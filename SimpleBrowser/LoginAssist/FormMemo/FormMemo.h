#import <Foundation/Foundation.h>
#import "MeoSiteMatch.h"

NS_ASSUME_NONNULL_BEGIN

@interface FormMemoField : NSObject <NSCopying>

@property (nonatomic, copy) NSString *fieldID;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *selector;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) BOOL enabled;

+ (instancetype)fieldWithLabel:(NSString *)label selector:(NSString *)selector value:(NSString *)value;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fieldWithDictionary:(NSDictionary *)dictionary;

@end

@interface FormMemo : NSObject <NSCopying>

@property (nonatomic, copy) NSString *memoID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong, nullable) NSNumber *port;
@property (nonatomic, copy, nullable) NSString *pathPrefix;
@property (nonatomic, copy, nullable) MeoSitePathMatchMode pathMatchMode;
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, copy) NSArray<FormMemoField *> *fields;
/// waitFor 超时（毫秒），默认 8000。
@property (nonatomic, assign) NSInteger waitTimeoutMs;
@property (nonatomic, assign) NSTimeInterval updatedAt;

+ (instancetype)memoWithHost:(NSString *)host title:(NSString *)title;

- (BOOL)matchesURL:(NSURL *)url;
- (NSInteger)matchSpecificityScore;
- (NSArray<FormMemoField *> *)enabledFields;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)memoWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
