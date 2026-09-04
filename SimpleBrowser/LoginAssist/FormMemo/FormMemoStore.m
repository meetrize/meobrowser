#import "FormMemoStore.h"
#import "FormMemo.h"

NSNotificationName const FormMemoStoreDidChangeNotification = @"FormMemoStoreDidChangeNotification";

@interface FormMemoStore ()
@property (nonatomic, strong) NSMutableArray<FormMemo *> *memos;
@property (nonatomic, copy) NSString *storePath;
@end

@implementation FormMemoStore

+ (instancetype)sharedStore {
    static FormMemoStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memos = [NSMutableArray array];
        _storePath = [[self class] memosFilePath];
        [self loadFromDisk];
    }
    return self;
}

+ (NSString *)memosFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"FormMemo"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"memos.json"];
}

- (void)loadFromDisk {
    [self.memos removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *rawList = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        rawList = json[@"memos"];
    } else if ([json isKindOfClass:[NSArray class]]) {
        rawList = json;
    }
    if (![rawList isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in rawList) {
        FormMemo *memo = [FormMemo memoWithDictionary:item];
        if (memo) {
            [self.memos addObject:memo];
        }
    }
}

- (BOOL)persist:(NSError **)error {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:self.memos.count];
    for (FormMemo *memo in self.memos) {
        [list addObject:[memo dictionaryRepresentation]];
    }
    NSDictionary *root = @{
        @"version": @1,
        @"memos": list,
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
    [[NSNotificationCenter defaultCenter] postNotificationName:FormMemoStoreDidChangeNotification object:self];
    return YES;
}

- (NSArray<FormMemo *> *)allMemos {
    return [self.memos copy];
}

- (NSArray<FormMemo *> *)memosMatchingURL:(NSURL *)url {
    NSMutableArray<FormMemo *> *matched = [NSMutableArray array];
    for (FormMemo *memo in self.memos) {
        if ([memo matchesURL:url]) {
            [matched addObject:memo];
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(FormMemo *a, FormMemo *b) {
        NSInteger sa = [a matchSpecificityScore];
        NSInteger sb = [b matchSpecificityScore];
        if (sa != sb) {
            return sa > sb ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.isDefault != b.isDefault) {
            return a.isDefault ? NSOrderedAscending : NSOrderedDescending;
        }
        return [@(b.updatedAt) compare:@(a.updatedAt)];
    }];
    return matched;
}

- (FormMemo *)defaultMemoMatchingURL:(NSURL *)url {
    NSArray<FormMemo *> *matched = [self memosMatchingURL:url];
    if (matched.count == 0) {
        return nil;
    }
    for (FormMemo *memo in matched) {
        if (memo.isDefault) {
            return memo;
        }
    }
    return matched.firstObject;
}

- (FormMemo *)memoWithID:(NSString *)memoID {
    if (memoID.length == 0) {
        return nil;
    }
    for (FormMemo *memo in self.memos) {
        if ([memo.memoID isEqualToString:memoID]) {
            return memo;
        }
    }
    return nil;
}

- (BOOL)upsertMemo:(FormMemo *)memo error:(NSError **)error {
    if (!memo || memo.memoID.length == 0 || memo.host.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FormMemoStore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"备忘无效"}];
        }
        return NO;
    }
    memo.host = memo.host.lowercaseString;
    memo.updatedAt = [NSDate date].timeIntervalSince1970;

    NSInteger existingIndex = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.memos.count; i++) {
        if ([self.memos[i].memoID isEqualToString:memo.memoID]) {
            existingIndex = i;
            break;
        }
    }

    if (memo.isDefault) {
        for (FormMemo *other in self.memos) {
            if ([other.memoID isEqualToString:memo.memoID]) {
                continue;
            }
            if (![other.host isEqualToString:memo.host]) {
                continue;
            }
            BOOL samePort = (other.port == nil && memo.port == nil) ||
                (other.port != nil && memo.port != nil &&
                 other.port.integerValue == memo.port.integerValue);
            if (samePort) {
                other.isDefault = NO;
            }
        }
    }

    FormMemo *stored = [memo copy];
    if (existingIndex == NSNotFound) {
        [self.memos addObject:stored];
    } else {
        self.memos[existingIndex] = stored;
    }
    return [self persist:error];
}

- (BOOL)deleteMemoWithID:(NSString *)memoID error:(NSError **)error {
    NSInteger index = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.memos.count; i++) {
        if ([self.memos[i].memoID isEqualToString:memoID]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        return YES;
    }
    [self.memos removeObjectAtIndex:index];
    return [self persist:error];
}

- (BOOL)setDefaultMemoID:(NSString *)memoID error:(NSError **)error {
    FormMemo *target = [self memoWithID:memoID];
    if (!target) {
        if (error) {
            *error = [NSError errorWithDomain:@"FormMemoStore"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"未找到备忘"}];
        }
        return NO;
    }
    for (FormMemo *memo in self.memos) {
        if ([memo.host isEqualToString:target.host]) {
            memo.isDefault = [memo.memoID isEqualToString:memoID];
        }
    }
    return [self persist:error];
}

- (BOOL)replaceAllMemos:(NSArray<FormMemo *> *)memos error:(NSError **)error {
    NSMutableArray<FormMemo *> *copied = [NSMutableArray array];
    for (FormMemo *memo in memos) {
        if (![memo isKindOfClass:[FormMemo class]] || memo.memoID.length == 0 || memo.host.length == 0) {
            continue;
        }
        FormMemo *stored = [memo copy];
        stored.host = stored.host.lowercaseString;
        [copied addObject:stored];
    }
    [self.memos removeAllObjects];
    [self.memos addObjectsFromArray:copied];
    return [self persist:error];
}

@end
