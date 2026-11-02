#import "AIPageContextRecipeStore.h"
#import "AIPageContextRecipe.h"
#import "AIPageContextBundle.h"

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

- (NSString *)pathForRecipeId:(NSString *)recipeId {
    return [[self recipesDirectory] stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", recipeId]];
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
        if (a.sortOrder != b.sortOrder) {
            return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.title localizedStandardCompare:b.title];
    }];
}

- (NSArray<AIPageContextRecipe *> *)allRecipes {
    return [self allRecipesSorted];
}

- (NSArray<AIPageContextRecipe *> *)allRecipesSorted {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (AIPageContextRecipe *r in [self userRecipes]) {
        [out addObject:r];
        [seen addObject:r.recipeId];
    }
    for (AIPageContextRecipe *r in [AIPageContextRecipe bundledRecipes]) {
        if ([seen containsObject:r.recipeId]) continue;
        [out addObject:r];
        [seen addObject:r.recipeId];
    }
    [out sortUsingComparator:^NSComparisonResult(AIPageContextRecipe *a, AIPageContextRecipe *b) {
        if (a.sortOrder != b.sortOrder) {
            return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.title localizedStandardCompare:b.title];
    }];
    return out;
}

- (AIPageContextRecipe *)recipeWithId:(NSString *)recipeId {
    if (recipeId.length == 0) return nil;
    AIPageContextRecipe *u = self.userById[recipeId];
    if (u) return u;
    return [AIPageContextRecipe recipeWithId:recipeId];
}

- (BOOL)hasUserOverrideForId:(NSString *)recipeId {
    return recipeId.length && self.userById[recipeId] != nil;
}

- (BOOL)isPureUserRecipeId:(NSString *)recipeId {
    return [self hasUserOverrideForId:recipeId] && ![AIPageContextRecipe isBundledRecipeId:recipeId];
}

- (void)clearOtherTopLevelExcept:(NSString *)keepId {
    NSArray *snapshot = [self allRecipesSorted];
    for (AIPageContextRecipe *other in snapshot) {
        if ([other.recipeId isEqualToString:keepId]) continue;
        if (!other.contextMenuTopLevel) continue;
        AIPageContextRecipe *cleared = [other copyRecipe];
        cleared.contextMenuTopLevel = NO;
        cleared.userDefined = YES;
        // Persist clear so bundled don't reappear as top-level on next merge
        NSError *err = nil;
        NSDictionary *dict = [cleared dictionaryRepresentation];
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&err];
        if (!data) continue;
        [data writeToFile:[self pathForRecipeId:cleared.recipeId] options:NSDataWritingAtomic error:nil];
        self.userById[cleared.recipeId] = cleared;
    }
}

- (BOOL)saveUserRecipe:(AIPageContextRecipe *)recipe error:(NSError **)error {
    if (!recipe.recipeId.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"AIPageContextRecipe" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"缺少 id"}];
        }
        return NO;
    }
    recipe.userDefined = YES;
    if (recipe.contextMenuTopLevel) {
        [self clearOtherTopLevelExcept:recipe.recipeId];
    }
    NSDictionary *dict = [recipe dictionaryRepresentation];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    if (![data writeToFile:[self pathForRecipeId:recipe.recipeId] options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    self.userById[recipe.recipeId] = recipe;
    [[NSNotificationCenter defaultCenter] postNotificationName:AIPageContextRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (BOOL)resetRecipeId:(NSString *)recipeId error:(NSError **)error {
    return [self deleteUserRecipeId:recipeId error:error];
}

- (BOOL)deleteUserRecipeId:(NSString *)recipeId error:(NSError **)error {
    if (recipeId.length == 0) return NO;
    NSString *path = [self pathForRecipeId:recipeId];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:error]) return NO;
    }
    [self.userById removeObjectForKey:recipeId];
    [[NSNotificationCenter defaultCenter] postNotificationName:AIPageContextRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (AIPageContextRecipe *)duplicateRecipe:(AIPageContextRecipe *)source withTitle:(NSString *)title {
    AIPageContextRecipe *r = [source copyRecipe];
    r.recipeId = [NSString stringWithFormat:@"user-%@", [[NSUUID UUID] UUIDString]];
    r.title = title.length ? title : [NSString stringWithFormat:@"%@ 副本", source.title ?: @"配方"];
    r.userDefined = YES;
    r.contextMenuTopLevel = NO;
    r.sortOrder = MAX(source.sortOrder, (NSInteger)200) + 10;
    return r;
}

- (AIPageContextRecipe *)createBlankRecipe {
    AIPageContextRecipe *r = [[AIPageContextRecipe alloc] init];
    r.recipeId = [NSString stringWithFormat:@"user-%@", [[NSUUID UUID] UUIDString]];
    r.title = @"新配方";
    r.userPrompt = @"请根据本页正文……\n";
    r.systemHint = @"请主要依据用户提供的页面引用作答；引用中未出现的信息请标明不确定。";
    r.autoAttachLayers = @[ AIPageContextLayerMeta, AIPageContextLayerArticle ];
    r.maxArticleChars = 24000;
    r.maxHtmlChars = 100000;
    r.userDefined = YES;
    r.showInSidebar = YES;
    r.showInContextMenu = YES;
    r.contextMenuTopLevel = NO;
    r.autoSend = YES;
    r.sortOrder = 200;
    return r;
}

- (BOOL)exportRecipe:(AIPageContextRecipe *)recipe toURL:(NSURL *)url error:(NSError **)error {
    if (!recipe || !url) return NO;
    NSDictionary *dict = [recipe dictionaryRepresentation];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (AIPageContextRecipe *)importRecipeFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    AIPageContextRecipe *r = [AIPageContextRecipe recipeFromDictionary:obj];
    if (!r) {
        if (error) {
            *error = [NSError errorWithDomain:@"AIPageContextRecipe" code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"无效的配方 JSON"}];
        }
        return nil;
    }
    r.userDefined = YES;
    if (![self saveUserRecipe:r error:error]) return nil;
    return r;
}

@end
