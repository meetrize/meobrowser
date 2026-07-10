#import <Cocoa/Cocoa.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserShortcutEditorCompletionHandler)(BrowserShortcutItem * _Nullable item);

@interface BrowserShortcutEditorSheet : NSObject

+ (void)presentAddingShortcutOnWindow:(NSWindow *)parentWindow
                           completion:(BrowserShortcutEditorCompletionHandler)completion;

+ (void)presentEditingShortcut:(BrowserShortcutItem *)shortcut
                      onWindow:(NSWindow *)parentWindow
                    completion:(BrowserShortcutEditorCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
