#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 文本翻译后端（Google 文本 API + Lingva 回退）。只传字符串，不改页面 URL。
@interface BrowserTextTranslationService : NSObject

+ (instancetype)sharedService;

/// 将 BCP-47 / 偏好语言标识规范为后端 target（如 zh-CN）。
- (NSString *)normalizedTargetLocaleIdentifier:(NSString *)localeID;

/// 是否值得送译（过短、无字母则跳过）。Replace / 通用送译用。
- (BOOL)shouldTranslateText:(NSString *)text;

/// 双语对照 / 即指即译展示用：排除域名、URL、过短元数据；Replace 勿用。
- (BOOL)isSuitableForPresentationTranslation:(NSString *)text;

/// 单条翻译（主线程外完成，回调不一定在主线程）。
- (void)translateText:(NSString *)text
         targetLocale:(NSString *)targetLocale
           completion:(void (^)(NSString * _Nullable translated, NSError * _Nullable error))completion;

/// 批量翻译；concurrency 建议 4～8。completion 在主线程。
- (void)translateTexts:(NSArray<NSString *> *)texts
          targetLocale:(NSString *)targetLocale
           concurrency:(NSUInteger)concurrency
            completion:(void (^)(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount))completion;

@end

NS_ASSUME_NONNULL_END
