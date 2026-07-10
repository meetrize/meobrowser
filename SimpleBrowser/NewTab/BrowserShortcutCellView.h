#import <Cocoa/Cocoa.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserShortcutCellActivateHandler)(BrowserShortcutItem *item, BOOL openInNewTab);
typedef void (^BrowserShortcutCellActionHandler)(BrowserShortcutItem *item);

@interface BrowserShortcutCellView : NSCollectionViewItem

@property (nonatomic, strong, nullable) BrowserShortcutItem *shortcut;
@property (nonatomic, assign, getter=isEditingMode) BOOL editingMode;
@property (nonatomic, assign, getter=isAddCell) BOOL addCell;
@property (nonatomic, copy, nullable) BrowserShortcutCellActivateHandler onActivate;
@property (nonatomic, copy, nullable) BrowserShortcutCellActionHandler onDelete;
@property (nonatomic, copy, nullable) dispatch_block_t onAddTapped;
@property (nonatomic, copy, nullable) dispatch_block_t onRequestEditMode;

- (void)configureWithShortcut:(BrowserShortcutItem *)shortcut;
- (void)configureAsAddCell;

@end

NS_ASSUME_NONNULL_END
