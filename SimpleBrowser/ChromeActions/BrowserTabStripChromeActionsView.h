#import <Cocoa/Cocoa.h>

@class BrowserChromeActionItem;

NS_ASSUME_NONNULL_BEGIN

/// 标签条右侧窗口级 Chrome 动作区（精简 / 置顶等），可扩展注册表。
@interface BrowserTabStripChromeActionsView : NSView

@property (nonatomic, copy, readonly) NSArray<BrowserChromeActionItem *> *items;

+ (NSArray<BrowserChromeActionItem *> *)defaultItems;

- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items;
- (nullable NSButton *)buttonForItemID:(NSString *)itemID;
- (void)setOn:(BOOL)on forItemID:(NSString *)itemID;
- (BOOL)isOnForItemID:(NSString *)itemID;

/// 供标签条扣减中间可用宽度。
- (CGFloat)preferredWidth;

@end

NS_ASSUME_NONNULL_END
