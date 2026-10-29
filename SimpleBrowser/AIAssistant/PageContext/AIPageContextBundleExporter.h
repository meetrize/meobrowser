#import <Foundation/Foundation.h>

@class AIPageContextBundle;

NS_ASSUME_NONNULL_BEGIN

@interface AIPageContextBundleExporter : NSObject

+ (NSDictionary *)dictionaryFromBundle:(AIPageContextBundle *)bundle
                     includeResources:(BOOL)includeResources
                        includeBodies:(BOOL)includeBodies;

+ (nullable NSData *)JSONDataFromBundle:(AIPageContextBundle *)bundle
                      includeResources:(BOOL)includeResources
                         includeBodies:(BOOL)includeBodies
                                 error:(NSError *_Nullable *_Nullable)error;

/// 写入下载目录或指定路径；返回最终路径。
+ (nullable NSString *)exportBundle:(AIPageContextBundle *)bundle
                         toDirectory:(NSString *)directory
                               error:(NSError *_Nullable *_Nullable)error;

+ (void)copyBundleJSONToPasteboard:(AIPageContextBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
