#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LoginCredentialStore : NSObject

+ (instancetype)sharedStore;

- (BOOL)saveUsername:(NSString *)username
            password:(NSString *)password
        forRecipeID:(NSString *)recipeID
               error:(NSError * _Nullable * _Nullable)error;

- (BOOL)loadUsername:(NSString * _Nullable * _Nullable)username
            password:(NSString * _Nullable * _Nullable)password
         forRecipeID:(NSString *)recipeID
               error:(NSError * _Nullable * _Nullable)error;

- (BOOL)deleteCredentialsForRecipeID:(NSString *)recipeID
                               error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
