#import <Cocoa/Cocoa.h>

@class BrowserLaunchpadView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserLaunchpadViewDelegate <NSObject>
- (void)launchpadView:(BrowserLaunchpadView *)view openURL:(NSURL *)url;
- (void)launchpadView:(BrowserLaunchpadView *)view openURLInNewTab:(NSURL *)url;
@end

@interface BrowserLaunchpadView : NSView

@property (nonatomic, weak, nullable) id<BrowserLaunchpadViewDelegate> delegate;

- (void)reloadShortcuts;

@end

NS_ASSUME_NONNULL_END
