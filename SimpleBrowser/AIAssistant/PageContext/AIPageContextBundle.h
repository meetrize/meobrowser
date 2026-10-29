#import <Foundation/Foundation.h>

@class AIPageContextResource;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AIPageContextArticleQuality) {
    AIPageContextArticleQualityUnknown = 0,
    AIPageContextArticleQualityHigh,
    AIPageContextArticleQualityLow,
};

/// 逻辑层 id，与 Recipe / 资源盘勾选一致。
FOUNDATION_EXPORT NSString * const AIPageContextLayerMeta;
FOUNDATION_EXPORT NSString * const AIPageContextLayerArticle;
FOUNDATION_EXPORT NSString * const AIPageContextLayerOutline;
FOUNDATION_EXPORT NSString * const AIPageContextLayerHTML;
FOUNDATION_EXPORT NSString * const AIPageContextLayerMarkdown;

@interface AIPageContextBundle : NSObject

@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy, nullable) NSUUID *tabID;
@property (nonatomic, copy, nullable) NSString *urlString;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, strong) NSDate *capturedAt;
@property (nonatomic, assign) BOOL stale;

@property (nonatomic, copy, nullable) NSString *metaDescription;
@property (nonatomic, copy, nullable) NSString *metaLanguage;
@property (nonatomic, copy, nullable) NSString *canonicalURL;

@property (nonatomic, copy, nullable) NSString *articleText;
@property (nonatomic, assign) AIPageContextArticleQuality articleQuality;
@property (nonatomic, copy, nullable) NSString *visibleText;
@property (nonatomic, copy, nullable) NSString *articleWarning;

@property (nonatomic, copy, nullable) NSString *outlineText;
@property (nonatomic, copy, nullable) NSString *htmlText;
@property (nonatomic, assign) BOOL htmlTruncated;
@property (nonatomic, copy, nullable) NSString *markdownText;

@property (nonatomic, strong) NSMutableArray<AIPageContextResource *> *resources;

+ (nullable instancetype)bundleFromCaptureDictionary:(NSDictionary *)dict
                                               tabID:(nullable NSUUID *)tabID;

+ (NSArray<NSString *> *)allLayerIds;

- (NSString *)effectiveArticleText; // article，空则 visibleText
- (BOOL)hasUsableArticle;
- (BOOL)hasContentForLayer:(NSString *)layerId;
- (nullable NSString *)textForLayer:(NSString *)layerId;
- (NSUInteger)charCountForLayer:(NSString *)layerId;
- (NSString *)displayNameForLayer:(NSString *)layerId;
- (NSString *)ageDescription; // 「刚刚」/「3 分钟前」
- (nullable AIPageContextResource *)resourceWithId:(NSString *)resourceId;

@end

NS_ASSUME_NONNULL_END
