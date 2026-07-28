#import <Cocoa/Cocoa.h>

@class BrowserTab;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTabOverviewCardView : NSView

@property (nonatomic, strong, nullable) NSUUID *tabID;
@property (nonatomic, assign, getter=isCardSelected) BOOL cardSelected;
@property (nonatomic, assign, getter=isCardFocused) BOOL cardFocused;
@property (nonatomic, assign, getter=isPinned) BOOL pinned;
@property (nonatomic, assign, getter=isHibernated) BOOL hibernated;
@property (nonatomic, assign, getter=isNewTabPage) BOOL newTabPage;

@property (nonatomic, copy, nullable) void (^onSelect)(void);
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^contextMenuProvider)(void);

- (void)configureWithTitle:(NSString *)title
                 faviconURL:(nullable NSURL *)pageURL
              thumbnailImage:(nullable NSImage *)thumbnail;

- (void)setThumbnailImage:(nullable NSImage *)image;

@end

FOUNDATION_EXPORT CGFloat BrowserTabOverviewCardHeightForWidth(CGFloat width);

NS_ASSUME_NONNULL_END
