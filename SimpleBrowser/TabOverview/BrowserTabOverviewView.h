#import <Cocoa/Cocoa.h>

@class BrowserTabOverviewCardView;
@class SBTextField;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserTabOverviewViewDelegate <NSObject>
- (void)tabOverviewViewDidRequestClose:(id)sender;
- (void)tabOverviewViewDidRequestNewTab:(id)sender;
- (void)tabOverviewView:(id)sender searchQueryDidChange:(NSString *)query;
- (void)tabOverviewViewDidClickBackground:(id)sender;
@end

@interface BrowserTabOverviewView : NSView

@property (nonatomic, weak, nullable) id<BrowserTabOverviewViewDelegate> delegate;
@property (nonatomic, strong, readonly) SBTextField *searchField;
@property (nonatomic, strong, readonly) NSScrollView *scrollView;
@property (nonatomic, strong, readonly) NSView *gridDocumentView;
@property (nonatomic, strong, readonly) NSTextField *titleLabel;
@property (nonatomic, strong, readonly) NSTextField *emptyLabel;

- (void)setTabCount:(NSUInteger)count;
- (void)setEmptyVisible:(BOOL)visible;
- (void)focusSearchField;
- (NSArray<BrowserTabOverviewCardView *> *)cardViews;
- (void)setCardViews:(NSArray<BrowserTabOverviewCardView *> *)cards;
- (void)relayoutGrid;

@end

NS_ASSUME_NONNULL_END
