#import <Cocoa/Cocoa.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat BrowserTabStripHeight;

/// 标签条背景色（窗口标题栏与之同色，避免 accessory 上方露白）
NSColor *BrowserTabStripFillColor(void);

@class BrowserTabStripView;

@protocol BrowserTabStripViewDelegate <NSObject>
- (void)tabStripView:(id)stripView didSelectTabID:(NSUUID *)tabID;
- (void)tabStripView:(id)stripView didCloseTabID:(NSUUID *)tabID;
- (void)tabStripViewDidRequestNewTab:(id)stripView;

@optional
- (void)tabStripViewDidDoubleClickTitleBar:(BrowserTabStripView *)stripView;
- (void)tabStripView:(id)stripView didCloseOtherTabsExceptTabID:(NSUUID *)tabID;
- (void)tabStripView:(id)stripView didCloseTabsToTheRightOfTabID:(NSUUID *)tabID;
- (void)tabStripViewDidRequestRestoreRecentlyClosedTab:(id)stripView;
- (BOOL)tabStripViewCanRestoreRecentlyClosedTab:(id)stripView;
- (BOOL)tabStripView:(id)stripView canCloseOtherTabsExceptTabID:(NSUUID *)tabID;
- (BOOL)tabStripView:(id)stripView canCloseTabsToTheRightOfTabID:(NSUUID *)tabID;
- (void)tabStripView:(id)stripView didMoveTabID:(NSUUID *)tabID toIndex:(NSUInteger)toIndex;
- (void)tabStripView:(id)stripView didSetPinned:(BOOL)pinned forTabID:(NSUUID *)tabID;
- (BOOL)tabStripView:(id)stripView isTabPinnedForTabID:(NSUUID *)tabID;
/// 将标签移到新浏览器窗口；screenPoint 非空时尽量把新窗口放在指针附近。
- (void)tabStripView:(id)stripView
didRequestMoveTabIDToNewWindow:(NSUUID *)tabID
         screenPoint:(NSPoint)screenPoint;
@end

@interface BrowserTabStripView : NSView

@property (nonatomic, weak, nullable) id<BrowserTabStripViewDelegate> delegate;

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID;
- (void)syncWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID;

@end

NS_ASSUME_NONNULL_END
