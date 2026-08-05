#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 浏览历史侧栏偏好（宽度等）。
@interface BrowserHistorySettings : NSObject

+ (instancetype)sharedSettings;

/// 侧栏宽度（pt），默认 380；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

@end

NS_ASSUME_NONNULL_END
