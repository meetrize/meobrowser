#import <Foundation/Foundation.h>
#import "BrowserScraperModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperMySQLWriter : NSObject

+ (BOOL)isAvailable;

+ (nullable NSString *)passwordForAccount:(NSString *)account;
+ (BOOL)setPassword:(NSString *)password forAccount:(NSString *)account error:(NSError **)error;

+ (BOOL)testConnection:(BrowserScraperMySQLConfig *)config
              password:(NSString *)password
                 error:(NSError **)error;

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
                   config:(BrowserScraperMySQLConfig *)config
              columnNames:(nullable NSArray<NSString *> *)columnNames
                    error:(NSError **)error;

+ (BOOL)writeNDJSONAtPath:(NSString *)ndjsonPath
                   config:(BrowserScraperMySQLConfig *)config
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
