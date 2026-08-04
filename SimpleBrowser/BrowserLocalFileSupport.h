#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地 HTML 预览：扩展名白名单、路径 → file URL、WKWebView 加载辅助。
@interface BrowserLocalFileSupport : NSObject

+ (NSSet<NSString *> *)previewablePathExtensions;

+ (BOOL)isPreviewablePathExtension:(nullable NSString *)extension;
+ (BOOL)isPreviewableFileURL:(nullable NSURL *)url;
/// 将 Finder / openURLs 传入的 file URL 规范为可加载的 path URL；不可预览时返回 nil。
+ (nullable NSURL *)normalizedPreviewableFileURL:(nullable NSURL *)url;
+ (BOOL)isPreviewableFileAtPath:(nullable NSString *)path;

/// 将用户输入（绝对路径 / ~/… / 带引号路径 / file://）解析为可预览的 file URL；否则 nil。
+ (nullable NSURL *)previewableFileURLFromUserInput:(NSString *)input;

/// 展开 ~、去掉首尾引号后的本地路径；不是路径形态时返回 nil。
+ (nullable NSString *)expandedLocalPathFromUserInput:(NSString *)input;

/// 用 loadFileURL:allowingReadAccessToURL: 加载本地文件（读权限为所在目录）；非 file URL 返回 NO。
+ (BOOL)loadFileURL:(NSURL *)url inWebView:(id)webView;

@end

NS_ASSUME_NONNULL_END
