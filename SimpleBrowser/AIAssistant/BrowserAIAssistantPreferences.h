#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserAIAssistantPreferencesDidChangeNotification;

@interface BrowserAIAssistantPreferences : NSObject

@property (class, readonly, strong) BrowserAIAssistantPreferences *sharedPreferences;

/// 侧栏宽度，默认 360，范围 280～560
@property (nonatomic, assign) CGFloat sidebarWidth;

/// 上次选用的 modelId，如 bridge__deepseek
@property (nonatomic, copy) NSString *lastModelId;

@end

NS_ASSUME_NONNULL_END
