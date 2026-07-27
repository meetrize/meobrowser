#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 助手侧栏偏好（宽度等）。
@interface AssistSidebarSettings : NSObject

+ (instancetype)sharedSettings;

/// 侧栏宽度（pt），默认 360；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

@end

NS_ASSUME_NONNULL_END
