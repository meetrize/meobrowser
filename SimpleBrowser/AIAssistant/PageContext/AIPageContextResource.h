#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AIPageContextResourceKind) {
    AIPageContextResourceKindScript = 0,
    AIPageContextResourceKindStylesheet,
    AIPageContextResourceKindJSON,
    AIPageContextResourceKindImage,
    AIPageContextResourceKindOther,
};

@interface AIPageContextResource : NSObject

@property (nonatomic, copy) NSString *resourceId;
@property (nonatomic, assign) AIPageContextResourceKind kind;
@property (nonatomic, copy, nullable) NSString *urlString;
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, assign) BOOL inlineContent;
@property (nonatomic, copy, nullable) NSString *text; // 已加载正文（内联或 L3）
@property (nonatomic, assign) NSUInteger reportedSize;
@property (nonatomic, assign) BOOL loading;

+ (nullable instancetype)resourceFromDictionary:(NSDictionary *)dict;
- (NSString *)kindDisplayName;
- (NSString *)chipLabel;
- (BOOL)hasTextBody;
- (BOOL)canFetchSameOrigin; // 有 URL 且尚无正文

@end

NS_ASSUME_NONNULL_END
