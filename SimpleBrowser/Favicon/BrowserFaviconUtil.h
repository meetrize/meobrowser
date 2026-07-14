#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 从页面 / 快捷方式 URL 取出小写 host；无 host 返回 nil。保留 www. 前缀。
FOUNDATION_EXPORT NSString * _Nullable BrowserFaviconHostFromURLString(NSString * _Nullable urlString);

/// data 能否解码为尺寸有效的 NSImage。
FOUNDATION_EXPORT BOOL BrowserFaviconIsDecodableImageData(NSData * _Nullable data);

/// 解码成功返回 NSImage，否则 nil。多尺寸 ICO 时选取像素面积最大的一帧。
FOUNDATION_EXPORT NSImage * _Nullable BrowserFaviconImageFromData(NSData * _Nullable data);

/// 图像像素最长边；无法取得像素尺寸时回退到 size。
FOUNDATION_EXPORT NSUInteger BrowserFaviconMaxPixelEdge(NSImage * _Nullable image);

typedef NS_ENUM(NSInteger, BrowserFaviconIconFitStyle) {
    /// 异形 / 圆形：放在圆角矩形底板内并留白（如 Bilibili、Apple）。
    BrowserFaviconIconFitInset = 0,
    /// 圆角矩形图案：铺满快捷方式槽位（如知乎、HN）。
    BrowserFaviconIconFitFillRoundedRect = 1,
};

/// 分析图标外形；Fill 时 outDisplayImage 为裁到内容包围盒后的图（便于 100% 铺满）。
FOUNDATION_EXPORT BrowserFaviconIconFitStyle
BrowserFaviconAnalyzeIconForDisplay(NSImage *image,
                                    NSImage * _Nullable * _Nullable outDisplayImage);

/// 兼容：是否应按圆角矩形铺满显示。
FOUNDATION_EXPORT BOOL BrowserFaviconImageLooksPreRounded(NSImage * _Nullable image);

/// 将位图最长边缩至 ≤ maxPixelEdge，输出 PNG data；失败返回 nil。
FOUNDATION_EXPORT NSData * _Nullable BrowserFaviconPNGDataByScalingImage(NSImage *image, NSUInteger maxPixelEdge);

NS_ASSUME_NONNULL_END
