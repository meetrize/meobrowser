#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 选区翻译结果浮层（右键「翻译」）。
@interface BrowserSelectionTranslationPresenter : NSObject

+ (instancetype)sharedPresenter;

/// 在 view 附近展示译文；可复制。
- (void)showTranslatedText:(NSString *)translated
              originalText:(NSString *)original
                  relativeTo:(NSView *)view;

- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
