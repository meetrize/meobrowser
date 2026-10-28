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
    NSString *pid = providerId.length ? providerId : @"unknown";
    return [NSString stringWithFormat:@"bridge__%@__%@", pid, [self shortIdFromBindingId:bindingId]];
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
    // 短名 bridge__provider：仅唯一绑定时命中
    if (![modelId hasPrefix:@"bridge__"]) {
        return nil;
    }
    NSString *rest = [modelId substringFromIndex:@"bridge__".length];
    if ([rest containsString:@"__"]) {
        // 长格式未命中
        return nil;
    }
    NSArray *list = [self bindingsForProviderId:rest];
    if (list.count == 1) {
        return list.firstObject;
    }
    return nil;
}

- (AIBridgeBinding *)bindTab:(BrowserTab *)tab
                  providerId:(NSString *)providerId
                 displayName:(NSString *)displayName
                     pageURL:(NSString *)pageURL
                   sessionId:(NSString *)sessionId {
    if (!tab || providerId.length == 0) {
        return nil;
    }
    // 同 tab 已有绑定 → 卸掉
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *key in self.byBindingId) {
        AIBridgeBinding *b = self.byBindingId[key];
        if (b.tab == tab) {
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
