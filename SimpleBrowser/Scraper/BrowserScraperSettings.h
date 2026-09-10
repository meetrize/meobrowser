#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperSettings : NSObject

+ (instancetype)sharedSettings;

/// 侧栏宽度，默认 400；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

/// 保留最近运行记录数，默认 20。
@property (nonatomic, assign) NSInteger maxRetainedRuns;

@end

NS_ASSUME_NONNULL_END
