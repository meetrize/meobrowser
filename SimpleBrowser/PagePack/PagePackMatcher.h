#import <Foundation/Foundation.h>

@class PagePack;

NS_ASSUME_NONNULL_BEGIN

@interface PagePackMatcher : NSObject

/// 为当前 URL 生成默认 match（如 https://example.com/*）。
+ (NSString *)defaultMatchForURL:(nullable NSURL *)url;

+ (BOOL)URL:(nullable NSURL *)url matchesPattern:(NSString *)pattern;
+ (BOOL)URL:(nullable NSURL *)url matchesPack:(PagePack *)pack;

@end

NS_ASSUME_NONNULL_END
