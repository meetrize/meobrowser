#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserScraperSettings : NSObject

+ (instancetype)sharedSettings;

/// 侧栏宽度，默认 400；钳制 320～560。
@property (nonatomic, assign) CGFloat sidebarWidth;

/// 智能检测后是否显示页内数据区标注，默认 YES。
@property (nonatomic, assign) BOOL candidateOverlayVisible;

/// 页内标注是否仅显示当前选中（及已采用）项，默认 NO。
@property (nonatomic, assign) BOOL candidateOverlayOnlySelected;

/// 保留最近运行记录数，默认 20。
@property (nonatomic, assign) NSInteger maxRetainedRuns;

@end

NS_ASSUME_NONNULL_END
