#import <Cocoa/Cocoa.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const CGFloat BrowserTabStripHeight;

@class BrowserTabStripView;

@protocol BrowserTabStripViewDelegate <NSObject>
- (void)tabStripView:(id)stripView didSelectTabID:(NSUUID *)tabID;
- (void)tabStripView:(id)stripView didCloseTabID:(NSUUID *)tabID;
- (void)tabStripViewDidRequestNewTab:(id)stripView;

@optional
- (void)tabStripViewDidDoubleClickTitleBar:(BrowserTabStripView *)stripView;
@end

@interface BrowserTabStripView : NSView

@property (nonatomic, weak, nullable) id<BrowserTabStripViewDelegate> delegate;

- (void)reloadWithTabs:(NSArray<BrowserTab *> *)tabs selectedTabID:(nullable NSUUID *)selectedTabID;

@end

NS_ASSUME_NONNULL_END
