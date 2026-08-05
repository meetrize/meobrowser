#import <Cocoa/Cocoa.h>

@class BrowserHistorySidebarController;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserHistorySidebarControllerDelegate <NSObject>
- (void)historySidebarDidRequestClose:(BrowserHistorySidebarController *)controller;
- (void)historySidebar:(BrowserHistorySidebarController *)controller
               openURL:(NSURL *)url
              inNewTab:(BOOL)inNewTab;
- (void)historySidebar:(BrowserHistorySidebarController *)controller didChangeWidth:(CGFloat)width;
@end

/// 右侧浏览历史侧栏：搜索、时间范围分段、按日分组列表。
@interface BrowserHistorySidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<BrowserHistorySidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
- (void)reloadList;

@end

NS_ASSUME_NONNULL_END
