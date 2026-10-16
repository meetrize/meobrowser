#import "BrowserSplitPresetStore.h"

static NSString * const kKey = @"meo.split.presets.v1";
static const NSInteger kMax = 20;

@implementation BrowserSplitPresetStore

+ (NSInteger)maxCount { return kMax; }

+ (NSArray<NSDictionary *> *)allPresets {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kKey];
    if (![a isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in a) if ([e isKindOfClass:[NSDictionary class]]) [out addObject:e];
    return out;
}

+ (BOOL)savePreset:(NSDictionary *)preset error:(NSString * _Nullable * _Nullable)outError {
    NSMutableArray *all = [[self allPresets] mutableCopy];
    NSString *name = preset[@"name"];
    if (name.length == 0) { if (outError) *outError = @"名称为空"; return NO; }
    NSUInteger found = [all indexOfObjectPassingTest:^BOOL(NSDictionary *e, NSUInteger __unused i, BOOL *__unused s) {
        return [e[@"name"] isEqualToString:name];
    }];
    if (found != NSNotFound) { all[found] = preset; }
    else {
        if (all.count >= kMax) { if (outError) *outError = @"预设已满20个,请先删除"; return NO; }
        [all addObject:preset];
    }
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:kKey];
    return YES;
}

+ (void)deletePresetNamed:(NSString *)name {
    NSMutableArray *all = [[self allPresets] mutableCopy];
    NSUInteger found = [all indexOfObjectPassingTest:^BOOL(NSDictionary *e, NSUInteger __unused i, BOOL *__unused s) {
        return [e[@"name"] isEqualToString:name];
    }];
    if (found != NSNotFound) {
        [all removeObjectAtIndex:found];
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:kKey];
    }
}

+ (void)replaceAll:(NSArray<NSDictionary *> *)presets {
    [[NSUserDefaults standardUserDefaults] setObject:presets forKey:kKey];
}

@end
