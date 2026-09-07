#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// MeoBrowser 的 NSApplication 子类：从其他应用点回本应用时，只前置被点击的窗口，
/// 避免把其余浏览器窗口一并抬到最前（对齐 Safari / Finder 行为）。
@interface MeoApplication : NSApplication

/// 激活本应用但只抬起当前 key/main（或指定）窗口；其它窗口保持原有相对层级。
+ (void)activateFrontWindowOnlyPreferring:(nullable NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
