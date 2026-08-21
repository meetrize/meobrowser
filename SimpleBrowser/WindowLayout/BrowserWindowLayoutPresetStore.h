#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserWindowLayoutMode) {
    BrowserWindowLayoutModeFree = 0,
    BrowserWindowLayoutModeLarge = 1,
    BrowserWindowLayoutModeSmall = 2,
};

@interface BrowserWindowLayoutPresetStore : NSObject

+ (BOOL)hasLargeFramePreset;
+ (NSRect)largeFramePreset;
+ (void)setLargeFramePreset:(NSRect)frame;

+ (BOOL)hasSmallFramePreset;
+ (NSRect)smallFramePreset;
+ (BOOL)smallTransparentPreset;
+ (void)setSmallFramePreset:(NSRect)frame transparent:(BOOL)transparent;

/// 首次小窗默认尺寸（未写过预设时）。
+ (NSRect)defaultSmallFrameOnScreen:(nullable NSScreen *)screen relativeTo:(NSRect)referenceFrame;

/// 将 frame 钳到屏幕可见区域。
+ (NSRect)clampFrame:(NSRect)frame toVisibleScreen:(nullable NSScreen *)screen;

@end

NS_ASSUME_NONNULL_END
