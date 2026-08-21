#import <Cocoa/Cocoa.h>

@class BrowserChromeActionItem;

NS_ASSUME_NONNULL_BEGIN

/// 标签条右侧窗口级 Chrome 动作区（精简 / 置顶等），可扩展注册表。
@interface BrowserTabStripChromeActionsView : NSView

@property (nonatomic, copy, readonly) NSArray<BrowserChromeActionItem *> *items;

/// 兼容旧调用：当前 layout 下的可见项 + moreMenu。
+ (NSArray<BrowserChromeActionItem *> *)defaultItems;

/// 按 LayoutStore 组装可见项（末尾固定 moreMenu）。
+ (NSArray<BrowserChromeActionItem *> *)itemsForCurrentLayout;

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items;
- (void)reloadFromLayoutStore;
- (nullable NSButton *)buttonForItemID:(NSString *)itemID;
- (void)setOn:(BOOL)on forItemID:(NSString *)itemID;
- (BOOL)isOnForItemID:(NSString *)itemID;

/// 供标签条扣减中间可用宽度。
- (CGFloat)preferredWidth;

@end

NS_ASSUME_NONNULL_END
