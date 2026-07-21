#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 地址栏「搜索 vs 导航」启发式：识别无协议主机、IP、localhost、端口与路径等。
@interface BrowserURLInputClassifier : NSObject

/// 判断用户输入是否更像可导航的网址（可不含 http/https）。
+ (BOOL)looksLikeURL:(NSString *)input;

/// 将用户输入规范化为可加载的 URL；不像网址时返回 nil（由调用方改走搜索）。
+ (nullable NSURL *)navigableURLFromInput:(NSString *)input;

@end

NS_ASSUME_NONNULL_END
