#import "AIBridgeRegistry.h"
#import "BrowserTab.h"

NSNotificationName const AIBridgeRegistryDidChangeNotification = @"AIBridgeRegistryDidChangeNotification";

@implementation AIBridgeBinding
@end

@interface AIBridgeRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIBridgeBinding *> *byBindingId;
@end

@implementation AIBridgeRegistry

+ (AIBridgeRegistry *)sharedRegistry {
    static AIBridgeRegistry *reg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reg = [[AIBridgeRegistry alloc] init];
    });
    return reg;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _byBindingId = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:AIBridgeRegistryDidChangeNotification object:self];
}

+ (NSString *)shortIdFromBindingId:(NSString *)bindingId {
    NSString *raw = [[bindingId ?: @"" stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    if (raw.length >= 6) {
        return [raw substringToIndex:6];
    }
    return raw.length ? raw : @"xxxxxx";
}

+ (NSString *)modelIdForProviderId:(NSString *)providerId bindingId:(NSString *)bindingId {
    (void)bindingId;
    NSString *pid = providerId.length ? providerId : @"unknown";
    return [NSString stringWithFormat:@"bridge__%@", pid];
}

+ (NSString *)providerIdFromModelId:(NSString *)modelId {
    if (![modelId hasPrefix:@"bridge__"]) {
        return nil;
    }
    NSString *rest = [modelId substringFromIndex:@"bridge__".length];
    NSRange sep = [rest rangeOfString:@"__"];
    if (sep.location != NSNotFound) {
        return [rest substringToIndex:sep.location];
    }
    return rest.length ? rest : nil;
}

- (NSArray<AIBridgeBinding *> *)allBindings {
    NSArray *all = self.byBindingId.allValues;
    return [all sortedArrayUsingComparator:^NSComparisonResult(AIBridgeBinding *a, AIBridgeBinding *b) {
        if (a.createdAt < b.createdAt) return NSOrderedAscending;
        if (a.createdAt > b.createdAt) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (NSArray<AIBridgeBinding *> *)bindingsForProviderId:(NSString *)providerId {
    if (providerId.length == 0) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (AIBridgeBinding *b in self.byBindingId.allValues) {
        if ([b.providerId isEqualToString:providerId]) {
            [out addObject:b];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(AIBridgeBinding *a, AIBridgeBinding *b) {
        if (a.createdAt < b.createdAt) return NSOrderedAscending;
        if (a.createdAt > b.createdAt) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return out;
}

- (AIBridgeBinding *)bindingForId:(NSString *)bindingId {
    if (bindingId.length == 0) {
        return nil;
    }
    return self.byBindingId[bindingId];
}

- (AIBridgeBinding *)bindingForProviderId:(NSString *)providerId {
    NSArray *list = [self bindingsForProviderId:providerId];
    return list.lastObject;
}

- (AIBridgeBinding *)bindingForModelId:(NSString *)modelId {
    if (modelId.length == 0) {
        return nil;
    }
    for (AIBridgeBinding *b in self.byBindingId.allValues) {
        if ([b.modelId isEqualToString:modelId]) {
            return b;
        }
    }
    // 固定名 / 旧长格式 bridge__provider(__short) → 按 provider 取最新
    NSString *pid = [AIBridgeRegistry providerIdFromModelId:modelId];
    if (pid.length == 0) {
        return nil;
    }
    return [self bindingForProviderId:pid];
}

- (AIBridgeBinding *)bindTab:(BrowserTab *)tab
                  providerId:(NSString *)providerId
                 displayName:(NSString *)displayName
                     pageURL:(NSString *)pageURL
                   sessionId:(NSString *)sessionId {
    if (!tab || providerId.length == 0) {
        return nil;
    }
    // 同 tab 或同 provider 已有绑定 → 卸掉（固定 modelId 每平台一条）
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *key in self.byBindingId) {
        AIBridgeBinding *b = self.byBindingId[key];
        if (b.tab == tab || [b.providerId isEqualToString:providerId]) {
            [remove addObject:key];
        }
    }
    for (NSString *key in remove) {
        AIBridgeBinding *old = self.byBindingId[key];
        if (old.tab && old.tab != tab) {
            old.tab.bridgeKeepsAlive = NO;
        }
        [self.byBindingId removeObjectForKey:key];
    }

    NSString *bindingId = [[NSUUID UUID] UUIDString];
    AIBridgeBinding *binding = [[AIBridgeBinding alloc] init];
    binding.bindingId = bindingId;
    binding.providerId = providerId;
    binding.modelId = [AIBridgeRegistry modelIdForProviderId:providerId bindingId:bindingId];
    binding.displayName = displayName.length ? displayName : providerId;
    binding.tab = tab;
    binding.tabTitle = tab.title;
    binding.pageURL = pageURL;
    binding.sessionId = sessionId;
    binding.createdAt = [NSDate date].timeIntervalSince1970;
    tab.bridgeKeepsAlive = YES;
    self.byBindingId[bindingId] = binding;
    [self notify];
    return binding;
}

- (void)unbindBindingId:(NSString *)bindingId {
    AIBridgeBinding *b = self.byBindingId[bindingId];
    if (!b) {
        return;
    }
    b.tab.bridgeKeepsAlive = NO;
    [self.byBindingId removeObjectForKey:bindingId];
    [self notify];
}

- (void)unbindProviderId:(NSString *)providerId {
    NSArray *list = [self bindingsForProviderId:providerId];
    if (list.count == 0) {
        return;
    }
    for (AIBridgeBinding *b in list) {
        b.tab.bridgeKeepsAlive = NO;
        [self.byBindingId removeObjectForKey:b.bindingId];
    }
    [self notify];
}

- (void)unbindTab:(BrowserTab *)tab {
    if (!tab) {
        return;
    }
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in self.byBindingId) {
        if (self.byBindingId[key].tab == tab) {
            [keys addObject:key];
        }
    }
    if (keys.count == 0) {
        return;
    }
    tab.bridgeKeepsAlive = NO;
    for (NSString *key in keys) {
        [self.byBindingId removeObjectForKey:key];
    }
    [self notify];
}

- (void)unbindAll {
    if (self.byBindingId.count == 0) {
        return;
    }
    for (AIBridgeBinding *b in self.byBindingId.allValues) {
        b.tab.bridgeKeepsAlive = NO;
    }
    [self.byBindingId removeAllObjects];
    [self notify];
}

@end
