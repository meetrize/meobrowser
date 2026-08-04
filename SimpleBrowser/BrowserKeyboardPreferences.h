#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserKeyboardPreferencesDidChangeNotification;

/// macOS F5 物理键码（与 F3=99 同属功能键区）。
FOUNDATION_EXPORT const unsigned short BrowserReloadShortcutDefaultKeyCode;

@interface BrowserKeyboardPreferences : NSObject

/// 刷新页面快捷键；默认 F5、无修饰键。
+ (unsigned short)reloadShortcutKeyCode;
+ (NSEventModifierFlags)reloadShortcutModifierFlags;
+ (void)setReloadShortcutKeyCode:(unsigned short)keyCode
                   modifierFlags:(NSEventModifierFlags)modifierFlags;
/// 从按键事件写入快捷键（同时记录可读字符，便于显示字母键）。
+ (void)setReloadShortcutFromEvent:(NSEvent *)event;
+ (void)resetReloadShortcutToDefault;

/// 是否启用自定义刷新快捷键（默认 YES）；⌘R 菜单项不受影响。
+ (BOOL)reloadShortcutEnabled;
+ (void)setReloadShortcutEnabled:(BOOL)enabled;

+ (BOOL)eventMatchesReloadShortcut:(NSEvent *)event;
+ (NSString *)displayStringForReloadShortcut;
+ (NSString *)displayStringForKeyCode:(unsigned short)keyCode
                        modifierFlags:(NSEventModifierFlags)modifierFlags;

@end

NS_ASSUME_NONNULL_END
