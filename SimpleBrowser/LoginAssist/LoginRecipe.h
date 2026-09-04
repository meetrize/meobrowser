#import <Foundation/Foundation.h>
#import "MeoSiteMatch.h"

NS_ASSUME_NONNULL_BEGIN

/// 登录 Recipe 的自定义填入字段（选择器 + 值；值存 Recipe JSON，不进凭证文件）。
@interface LoginRecipeExtraField : NSObject <NSCopying>
@property (nonatomic, copy) NSString *fieldID;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *selector;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) BOOL enabled;

+ (instancetype)fieldWithLabel:(NSString *)label selector:(NSString *)selector value:(NSString *)value;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fieldWithDictionary:(NSDictionary *)dictionary;
@end

/// 站点登录配方（仅密码登录）。
@interface LoginRecipe : NSObject <NSCopying>

@property (nonatomic, copy) NSString *recipeID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *host;
/// 非默认端口；nil = 任意端口（兼容旧数据）。
@property (nonatomic, strong, nullable) NSNumber *port;
@property (nonatomic, copy, nullable) NSString *pathPrefix;
/// 缺省时按 pathPrefix 是否含通配符推断。
@property (nonatomic, copy, nullable) MeoSitePathMatchMode pathMatchMode;
@property (nonatomic, assign) BOOL autoLogin;
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, copy, nullable) NSString *usernameSelector;
@property (nonatomic, copy, nullable) NSString *passwordSelector;
@property (nonatomic, copy, nullable) NSString *submitSelector;
/// YES（默认）：对密码框回车提交；NO：点击 submitSelector。
@property (nonatomic, assign) BOOL submitByEnter;
@property (nonatomic, copy, nullable) NSString *successJSPredicate;
/// waitFor 超时（毫秒），默认 8000。
@property (nonatomic, assign) NSInteger waitTimeoutMs;
/// 自定义字段（默认空数组）。
@property (nonatomic, copy) NSArray<LoginRecipeExtraField *> *extraFields;
@property (nonatomic, assign) NSTimeInterval updatedAt;

+ (instancetype)recipeWithHost:(NSString *)host title:(NSString *)title;

- (BOOL)matchesURL:(NSURL *)url;
- (NSInteger)matchSpecificityScore;
/// 已启用且带选择器的自定义字段。
- (NSArray<LoginRecipeExtraField *> *)enabledExtraFields;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)recipeWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
