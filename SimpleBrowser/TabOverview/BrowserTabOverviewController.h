#import <Cocoa/Cocoa.h>

@class BrowserWindowController;
@class BrowserTabOverviewView;
@class BrowserTabThumbnailCache;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTabOverviewController : NSObject

@property (nonatomic, weak, nullable) BrowserWindowController *windowController;
@property (nonatomic, strong, readonly) BrowserTabOverviewView *overviewView;
@property (nonatomic, assign, readonly, getter=isVisible) BOOL visible;
@property (nonatomic, strong, readonly) BrowserTabThumbnailCache *thumbnailCache;

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController;

- (void)installInContentContainer:(NSView *)contentContainer;
- (void)showOverview;
- (void)hideOverview;
- (IBAction)toggleOverview:(nullable id)sender;
- (void)reloadFromTabController;
- (void)bringToFront;
- (void)captureThumbnailForLeavingTabIfNeeded;
- (void)updateThumbnailForSelectedTabIfVisible;

@end

NS_ASSUME_NONNULL_END
