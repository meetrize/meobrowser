#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 锚定在设置按钮旁的轻量外观面板（由 NSPopover 承载）。
@interface BrowserLaunchpadAppearancePanel : NSView

@property (nonatomic, readonly) NSSize preferredContentSize;

+ (NSSize)preferredPanelSize;
- (void)reloadFromAppearance;

@end

NS_ASSUME_NONNULL_END
