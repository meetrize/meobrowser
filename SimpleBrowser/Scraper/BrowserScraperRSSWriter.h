#import <Foundation/Foundation.h>

@class BrowserScraperRecipe;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperRSSWriter : NSObject

/// 将爬虫行字典启发式映射为 RSS 2.0 XML（UTF-8）。
+ (NSData *)RSS2DataFromRows:(NSArray<NSDictionary *> *)rows
                      recipe:(BrowserScraperRecipe *)recipe;

@end

NS_ASSUME_NONNULL_END
