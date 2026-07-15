#import "LoginRecipeStore.h"
#import "LoginRecipe.h"
#import "LoginCredentialStore.h"

NSNotificationName const LoginRecipeStoreDidChangeNotification = @"LoginRecipeStoreDidChangeNotification";

@interface LoginRecipeStore ()
@property (nonatomic, strong) NSMutableArray<LoginRecipe *> *recipes;
@property (nonatomic, copy) NSString *storePath;
@end

@implementation LoginRecipeStore

+ (instancetype)sharedStore {
    static LoginRecipeStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recipes = [NSMutableArray array];
        _storePath = [[self class] recipesFilePath];
        [self loadFromDisk];
    }
    return self;
}

+ (NSString *)recipesFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"LoginAssist"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"recipes.json"];
}

- (void)loadFromDisk {
    [self.recipes removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *rawList = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        rawList = json[@"recipes"];
    } else if ([json isKindOfClass:[NSArray class]]) {
        rawList = json;
    }
    if (![rawList isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in rawList) {
        LoginRecipe *recipe = [LoginRecipe recipeWithDictionary:item];
        if (recipe) {
            [self.recipes addObject:recipe];
        }
    }
}

- (BOOL)persist:(NSError **)error {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.recipes.count];
    for (LoginRecipe *recipe in self.recipes) {
        [list addObject:[recipe dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"recipes": list,
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }
    if (![data writeToFile:self.storePath options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LoginRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (NSArray<LoginRecipe *> *)allRecipes {
    return [self.recipes copy];
}

- (NSArray<LoginRecipe *> *)recipesMatchingURL:(NSURL *)url {
    NSMutableArray<LoginRecipe *> *matched = [NSMutableArray array];
    for (LoginRecipe *recipe in self.recipes) {
        if ([recipe matchesURL:url]) {
            [matched addObject:recipe];
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(LoginRecipe *a, LoginRecipe *b) {
        if (a.isDefault != b.isDefault) {
            return a.isDefault ? NSOrderedAscending : NSOrderedDescending;
        }
        return [@(b.updatedAt) compare:@(a.updatedAt)];
    }];
    return matched;
}

- (LoginRecipe *)defaultRecipeMatchingURL:(NSURL *)url {
    NSArray<LoginRecipe *> *matched = [self recipesMatchingURL:url];
    if (matched.count == 0) {
        return nil;
    }
    for (LoginRecipe *recipe in matched) {
        if (recipe.isDefault) {
            return recipe;
        }
    }
    return matched.firstObject;
}

- (LoginRecipe *)recipeWithID:(NSString *)recipeID {
    if (recipeID.length == 0) {
        return nil;
    }
    for (LoginRecipe *recipe in self.recipes) {
        if ([recipe.recipeID isEqualToString:recipeID]) {
            return recipe;
        }
    }
    return nil;
}

- (BOOL)upsertRecipe:(LoginRecipe *)recipe error:(NSError **)error {
    if (!recipe || recipe.recipeID.length == 0 || recipe.host.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginRecipeStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Recipe 无效"}];
        }
        return NO;
    }
    recipe.host = recipe.host.lowercaseString;
    recipe.updatedAt = [NSDate date].timeIntervalSince1970;

    NSInteger existingIndex = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.recipes.count; i++) {
        if ([self.recipes[i].recipeID isEqualToString:recipe.recipeID]) {
            existingIndex = i;
            break;
        }
    }

    if (recipe.isDefault) {
        for (LoginRecipe *other in self.recipes) {
            if (![other.recipeID isEqualToString:recipe.recipeID] &&
                [other.host isEqualToString:recipe.host]) {
                other.isDefault = NO;
            }
        }
    }

    LoginRecipe *stored = [recipe copy];
    if (existingIndex == NSNotFound) {
        [self.recipes addObject:stored];
    } else {
        self.recipes[existingIndex] = stored;
    }
    return [self persist:error];
}

- (BOOL)deleteRecipeWithID:(NSString *)recipeID error:(NSError **)error {
    NSInteger index = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.recipes.count; i++) {
        if ([self.recipes[i].recipeID isEqualToString:recipeID]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        return YES;
    }
    [self.recipes removeObjectAtIndex:index];
    [[LoginCredentialStore sharedStore] deleteCredentialsForRecipeID:recipeID error:nil];
    return [self persist:error];
}

- (BOOL)setDefaultRecipeID:(NSString *)recipeID error:(NSError **)error {
    LoginRecipe *target = [self recipeWithID:recipeID];
    if (!target) {
        if (error) {
            *error = [NSError errorWithDomain:@"LoginRecipeStore"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"未找到 Recipe"}];
        }
        return NO;
    }
    for (LoginRecipe *recipe in self.recipes) {
        recipe.isDefault = [recipe.recipeID isEqualToString:recipeID];
    }
    return [self persist:error];
}

@end
