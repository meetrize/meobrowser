#import "AIBridgeRegistry.h"
#import "BrowserTab.h"

NSNotificationName const AIBridgeRegistryDidChangeNotification = @"AIBridgeRegistryDidChangeNotification";

@implementation AIBridgeBinding
@end

@interface AIBridgeRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIBridgeBinding *> *byProvider;
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
        _byProvider = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:AIBridgeRegistryDidChangeNotification object:self];
}

- (NSArray<AIBridgeBinding *> *)allBindings {
    return self.byProvider.allValues;
}

- (AIBridgeBinding *)bindingForProviderId:(NSString *)providerId {
    if (providerId.length == 0) {
        return nil;
    }
    return self.byProvider[providerId];
}

- (AIBridgeBinding *)bindingForModelId:(NSString *)modelId {
    if (modelId.length == 0) {
        return nil;
    }
    for (AIBridgeBinding *b in self.byProvider.allValues) {
        if ([b.modelId isEqualToString:modelId]) {
            return b;
        }
    }
    return nil;
}

- (void)bindTab:(BrowserTab *)tab
     providerId:(NSString *)providerId
       modelId:(NSString *)modelId
   displayName:(NSString *)displayName
       pageURL:(NSString *)pageURL {
    if (!tab || providerId.length == 0 || modelId.length == 0) {
        return;
    }
    // Clear previous keep-alive on same provider or same tab
    AIBridgeBinding *existing = self.byProvider[providerId];
    if (existing.tab && existing.tab != tab) {
        existing.tab.bridgeKeepsAlive = NO;
    }
    for (NSString *key in self.byProvider.allKeys.copy) {
        AIBridgeBinding *b = self.byProvider[key];
        if (b.tab == tab && ![key isEqualToString:providerId]) {
            b.tab.bridgeKeepsAlive = NO;
            [self.byProvider removeObjectForKey:key];
        }
    }

    AIBridgeBinding *binding = [[AIBridgeBinding alloc] init];
    binding.providerId = providerId;
    binding.modelId = modelId;
    binding.displayName = displayName.length ? displayName : providerId;
    binding.tab = tab;
    binding.tabTitle = tab.title;
    binding.pageURL = pageURL;
    tab.bridgeKeepsAlive = YES;
    self.byProvider[providerId] = binding;
    [self notify];
}

- (void)unbindProviderId:(NSString *)providerId {
    AIBridgeBinding *b = self.byProvider[providerId];
    if (!b) {
        return;
    }
    b.tab.bridgeKeepsAlive = NO;
    [self.byProvider removeObjectForKey:providerId];
    [self notify];
}

- (void)unbindTab:(BrowserTab *)tab {
    if (!tab) {
        return;
    }
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in self.byProvider) {
        if (self.byProvider[key].tab == tab) {
            [keys addObject:key];
        }
    }
    if (keys.count == 0) {
        return;
    }
    tab.bridgeKeepsAlive = NO;
    for (NSString *key in keys) {
        [self.byProvider removeObjectForKey:key];
    }
    [self notify];
}

- (void)unbindAll {
    if (self.byProvider.count == 0) {
        return;
    }
    for (AIBridgeBinding *b in self.byProvider.allValues) {
        b.tab.bridgeKeepsAlive = NO;
    }
    [self.byProvider removeAllObjects];
    [self notify];
}

@end
