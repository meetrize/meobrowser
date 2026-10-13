#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 1px 细分隔线,hover 高亮,拖拽回调改 weights。
@interface BrowserThinDivider : NSView
@property (nonatomic, assign) BOOL vertical; // YES=左右栏之间的竖线
@property (nonatomic, copy, nullable) void (^dragDeltaHandler)(CGFloat delta);
@property (nonatomic, copy, nullable) void (^dragDidEndHandler)(void);
@end

NS_ASSUME_NONNULL_END
