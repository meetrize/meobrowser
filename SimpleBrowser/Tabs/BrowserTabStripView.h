#import <Cocoa/Cocoa.h>

@class BrowserTab;
@class BrowserTabStripView;
@class BrowserWindowController;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat BrowserTabStripHeight;
FOUNDATION_EXPORT const CGFloat BrowserTabStripHeightRegular;
FOUNDATION_EXPORT const CGFloat BrowserTabStripHeightCompact;

/// 标签条背景色（窗口标题栏与之同色，避免 accessory 上方露白）
NSColor *BrowserTabStripFillColor(void);

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
/// 将标签真迁移到其它浏览器窗口的指定下标。
- (void)tabStripView:(id)stripView
didRequestTransferTabID:(NSUUID *)tabID
           toWindow:(BrowserWindowController *)destination
            atIndex:(NSUInteger)index;
/// 标签条溢出菜单请求打开标签概览。
- (void)tabStripViewDidRequestShowTabOverview:(id)stripView;
@end

@interface BrowserTabStripView : NSView

@property (nonatomic, weak, nullable) id<BrowserTabStripViewDelegate> delegate;

/// 标签条右侧 Chrome 动作区（精简 / 置顶等）；置于「+」与 trailing 拖窗带之间。
@property (nonatomic, strong, nullable) NSView *chromeActionsView;

/// 精简模式下的前进/后退容器；置于交通灯右侧。nil = 常态无左侧导航。
@property (nonatomic, strong, nullable) NSView *leadingNavigationView;

/// 精简 metrics：更矮条高、更紧 inset。
@property (nonatomic, assign) BOOL compactMetricsEnabled;

/// 当前条高（随 compactMetricsEnabled 变化）。
@property (nonatomic, assign, readonly) CGFloat effectiveStripHeight;

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID;
- (void)syncWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID;

/// 标签条命中区（屏幕坐标，已外扩）。
- (NSRect)stripEffectiveZoneInScreen;

/// 跨窗拖放占位。
- (void)showForeignDropPlaceholderAtIndex:(NSUInteger)index;
- (void)updateForeignDropPlaceholderAtIndex:(NSUInteger)index;
- (void)hideForeignDropPlaceholder;
- (NSUInteger)insertionIndexForForeignDropAtScreenPoint:(NSPoint)screenPoint pinned:(BOOL)pinned;

@end

NS_ASSUME_NONNULL_END
