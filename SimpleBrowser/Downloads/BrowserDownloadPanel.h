#import <Cocoa/Cocoa.h>

@class BrowserDownloadManager;
@class BrowserDownloadPanel;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserDownloadPanelDelegate <NSObject>
- (void)downloadPanelDidRequestClose:(BrowserDownloadPanel *)panel;
@end

@interface BrowserDownloadPanel : NSPanel

@property (nonatomic, weak, nullable) id<BrowserDownloadPanelDelegate> panelDelegate;
@property (nonatomic, weak, nullable) BrowserDownloadManager *manager;

/// 点击该屏幕矩形（通常为下载按钮）时不关闭面板，由按钮自行 toggle。
@property (nonatomic, assign) NSRect dismissExclusionRectOnScreen;

- (void)reloadFromManager;
- (void)presentAnchoredToRect:(NSRect)anchorRectOnScreen ofWindow:(nullable NSWindow *)ownerWindow;
- (void)dismissPanel;

@end

NS_ASSUME_NONNULL_END
