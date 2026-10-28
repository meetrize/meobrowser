#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserAIAssistantPreferencesDidChangeNotification;

@interface BrowserAIAssistantPreferences : NSObject

@property (class, readonly, strong) BrowserAIAssistantPreferences *sharedPreferences;

/// 侧栏宽度，默认 380；持久化下限 300，上限由侧栏按窗口约 80% 裁剪
@property (nonatomic, assign) CGFloat sidebarWidth;

/// 上次选用的 modelId（兼容；优先 lastProviderId）
@property (nonatomic, copy) NSString *lastModelId;
/// 新建会话默认平台，如 deepseek
@property (nonatomic, copy) NSString *lastProviderId;

@end

NS_ASSUME_NONNULL_END
