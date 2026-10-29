#import "AIPageContextRecipeStore.h"
#import "AIPageContextRecipe.h"

NSNotificationName const AIPageContextRecipeStoreDidChangeNotification =
    @"AIPageContextRecipeStoreDidChangeNotification";

@interface AIPageContextRecipeStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, AIPageContextRecipe *> *userById;
@end

@implementation AIPageContextRecipeStore

+ (AIPageContextRecipeStore *)sharedStore {
    static AIPageContextRecipeStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[AIPageContextRecipeStore alloc] init];
        [store reloadFromDisk];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _userById = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)recipesDirectory {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"MeoBrowser/AIAssistant/Recipes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)reloadFromDisk {
    [self.userById removeAllObjects];
    NSString *dir = [self recipesDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    for (NSString *name in files) {
        if (![name.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        AIPageContextRecipe *r = [AIPageContextRecipe recipeFromDictionary:obj];
        if (!r) continue;
        r.userDefined = YES;
        self.userById[r.recipeId] = r;
    }
}

- (NSArray<AIPageContextRecipe *> *)userRecipes {
    return [self.userById.allValues sortedArrayUsingComparator:^NSComparisonResult(AIPageContextRecipe *a, AIPageContextRecipe *b) {
        return [a.title localizedStandardCompare:b.title];
    }];
}

- (NSArray<AIPageContextRecipe *> *)allRecipes {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    // 用户覆盖同 id：用户优先
    for (AIPageContextRecipe *r in [self userRecipes]) {
        [out addObject:r];
        [seen addObject:r.recipeId];
    }
    for (AIPageContextRecipe *r in [AIPageContextRecipe bundledRecipes]) {
        if ([seen containsObject:r.recipeId]) continue;
        [out addObject:r];
        [seen addObject:r.recipeId];
    }
    return out;
}

- (AIPageContextRecipe *)recipeWithId:(NSString *)recipeId {
    if (recipeId.length == 0) return nil;
    AIPageContextRecipe *u = self.userById[recipeId];
    if (u) return u;
    return [AIPageContextRecipe recipeWithId:recipeId];
}

- (BOOL)saveUserRecipe:(AIPageContextRecipe *)recipe error:(NSError **)error {
    if (!recipe.recipeId.length) {
        if (error) *error = [NSError errorWithDomain:@"AIPageContextRecipe" code:1 userInfo:@{NSLocalizedDescriptionKey: @"缺少 id"}];
        return NO;
    }
    recipe.userDefined = YES;
    NSDictionary *dict = [recipe dictionaryRepresentation];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    NSString *path = [[self recipesDirectory] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.json", recipe.recipeId]];
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    self.userById[recipe.recipeId] = recipe;
    [[NSNotificationCenter defaultCenter] postNotificationName:AIPageContextRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (BOOL)deleteUserRecipeId:(NSString *)recipeId error:(NSError **)error {
    if (recipeId.length == 0) return NO;
    NSString *path = [[self recipesDirectory] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.json", recipeId]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:error]) return NO;
    }
    [self.userById removeObjectForKey:recipeId];
    [[NSNotificationCenter defaultCenter] postNotificationName:AIPageContextRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (AIPageContextRecipe *)duplicateRecipe:(AIPageContextRecipe *)source withTitle:(NSString *)title {
    AIPageContextRecipe *r = [[AIPageContextRecipe alloc] init];
    r.recipeId = [NSString stringWithFormat:@"user-%@", [[NSUUID UUID] UUIDString]];
    r.title = title.length ? title : [NSString stringWithFormat:@"%@ 副本", source.title ?: @"配方"];
    r.userPrompt = source.userPrompt ?: @"";
    r.systemHint = source.systemHint ?: @"";
    r.autoAttachLayers = [source.autoAttachLayers copy] ?: @[];
    r.maxArticleChars = source.maxArticleChars ?: 24000;
    r.maxHtmlChars = source.maxHtmlChars ?: 100000;
    r.userDefined = YES;
    return r;
}

@end
