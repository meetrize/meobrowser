#import "LoginCredentialStore.h"

NSErrorDomain const LoginCredentialStoreErrorDomain = @"LoginCredentialStore";
const NSInteger LoginCredentialStoreErrorBusy = 4;
NSNotificationName const LoginCredentialStoreDidChangeNotification = @"LoginCredentialStoreDidChangeNotification";

@implementation LoginCredentials
- (instancetype)init {
    self = [super init];
    if (self) {
        _username = @"";
        _password = @"";
        _phone = @"";
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone {
    (void)zone;
    LoginCredentials *copy = [[LoginCredentials alloc] init];
    copy.username = self.username;
    copy.password = self.password;
    copy.phone = self.phone;
    return copy;
}
@end

@interface LoginCredentialStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, LoginCredentials *> *credentialsByRecipeID;
@property (nonatomic, copy) NSString *storePath;
@end

@implementation LoginCredentialStore

+ (instancetype)sharedStore {
    static LoginCredentialStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

+ (NSString *)credentialsFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"LoginAssist"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"credentials.json"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _credentialsByRecipeID = [NSMutableDictionary dictionary];
        _storePath = [[self class] credentialsFilePath];
    }
    [self loadFromDisk];
    return self;
}

#pragma mark - Disk

- (void)loadFromDisk {
    [self.credentialsByRecipeID removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.storePath];
    if (!data.length) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id map = json[@"credentials"];
    if (![map isKindOfClass:[NSDictionary class]]) {
        return;
    }
    for (id key in map) {
        if (![key isKindOfClass:[NSString class]] || [(NSString *)key length] == 0) {
            continue;
        }
        id payload = map[key];
        if (![payload isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        LoginCredentials *credentials = [self credentialsFromPayload:payload];
        self.credentialsByRecipeID[key] = credentials;
    }
}

- (LoginCredentials *)credentialsFromPayload:(NSDictionary *)payload {
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    id username = payload[@"username"];
    id password = payload[@"password"];
    id phone = payload[@"phone"];
    credentials.username = [username isKindOfClass:[NSString class]] ? username : @"";
    credentials.password = [password isKindOfClass:[NSString class]] ? password : @"";
    credentials.phone = [phone isKindOfClass:[NSString class]] ? phone : @"";
    return credentials;
}

- (BOOL)persist:(NSError **)error {
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:self.credentialsByRecipeID.count];
    for (NSString *recipeID in self.credentialsByRecipeID) {
        LoginCredentials *credentials = self.credentialsByRecipeID[recipeID];
        map[recipeID] = @{
            @"username": credentials.username ?: @"",
            @"password": credentials.password ?: @"",
            @"phone": credentials.phone ?: @"",
        };
    }
    NSDictionary *root = @{
        @"version": @1,
        @"credentials": map,
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data) {
        if (error) {
            *error = jsonError ?: [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无法编码凭证"}];
        }
        return NO;
    }
    if (![data writeToFile:self.storePath options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:self.storePath
                                            error:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:LoginCredentialStoreDidChangeNotification object:self];
    return YES;
}

#pragma mark - Public API

- (NSDictionary<NSString *, LoginCredentials *> *)allCredentials {
    @synchronized (self) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:self.credentialsByRecipeID.count];
        for (NSString *recipeID in self.credentialsByRecipeID) {
            copy[recipeID] = [self.credentialsByRecipeID[recipeID] copy];
        }
        return copy;
    }
}

- (BOOL)saveUsername:(NSString *)username
            password:(NSString *)password
         forRecipeID:(NSString *)recipeID
               error:(NSError **)error {
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = username ?: @"";
    credentials.password = password ?: @"";
    LoginCredentials *existing = [self loadCredentialsForRecipeID:recipeID error:nil];
    if (existing) {
        credentials.phone = existing.phone ?: @"";
    }
    return [self saveCredentials:credentials forRecipeID:recipeID error:error];
}

- (BOOL)saveCredentials:(LoginCredentials *)credentials
            forRecipeID:(NSString *)recipeID
                  error:(NSError **)error {
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return NO;
    }
    if (!credentials) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少凭证"}];
        }
        return NO;
    }
    @synchronized (self) {
        self.credentialsByRecipeID[recipeID] = [credentials copy];
        return [self persist:error];
    }
}

- (LoginCredentials *)loadCredentialsForRecipeID:(NSString *)recipeID error:(NSError **)error {
    if (recipeID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LoginCredentialStoreErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"缺少 Recipe ID"}];
        }
        return nil;
    }
    @synchronized (self) {
        LoginCredentials *cached = self.credentialsByRecipeID[recipeID];
        if (cached) {
            return [cached copy];
        }
        LoginCredentials *empty = [[LoginCredentials alloc] init];
        return empty;
    }
}

- (void)loadCredentialsForRecipeID:(NSString *)recipeID
                        completion:(void (^)(LoginCredentials * _Nullable, NSError * _Nullable))completion {
    if (!completion) {
        return;
    }
    NSError *localError = nil;
    LoginCredentials *credentials = [self loadCredentialsForRecipeID:recipeID error:&localError];
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(credentials, localError);
    });
}

- (BOOL)loadUsername:(NSString **)username
            password:(NSString **)password
         forRecipeID:(NSString *)recipeID
               error:(NSError **)error {
    LoginCredentials *credentials = [self loadCredentialsForRecipeID:recipeID error:error];
    if (!credentials) {
        return NO;
    }
    if (username) {
        *username = credentials.username ?: @"";
    }
    if (password) {
        *password = credentials.password ?: @"";
    }
    return YES;
}

- (BOOL)deleteCredentialsForRecipeID:(NSString *)recipeID error:(NSError **)error {
    if (recipeID.length == 0) {
        return YES;
    }
    @synchronized (self) {
        [self.credentialsByRecipeID removeObjectForKey:recipeID];
        return [self persist:error];
    }
}

- (BOOL)replaceAllCredentials:(NSDictionary<NSString *, LoginCredentials *> *)credentialsByRecipeID
                        error:(NSError **)error {
    @synchronized (self) {
        [self.credentialsByRecipeID removeAllObjects];
        [credentialsByRecipeID enumerateKeysAndObjectsUsingBlock:^(NSString *recipeID, LoginCredentials *credentials, BOOL *stop) {
            (void)stop;
            if (![recipeID isKindOfClass:[NSString class]] || recipeID.length == 0) {
                return;
            }
            if (![credentials isKindOfClass:[LoginCredentials class]]) {
                return;
            }
            self.credentialsByRecipeID[recipeID] = [credentials copy];
        }];
        return [self persist:error];
    }
}

@end
