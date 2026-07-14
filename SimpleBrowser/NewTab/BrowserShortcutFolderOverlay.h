#import <Cocoa/Cocoa.h>

@class BrowserShortcutFolderOverlay;
@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserShortcutFolderOverlayDelegate <NSObject>
- (void)folderOverlayDidRequestClose:(BrowserShortcutFolderOverlay *)overlay;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
              openURL:(NSURL *)url
            inNewTab:(BOOL)inNewTab;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
         renameFolder:(BrowserShortcutItem *)folder
                title:(NSString *)title;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
       removeShortcut:(BrowserShortcutItem *)shortcut;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
  moveShortcutToTopLevel:(BrowserShortcutItem *)shortcut;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
         editShortcut:(BrowserShortcutItem *)shortcut;
- (BOOL)folderOverlayIsEditingMode:(BrowserShortcutFolderOverlay *)overlay;

/// 夹内拖出到主网格：开始 / 移动 / 结束（含占位符与落点保存）。
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
didBeginDraggingChild:(BrowserShortcutItem *)child;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
draggingChild:(BrowserShortcutItem *)child
movedToWindowPoint:(NSPoint)windowPoint
       outsidePanel:(BOOL)outsidePanel;
- (void)folderOverlay:(BrowserShortcutFolderOverlay *)overlay
didEndDraggingChild:(BrowserShortcutItem *)child
     atWindowPoint:(NSPoint)windowPoint
      outsidePanel:(BOOL)outsidePanel;
@end

@interface BrowserShortcutFolderOverlay : NSView

@property (nonatomic, weak, nullable) id<BrowserShortcutFolderOverlayDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) BrowserShortcutItem *folder;

- (void)presentFolder:(BrowserShortcutItem *)folder
             children:(NSArray<BrowserShortcutItem *> *)children
       fromAnchorRect:(NSRect)anchorRect
               inView:(NSView *)hostView
             animated:(BOOL)animated;

- (void)dismissAnimated:(BOOL)animated completion:(nullable dispatch_block_t)completion;
- (void)reloadChildren:(NSArray<BrowserShortcutItem *> *)children;
- (void)beginRenaming;

/// 夹内图标拖出：由 cell 在超过拖拽阈值后调用。
- (BOOL)beginDraggingChild:(BrowserShortcutItem *)child
                  fromView:(NSView *)view
                     event:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
