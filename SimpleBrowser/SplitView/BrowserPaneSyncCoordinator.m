#import "BrowserPaneSyncCoordinator.h"

@implementation BrowserPaneSyncCoordinator {
    NSMutableDictionary<NSNumber *, NSDictionary *> *_fps;
    BOOL _syncing;
    BOOL _picking;
}

- (instancetype)init {
    self = [super init];
    if (self) { _fps = [NSMutableDictionary dictionary]; _masterPaneIndex = 0; }
    return self;
}

- (BOOL)isSyncing { return _syncing; }
- (BOOL)isPicking { return _picking; }
- (NSDictionary *)fingerprints { return [_fps copy]; }

- (void)startPickWithPaneCount:(NSInteger)count {
    [_fps removeAllObjects];
    _picking = YES; _syncing = NO;
    if (self.statusDidChangeHandler) self.statusDidChangeHandler([self statusTextForPaneCount:count]);
}

- (void)cancelAll {
    [_fps removeAllObjects];
    _picking = NO; _syncing = NO;
    if (self.statusDidChangeHandler) self.statusDidChangeHandler(@"同步已关闭");
}

- (void)setFingerprint:(NSDictionary *)fp forPane:(NSInteger)index {
    if (fp) _fps[@(index)] = fp;
    else [_fps removeObjectForKey:@(index)];
}

- (BOOL)allPairedForPaneCount:(NSInteger)count {
    if (count <= 1) return NO;
    return _fps.count >= (NSUInteger)count;
}

- (void)beginSyncWithMaster:(NSInteger)master {
    _masterPaneIndex = master;
    _picking = NO; _syncing = YES;
}

- (NSString *)escapedString:(NSString *)s {
    NSMutableString *m = [s mutableCopy] ?: [NSMutableString string];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"'" withString:@"\\'" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

- (NSString *)fpJSON:(NSDictionary *)fp {
    if (!fp) return @"null";
    NSData *d = [NSJSONSerialization dataWithJSONObject:fp options:0 error:nil];
    return [[NSString alloc] initWithData:d ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"null";
}

- (NSString *)applyValueJS:(NSString *)value fp:(NSDictionary *)fp {
    return [NSString stringWithFormat:@"window.meoSyncApplyValue('%@',%@)", [self escapedString:value ?: @""], [self fpJSON:fp]];
}

- (NSString *)submitJS:(NSDictionary *)fp {
    return [NSString stringWithFormat:@"window.meoSyncSubmit(%@)", [self fpJSON:fp]];
}

- (NSString *)statusTextForPaneCount:(NSInteger)count {
    if (_syncing) return [NSString stringWithFormat:@"同步中 %lu/%ld", (unsigned long)_fps.count, (long)count];
    if (_picking) return [NSString stringWithFormat:@"请点击各栏表单 %lu/%ld", (unsigned long)_fps.count, (long)count];
    return @"同步已关闭";
}

@end
