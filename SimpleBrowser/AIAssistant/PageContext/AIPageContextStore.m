#import "AIPageContextStore.h"
#import "AIPageContextBundle.h"

@interface AIPageContextStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIPageContextBundle *> *byTab;
@end

@implementation AIPageContextStore

+ (AIPageContextStore *)sharedStore {
    static AIPageContextStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[AIPageContextStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _byTab = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)keyForTabID:(NSUUID *)tabID {
    return tabID.UUIDString ?: @"";
}

- (void)setBundle:(AIPageContextBundle *)bundle forTabID:(NSUUID *)tabID {
    if (!bundle || !tabID) return;
    bundle.tabID = tabID;
    self.byTab[[self keyForTabID:tabID]] = bundle;
}

- (AIPageContextBundle *)bundleForTabID:(NSUUID *)tabID {
    if (!tabID) return nil;
    return self.byTab[[self keyForTabID:tabID]];
}

- (void)markStaleForTabID:(NSUUID *)tabID {
    AIPageContextBundle *b = [self bundleForTabID:tabID];
    if (b) b.stale = YES;
}

- (void)removeBundleForTabID:(NSUUID *)tabID {
    if (!tabID) return;
    [self.byTab removeObjectForKey:[self keyForTabID:tabID]];
}

@end
