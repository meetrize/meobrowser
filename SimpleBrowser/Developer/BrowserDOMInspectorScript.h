#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 页面侧探针脚本，运行时返回完整 JS 源码。
@interface BrowserDOMInspectorScript : NSObject

/// 探针实现：定义全部逻辑并暴露 window.__meoDomInspectorStart / __meoDomInspectorStop。
/// 该段以 WKUserScript 形式下发到每个框架（含跨源 iframe），因此不能依赖父页面。
+ (NSString *)startScript;

/// 引导脚本：在每个框架（含跨源 iframe）注册启停入口与消息转发。
+ (NSString *)bootstrapScript;

/// 开关脚本：调用 window.__meoDomInspectorStart() / __meoDomInspectorStop()。
/// 用于在探针已注入的前提下启停。
+ (NSString *)enableScript;
+ (NSString *)disableScript;

@end

NS_ASSUME_NONNULL_END
