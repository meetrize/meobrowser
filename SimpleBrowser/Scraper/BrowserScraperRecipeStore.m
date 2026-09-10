#import "BrowserScraperRecipeStore.h"

NSNotificationName const BrowserScraperRecipeStoreDidChangeNotification = @"BrowserScraperRecipeStoreDidChangeNotification";

@interface BrowserScraperRecipeStore ()
@property (nonatomic, strong) NSMutableArray<BrowserScraperRecipe *> *mutableRecipes;
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, copy) NSString *recipesDirectory;
@property (nonatomic, copy) NSString *indexPath;
@end

@implementation BrowserScraperRecipeStore

+ (instancetype)sharedStore {
    static BrowserScraperRecipeStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (NSString *)scraperRootDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"Scraper"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSString *)runsRootDirectory {
    NSString *dir = [[self scraperRootDirectory] stringByAppendingPathComponent:@"runs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableRecipes = [NSMutableArray array];
        _rootDirectory = [[self class] scraperRootDirectory];
        _recipesDirectory = [_rootDirectory stringByAppendingPathComponent:@"recipes"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_recipesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        _indexPath = [_rootDirectory stringByAppendingPathComponent:@"index.json"];
        [self loadFromDisk];
    }
    return self;
}

- (NSArray<BrowserScraperRecipe *> *)recipes {
    return [self.mutableRecipes copy];
}

- (void)loadFromDisk {
    [self.mutableRecipes removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.indexPath];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *ids = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        ids = json[@"recipeIDs"];
    }
    if (![ids isKindOfClass:[NSArray class]]) return;
    for (id item in ids) {
        if (![item isKindOfClass:[NSString class]]) continue;
        NSString *path = [self.recipesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", item]];
        NSData *recipeData = [NSData dataWithContentsOfFile:path];
        if (!recipeData) continue;
        id recipeJSON = [NSJSONSerialization JSONObjectWithData:recipeData options:0 error:nil];
        BrowserScraperRecipe *recipe = [BrowserScraperRecipe recipeWithDictionary:recipeJSON];
        if (recipe) {
            [self.mutableRecipes addObject:recipe];
        }
    }
}

- (void)reloadFromDisk {
    [self loadFromDisk];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserScraperRecipeStoreDidChangeNotification object:self];
}

- (BOOL)persistIndex:(NSError **)error {
    NSMutableArray *ids = [NSMutableArray array];
    for (BrowserScraperRecipe *recipe in self.mutableRecipes) {
        [ids addObject:recipe.recipeID];
    }
    NSDictionary *root = @{ @"version": @1, @"recipeIDs": ids };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    if (![data writeToFile:self.indexPath options:NSDataWritingAtomic error:error]) return NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserScraperRecipeStoreDidChangeNotification object:self];
    return YES;
}

- (nullable BrowserScraperRecipe *)recipeWithID:(NSString *)recipeID {
    for (BrowserScraperRecipe *recipe in self.mutableRecipes) {
        if ([recipe.recipeID isEqualToString:recipeID]) return recipe;
    }
    return nil;
}

- (NSArray<BrowserScraperRecipe *> *)recipesMatchingURL:(NSURL *)url {
    NSMutableArray *matched = [NSMutableArray array];
    for (BrowserScraperRecipe *recipe in self.mutableRecipes) {
        if ([recipe.match matchesURL:url]) {
            [matched addObject:recipe];
        }
    }
    return matched;
}

- (BOOL)saveRecipe:(BrowserScraperRecipe *)recipe error:(NSError **)error {
    if (recipe.recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraper" code:1 userInfo:@{NSLocalizedDescriptionKey: @"缺少配方 ID"}];
        }
        return NO;
    }
    recipe.updatedAt = [NSDate date].timeIntervalSince1970;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[recipe dictionaryRepresentation]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;
    NSString *path = [self.recipesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", recipe.recipeID]];
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;

    NSUInteger idx = [self.mutableRecipes indexOfObjectPassingTest:^BOOL(BrowserScraperRecipe *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.recipeID isEqualToString:recipe.recipeID];
    }];
    if (idx == NSNotFound) {
        [self.mutableRecipes addObject:recipe];
    } else {
        self.mutableRecipes[idx] = recipe;
    }
    return [self persistIndex:error];
}

- (BOOL)deleteRecipeWithID:(NSString *)recipeID error:(NSError **)error {
    NSUInteger idx = [self.mutableRecipes indexOfObjectPassingTest:^BOOL(BrowserScraperRecipe *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.recipeID isEqualToString:recipeID];
    }];
    if (idx != NSNotFound) {
        [self.mutableRecipes removeObjectAtIndex:idx];
    }
    NSString *path = [self.recipesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", recipeID]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [self persistIndex:error];
}

- (BOOL)exportRecipe:(BrowserScraperRecipe *)recipe toURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[recipe dictionaryRepresentation]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (nullable BrowserScraperRecipe *)importRecipeFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    BrowserScraperRecipe *recipe = [BrowserScraperRecipe recipeWithDictionary:json];
    if (!recipe) {
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraper" code:2 userInfo:@{NSLocalizedDescriptionKey: @"无效配方文件"}];
        }
        return nil;
    }
    // 导入时换新 ID，避免覆盖
    recipe.recipeID = [[NSUUID UUID] UUIDString];
    recipe.schedule.launchAgentLabel = [NSString stringWithFormat:@"com.example.MeoBrowser.scrape.%@", recipe.recipeID];
    if (![self saveRecipe:recipe error:error]) return nil;
    return recipe;
}

@end
