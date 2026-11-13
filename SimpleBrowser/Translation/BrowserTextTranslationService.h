#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 文本翻译后端。默认走设置中的 MTranServer（可改地址）；也可切 Google + Lingva。只传字符串，不改页面 URL。
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

/// 批量翻译；concurrency 建议 4～8（Google 路径）。completion 在主线程。
- (void)translateTexts:(NSArray<NSString *> *)texts
          targetLocale:(NSString *)targetLocale
           concurrency:(NSUInteger)concurrency
            completion:(void (^)(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount))completion;

/// 批量翻译；progress 在每批返回时于主线程回调（partial 与 texts 等长，未完成槽为空串）。
- (void)translateTexts:(NSArray<NSString *> *)texts
          targetLocale:(NSString *)targetLocale
           concurrency:(NSUInteger)concurrency
              progress:(void (^ _Nullable)(NSArray<NSString *> *partialOrEmpty))progress
            completion:(void (^)(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount))completion;

@end

NS_ASSUME_NONNULL_END
