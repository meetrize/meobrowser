#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface PagePackSettings : NSObject

+ (instancetype)sharedSettings;

/// 总开关，默认 YES。
@property (nonatomic, assign) BOOL pagePackEnabled;

/// 侧栏宽度，默认 400；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

@end

NS_ASSUME_NONNULL_END
