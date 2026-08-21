#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWindowController;

@interface BrowserAutoScrollController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) void (^didDisableHandler)(void);

- (void)applySpeedFromPreferences;
- (void)stopBecauseInterrupted;
- (void)stopBecauseReachedBottom;

@end

NS_ASSUME_NONNULL_END
