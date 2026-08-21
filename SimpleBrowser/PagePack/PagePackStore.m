#import "PagePackStore.h"
#import "PagePackModels.h"
#import "PagePackMatcher.h"

NSNotificationName const PagePackStoreDidChangeNotification = @"PagePackStoreDidChangeNotification";

@interface PagePackStore ()
@property (nonatomic, strong) NSMutableArray<PagePack *> *packs;
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, copy) NSString *indexPath;
@end

@implementation PagePackStore

+ (instancetype)sharedStore {
    static PagePackStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _packs = [NSMutableArray array];
        _rootDirectory = [[self class] packsRootDirectory];
        _indexPath = [_rootDirectory stringByAppendingPathComponent:@"index.json"];
        [self loadFromDisk];
    }
    return self;
}

+ (NSString *)packsRootDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"PagePacks"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)directoryForPackID:(NSString *)packID {
    return [self.rootDirectory stringByAppendingPathComponent:packID];
}

- (NSString *)manifestPathForPackID:(NSString *)packID {
    return [[self directoryForPackID:packID] stringByAppendingPathComponent:@"manifest.json"];
}

- (NSString *)filePathForPackID:(NSString *)packID fileName:(NSString *)fileName {
    return [[self directoryForPackID:packID] stringByAppendingPathComponent:fileName];
}

- (void)loadFromDisk {
    [self.packs removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.indexPath];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *rawList = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        rawList = json[@"packs"];
    }
    if (![rawList isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in rawList) {
        PagePack *pack = [PagePack packWithDictionary:item];
        if (pack) {
            [self.packs addObject:pack];
        }
    }
}

- (BOOL)persistIndex:(NSError **)error {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.packs.count];
    for (PagePack *pack in self.packs) {
        [list addObject:[pack dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"packs": list,
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }
    if (![data writeToFile:self.indexPath options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PagePackStoreDidChangeNotification object:self];
    return YES;
}

- (BOOL)writeManifestForPack:(PagePack *)pack error:(NSError **)error {
    NSString *dir = [self directoryForPackID:pack.packID];
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
        if (error) {
            *error = dirError;
        }
        return NO;
    }
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[pack dictionaryRepresentation]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }
    return [data writeToFile:[self manifestPathForPackID:pack.packID] options:NSDataWritingAtomic error:error];
}

- (NSArray<PagePack *> *)allPacks {
    return [[self.packs copy] sortedArrayUsingComparator:^NSComparisonResult(PagePack *a, PagePack *b) {
        return [@(b.updatedAt) compare:@(a.updatedAt)];
    }];
}

- (PagePack *)packWithID:(NSString *)packID {
    if (packID.length == 0) {
        return nil;
    }
    for (PagePack *pack in self.packs) {
        if ([pack.packID isEqualToString:packID]) {
            return [pack copy];
        }
    }
    return nil;
}

- (NSInteger)indexOfPackID:(NSString *)packID {
    for (NSInteger i = 0; i < (NSInteger)self.packs.count; i++) {
        if ([self.packs[i].packID isEqualToString:packID]) {
            return i;
        }
    }
    return NSNotFound;
}

- (NSArray<PagePack *> *)packsMatchingURL:(NSURL *)url {
    NSMutableArray<PagePack *> *matched = [NSMutableArray array];
    for (PagePack *pack in self.packs) {
        if ([PagePackMatcher URL:url matchesPack:pack]) {
            [matched addObject:[pack copy]];
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(PagePack *a, PagePack *b) {
        if (a.enabled != b.enabled) {
            return a.enabled ? NSOrderedAscending : NSOrderedDescending;
        }
        return [@(b.updatedAt) compare:@(a.updatedAt)];
    }];
    return matched;
}

- (NSArray<PagePack *> *)enabledPacksMatchingURL:(NSURL *)url {
    NSMutableArray<PagePack *> *matched = [NSMutableArray array];
    for (PagePack *pack in [self packsMatchingURL:url]) {
        if (pack.enabled) {
            [matched addObject:pack];
        }
    }
    return matched;
}

- (BOOL)upsertPack:(PagePack *)pack error:(NSError **)error {
    if (pack.packID.length == 0 || pack.name.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件信息不完整"}];
        }
        return NO;
    }
    for (PagePackFile *file in pack.files) {
        if (![PagePackFile isValidFileName:file.name error:error]) {
            return NO;
        }
    }
    pack.updatedAt = [NSDate date].timeIntervalSince1970;
    NSInteger idx = [self indexOfPackID:pack.packID];
    PagePack *stored = [pack copy];
    if (idx == NSNotFound) {
        [self.packs addObject:stored];
        if (![self writeManifestForPack:stored error:error]) {
            [self.packs removeLastObject];
            return NO;
        }
        // Ensure default files exist on disk.
        for (PagePackFile *file in stored.files) {
            NSString *path = [self filePathForPackID:stored.packID fileName:file.name];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } else {
        PagePack *previous = self.packs[idx];
        self.packs[idx] = stored;
        if (![self writeManifestForPack:stored error:error]) {
            self.packs[idx] = previous;
            return NO;
        }
    }
    return [self persistIndex:error];
}

- (BOOL)setPack:(NSString *)packID enabled:(BOOL)enabled error:(NSError **)error {
    NSInteger idx = [self indexOfPackID:packID];
    if (idx == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return NO;
    }
    PagePack *pack = [self.packs[idx] copy];
    pack.enabled = enabled;
    return [self upsertPack:pack error:error];
}

- (BOOL)deletePackWithID:(NSString *)packID error:(NSError **)error {
    NSInteger idx = [self indexOfPackID:packID];
    if (idx == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return NO;
    }
    PagePack *removed = self.packs[idx];
    [self.packs removeObjectAtIndex:idx];
    if (![self persistIndex:error]) {
        [self.packs insertObject:removed atIndex:idx];
        return NO;
    }
    NSString *dir = [self directoryForPackID:packID];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    return YES;
}

- (NSString *)contentOfFile:(NSString *)fileName inPack:(NSString *)packID error:(NSError **)error {
    if (![PagePackFile isValidFileName:fileName error:error]) {
        return nil;
    }
    if ([self indexOfPackID:packID] == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return nil;
    }
    NSString *path = [self filePathForPackID:packID fileName:fileName];
    NSError *readError = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
    if (!content) {
        if (error) {
            *error = readError ?: [NSError errorWithDomain:PagePackErrorDomain
                                                      code:PagePackErrorIO
                                                  userInfo:@{NSLocalizedDescriptionKey: @"读取文件失败"}];
        }
        return nil;
    }
    return content;
}

- (BOOL)writeContent:(NSString *)content
            fileName:(NSString *)fileName
              inPack:(NSString *)packID
               error:(NSError **)error {
    if (![PagePackFile isValidFileName:fileName error:error]) {
        return NO;
    }
    NSInteger idx = [self indexOfPackID:packID];
    if (idx == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return NO;
    }
    PagePack *pack = self.packs[idx];
    if (![pack fileNamed:fileName]) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件不存在"}];
        }
        return NO;
    }
    NSString *dir = [self directoryForPackID:packID];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [self filePathForPackID:packID fileName:fileName];
    NSString *text = content ?: @"";
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }
    pack.updatedAt = [NSDate date].timeIntervalSince1970;
    if (![self writeManifestForPack:pack error:error]) {
        return NO;
    }
    return [self persistIndex:error];
}

- (BOOL)addFile:(PagePackFile *)file
         toPack:(NSString *)packID
  initialContent:(NSString *)content
          error:(NSError **)error {
    if (!file || ![PagePackFile isValidFileName:file.name error:error]) {
        return NO;
    }
    NSInteger idx = [self indexOfPackID:packID];
    if (idx == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return NO;
    }
    PagePack *pack = [self.packs[idx] copy];
    if ([pack fileNamed:file.name]) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorDuplicate
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件已存在"}];
        }
        return NO;
    }
    NSMutableArray<PagePackFile *> *files = [pack.files mutableCopy] ?: [NSMutableArray array];
    [files addObject:[file copy]];
    pack.files = files;
    if (![self upsertPack:pack error:error]) {
        return NO;
    }
    return [self writeContent:content ?: @"" fileName:file.name inPack:packID error:error];
}

- (BOOL)removeFileNamed:(NSString *)fileName inPack:(NSString *)packID error:(NSError **)error {
    NSInteger idx = [self indexOfPackID:packID];
    if (idx == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"插件不存在"}];
        }
        return NO;
    }
    PagePack *pack = [self.packs[idx] copy];
    NSMutableArray<PagePackFile *> *files = [NSMutableArray array];
    BOOL found = NO;
    for (PagePackFile *file in pack.files) {
        if ([file.name isEqualToString:fileName]) {
            found = YES;
            continue;
        }
        [files addObject:file];
    }
    if (!found) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件不存在"}];
        }
        return NO;
    }
    pack.files = files;
    if (![self upsertPack:pack error:error]) {
        return NO;
    }
    NSString *path = [self filePathForPackID:packID fileName:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return YES;
}

- (PagePack *)createPackForURL:(NSURL *)url name:(NSString *)name error:(NSError **)error {
    NSString *match = [PagePackMatcher defaultMatchForURL:url];
    NSString *packName = name;
    if (packName.length == 0) {
        NSString *host = url.host;
        packName = host.length > 0 ? [NSString stringWithFormat:@"%@ 插件", host] : @"新页面插件";
    }
    PagePack *pack = [PagePack packWithName:packName matches:@[match]];
    if (![self upsertPack:pack error:error]) {
        return nil;
    }
    return [self packWithID:pack.packID];
}

@end
