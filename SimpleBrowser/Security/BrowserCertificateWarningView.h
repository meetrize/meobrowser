#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserCertificateWarningView;

@protocol BrowserCertificateWarningViewDelegate <NSObject>
- (void)certificateWarningViewDidChooseGoBack:(BrowserCertificateWarningView *)view;
- (void)certificateWarningViewDidChooseProceed:(BrowserCertificateWarningView *)view;
@end

/// 内容区证书警告 interstitial（原生视图）。
@interface BrowserCertificateWarningView : NSView

@property (nonatomic, weak, nullable) id<BrowserCertificateWarningViewDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *hostDisplay;

- (void)configureWithHost:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
