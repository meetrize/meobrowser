#import <Cocoa/Cocoa.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserShortcutCellActivateHandler)(BrowserShortcutItem *item, BOOL openInNewTab);

@interface BrowserShortcutCellView : NSCollectionViewItem

@property (nonatomic, strong, nullable) BrowserShortcutItem *shortcut;
@property (nonatomic, assign, getter=isMergeHighlighted) BOOL mergeHighlighted;
@property (nonatomic, copy, nullable) BrowserShortcutCellActivateHandler onActivate;
@property (nonatomic, copy, nullable) dispatch_block_t onAddTapped;

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut;
- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut
                     children:(NSArray<BrowserShortcutItem *> *)children;
- (void)configureAsAddCell;
- (void)applyIconSize:(CGFloat)iconSize;
- (void)applyTitleColor:(NSColor *)color;

/// 拖拽代理图（半透明图标影子）；contentView 为 cell 的 view。
+ (nullable NSImage *)draggingProxyImageFromContentView:(NSView *)contentView
                                                  alpha:(CGFloat)alpha;
+ (NSRect)draggingProxyFrameFromContentView:(NSView *)contentView
                                     inView:(NSView *)targetView;

@end

NS_ASSUME_NONNULL_END
