#import <Foundation/Foundation.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperExcelWriter : NSObject

/// columnNames：优先列序（通常来自启用字段）；nil/空则从行数据推导。未声明键追加在末尾。
+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
               outputPath:(NSString *)outputPath
                 sinkType:(BrowserScraperSinkType)sinkType
              columnNames:(nullable NSArray<NSString *> *)columnNames
                    error:(NSError **)error;

/// 兼容旧调用。
+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
               outputPath:(NSString *)outputPath
                 sinkType:(BrowserScraperSinkType)sinkType
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
