#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString *LoginRecipeMode NS_TYPED_EXTENSIBLE_ENUM;
extern LoginRecipeMode const LoginRecipeModePassword;

/// 站点登录配方（V1：密码模式）。
@interface LoginRecipe : NSObject <NSCopying>

@property (nonatomic, copy) NSString *recipeID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy, nullable) NSString *pathPrefix;
@property (nonatomic, copy) LoginRecipeMode mode;
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
@property (nonatomic, assign) NSTimeInterval updatedAt;

+ (instancetype)recipeWithHost:(NSString *)host title:(NSString *)title;

- (BOOL)matchesURL:(NSURL *)url;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)recipeWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
