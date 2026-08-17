#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserNavigationErrorView;

@protocol BrowserNavigationErrorViewDelegate <NSObject>
- (void)navigationErrorViewDidChooseReload:(BrowserNavigationErrorView *)view;
- (void)navigationErrorViewDidChooseGoBack:(BrowserNavigationErrorView *)view;
@end

/// 内容区导航失败 interstitial（原生视图），替代 NSAlert。
@interface BrowserNavigationErrorView : NSView

@property (nonatomic, weak, nullable) id<BrowserNavigationErrorViewDelegate> delegate;

- (void)configureWithTitle:(NSString *)title
                   message:(NSString *)message
                showGoBack:(BOOL)showGoBack
          reloadButtonTitle:(nullable NSString *)reloadButtonTitle;

@end

NS_ASSUME_NONNULL_END
