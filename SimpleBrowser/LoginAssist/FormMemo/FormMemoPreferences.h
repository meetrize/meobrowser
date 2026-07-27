#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const FormMemoPreferencesDidChangeNotification;

@interface FormMemoPreferences : NSObject

/// 聚焦输入且有内容时显示「＋备忘」内联图标；默认 YES。
+ (BOOL)inlineSaveEnabled;
+ (void)setInlineSaveEnabled:(BOOL)enabled;

/// 本机是否已通过内联保存过至少一次（用于首次确认）。
+ (BOOL)hasCompletedInlineSaveOnce;
+ (void)setHasCompletedInlineSaveOnce:(BOOL)done;

@end

NS_ASSUME_NONNULL_END
