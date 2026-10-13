#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 分栏预设持久化:UserDefaults meo.split.presets.v1,上限20。
/// item = @{name, layout:@(int), weights:@[@..], urls:@[@"https://.."], chrome:@(int)}
@interface BrowserSplitPresetStore : NSObject
+ (NSArray<NSDictionary *> *)allPresets;
+ (BOOL)savePreset:(NSDictionary *)preset error:(NSString **)outError; // 同名覆盖
+ (void)deletePresetNamed:(NSString *)name;
+ (void)replaceAll:(NSArray<NSDictionary *> *)presets;
+ (NSInteger)maxCount;
@end

NS_ASSUME_NONNULL_END
