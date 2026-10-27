#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 非默认浏览器时显示在工具栏下方的提示条；点击打开系统「默认网页浏览器」设置。
@interface BrowserDefaultBrowserTipBar : NSView

- (void)refreshVisibility;

@end

NS_ASSUME_NONNULL_END
