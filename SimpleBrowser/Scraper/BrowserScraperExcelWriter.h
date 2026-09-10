#import <Foundation/Foundation.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperExcelWriter : NSObject

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
               outputPath:(NSString *)outputPath
                 sinkType:(BrowserScraperSinkType)sinkType
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
