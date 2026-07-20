#import <Cocoa/Cocoa.h>
#import "BrowserFindSession.h"

@class BrowserFindBarView;
@class SBTextField;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserFindBarViewDelegate <NSObject>
- (void)findBarViewQueryDidChange:(BrowserFindBarView *)view;
- (void)findBarViewDidRequestNext:(BrowserFindBarView *)view;
- (void)findBarViewDidRequestPrevious:(BrowserFindBarView *)view;
- (void)findBarViewDidToggleMode:(BrowserFindBarView *)view;
- (void)findBarViewDidToggleCaseSensitive:(BrowserFindBarView *)view;
- (void)findBarViewDidRequestClose:(BrowserFindBarView *)view;
@end

@interface BrowserFindBarView : NSView

@property (nonatomic, weak, nullable) id<BrowserFindBarViewDelegate> delegate;
@property (nonatomic, strong, readonly) SBTextField *queryField;
@property (nonatomic, assign, readonly) BrowserFindMode mode;
@property (nonatomic, assign, readonly) BOOL caseSensitive;

- (void)applySession:(BrowserFindSession *)session;
- (void)setMode:(BrowserFindMode)mode;
- (void)setCaseSensitive:(BOOL)caseSensitive;
- (void)updateMatchCount:(NSInteger)current total:(NSInteger)total truncated:(BOOL)truncated invalid:(BOOL)invalid;
- (void)flashWrapHint;
- (void)focusAndSelectAll;
- (void)setNavigationEnabled:(BOOL)enabled;
- (void)setFindEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
