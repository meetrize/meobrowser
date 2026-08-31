#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 助手侧栏偏好（宽度、详情区高度等）。
@interface AssistSidebarSettings : NSObject

+ (instancetype)sharedSettings;

/// 侧栏宽度（pt），默认 360；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

/// 详情编辑区高度（pt），默认 380；钳制 180～520。关闭详情时不写入。
@property (nonatomic, assign) CGFloat detailHeight;

@end

NS_ASSUME_NONNULL_END
