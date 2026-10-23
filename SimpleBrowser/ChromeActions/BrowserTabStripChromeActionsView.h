#import <Cocoa/Cocoa.h>

@class BrowserChromeActionItem;

NS_ASSUME_NONNULL_BEGIN

/// 标签条右侧窗口级 Chrome 动作区（精简 / 置顶等），可扩展注册表。
/// 左侧竖三点可拖拽改宽；变窄时右侧图标溢入 ⋯ 菜单，变宽时再显示。
@interface BrowserTabStripChromeActionsView : NSView

@property (nonatomic, copy, readonly) NSArray<BrowserChromeActionItem *> *items;

/// 宽度变化时通知标签条刷新约束（通常由 BrowserTabStripView 接线）。
@property (nonatomic, copy, nullable) void (^onPreferredWidthDidChange)(void);

/// 正在拖拽改宽（标签条据此做同步 layout，避免拖柄跟手滞后）。
@property (nonatomic, assign, readonly) BOOL isResizingWidth;

/// 兼容旧调用：当前 layout 下的可见项 + moreMenu。
+ (NSArray<BrowserChromeActionItem *> *)defaultItems;

/// 按 LayoutStore 组装可见项（末尾固定 moreMenu）。
+ (NSArray<BrowserChromeActionItem *> *)itemsForCurrentLayout;

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items;
- (void)reloadFromLayoutStore;
- (nullable NSButton *)buttonForItemID:(NSString *)itemID;
- (void)setOn:(BOOL)on forItemID:(NSString *)itemID;
- (BOOL)isOnForItemID:(NSString *)itemID;

/// 供标签条扣减中间可用宽度（含左侧拖拽柄）。
- (CGFloat)preferredWidth;

/// 因宽度不足而暂时藏进 ⋯ 的 pinned 动作 id（不含用户主动隐藏项）。
- (NSArray<NSString *> *)widthOverflowedActionIDs;

@end

NS_ASSUME_NONNULL_END
