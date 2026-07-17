#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserFeedItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy, nullable) NSString *mimeType;
@end

NS_ASSUME_NONNULL_END
