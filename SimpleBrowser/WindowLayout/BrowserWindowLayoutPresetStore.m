#import "BrowserWindowLayoutPresetStore.h"

static NSString * const kLargeFrameKey = @"BrowserWindowLayoutLargeFrame";
static NSString * const kSmallFrameKey = @"BrowserWindowLayoutSmallFrame";
static NSString * const kSmallTransparentKey = @"BrowserWindowLayoutSmallTransparent";

@implementation BrowserWindowLayoutPresetStore

+ (BOOL)hasLargeFramePreset {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kLargeFrameKey];
    return value.length > 0;
}

+ (NSRect)largeFramePreset {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kLargeFrameKey];
    if (value.length == 0) {
        return NSZeroRect;
    }
    return NSRectFromString(value);
}

+ (void)setLargeFramePreset:(NSRect)frame {
    if (NSIsEmptyRect(frame) || frame.size.width < 200 || frame.size.height < 200) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(frame) forKey:kLargeFrameKey];
}

+ (BOOL)hasSmallFramePreset {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kSmallFrameKey];
    return value.length > 0;
}

+ (NSRect)smallFramePreset {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kSmallFrameKey];
    if (value.length == 0) {
        return NSZeroRect;
    }
    return NSRectFromString(value);
}

+ (BOOL)smallTransparentPreset {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSmallTransparentKey];
}

+ (void)setSmallFramePreset:(NSRect)frame transparent:(BOOL)transparent {
    if (NSIsEmptyRect(frame) || frame.size.width < 200 || frame.size.height < 200) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:NSStringFromRect(frame) forKey:kSmallFrameKey];
    [defaults setBool:transparent forKey:kSmallTransparentKey];
}

+ (NSRect)defaultSmallFrameOnScreen:(NSScreen *)screen relativeTo:(NSRect)referenceFrame {
    NSScreen *target = screen ?: NSScreen.mainScreen;
    NSRect visible = target.visibleFrame;
    CGFloat width = 420;
    CGFloat height = 640;
    CGFloat x = NSMaxX(visible) - width - 40;
    CGFloat y = NSMinY(visible) + 40;
    if (!NSIsEmptyRect(referenceFrame)) {
        x = NSMaxX(referenceFrame) - width - 24;
        y = NSMinY(referenceFrame) + 24;
    }
    NSRect frame = NSMakeRect(x, y, width, height);
    return [self clampFrame:frame toVisibleScreen:target];
}

+ (NSRect)clampFrame:(NSRect)frame toVisibleScreen:(NSScreen *)screen {
    NSScreen *target = screen ?: NSScreen.mainScreen;
    if (!target) {
        return frame;
    }
    NSRect visible = target.visibleFrame;
    CGFloat width = MIN(MAX(frame.size.width, 320), visible.size.width);
    CGFloat height = MIN(MAX(frame.size.height, 240), visible.size.height);
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    if (x < NSMinX(visible)) {
        x = NSMinX(visible);
    }
    if (y < NSMinY(visible)) {
        y = NSMinY(visible);
    }
    if (x + width > NSMaxX(visible)) {
        x = NSMaxX(visible) - width;
    }
    if (y + height > NSMaxY(visible)) {
        y = NSMaxY(visible) - height;
    }
    return NSMakeRect(x, y, width, height);
}

@end
