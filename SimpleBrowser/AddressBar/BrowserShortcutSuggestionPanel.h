#import <Cocoa/Cocoa.h>

@class BrowserShortcutItem;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserShortcutSuggestionPanelDelegate <NSObject>
- (void)suggestionPanelDidSelectItemAtIndex:(NSUInteger)index;
- (void)suggestionPanelDidOpenItemAtIndex:(NSUInteger)index;
- (void)suggestionPanelDidOpenItemAtIndexInNewTab:(NSUInteger)index;
- (void)suggestionPanelDidHoverItemAtIndex:(NSUInteger)index;
@end

@interface BrowserShortcutSuggestionPanel : NSPanel

@property (nonatomic, weak, nullable) id<BrowserShortcutSuggestionPanelDelegate> suggestionDelegate;

- (void)updateWithItems:(NSArray<BrowserShortcutItem *> *)items
                    query:(NSString *)query
           selectedIndex:(NSUInteger)selectedIndex
              anchorRect:(NSRect)anchorRectOnScreen;

- (void)setHighlightedIndex:(NSUInteger)index;

- (void)dismissPanel;

@end

NS_ASSUME_NONNULL_END
