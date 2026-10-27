#import "ServerSyncKeychain.h"

static NSString * const kLegacyKeychainService = @"com.example.MeoBrowser.serverSync";
static NSString * const kLegacyKeychainAccount = @"authToken";
static NSString * const kTokenMigratedKey = @"meo.serverSync.authTokenFileMigrated";

@implementation ServerSyncKeychain

static NSString *sCachedToken = nil;
static BOOL sTokenCacheLoaded = NO;

+ (NSString *)tokenFilePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"] stringByAppendingPathComponent:@"ServerSync"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"auth-token.txt"];
}

+ (void)updateMemoryCache:(NSString *)token {
    sCachedToken = [token copy];
    sTokenCacheLoaded = YES;
}

+ (NSString *)readTokenFromFile {
    NSString *path = [self tokenFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }
    NSString *token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    token = [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return token.length > 0 ? token : nil;
}

+ (BOOL)writeTokenToFile:(NSString *)token error:(NSError **)error {
    NSString *path = [self tokenFilePath];
    if (token.length == 0) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
        }
        return YES;
    }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path
                                            error:nil];
    return YES;
}

/// 旧钥匙串仅尝试一次性后台迁移；失败也置位，避免反复弹「登录钥匙串」密码框。
+ (void)migrateLegacyKeychainIfNeeded {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kTokenMigratedKey]) {
        return;
    }
    // 文件已有 token：直接置位，绝不碰钥匙串。
    if ([self readTokenFromFile].length > 0) {
        [defaults setBool:YES forKey:kTokenMigratedKey];
        return;
    }
    // 放弃从钥匙串读取：读钥匙串会弹 Mac 登录密码。用户需在设置中重新登录云同步一次。
    [defaults setBool:YES forKey:kTokenMigratedKey];
    (void)kLegacyKeychainService;
    (void)kLegacyKeychainAccount;
}

+ (void)warmMemoryCacheInBackground {
    if (sTokenCacheLoaded) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (sTokenCacheLoaded) {
            return;
        }
        [self migrateLegacyKeychainIfNeeded];
        [self updateMemoryCache:[self readTokenFromFile]];
    });
}

+ (BOOL)setToken:(NSString *)token error:(NSError **)error {
    if (token.length == 0) {
        return [self clearToken:error];
    }
    if (![self writeTokenToFile:token error:error]) {
        return NO;
    }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kTokenMigratedKey];
    [self updateMemoryCache:token];
    return YES;
}

+ (NSString *)token {
    if (sTokenCacheLoaded) {
        return sCachedToken;
    }
    [self migrateLegacyKeychainIfNeeded];
    NSString *token = [self readTokenFromFile];
    [self updateMemoryCache:token];
    return token;
}

+ (BOOL)clearToken:(NSError **)error {
    BOOL ok = [self writeTokenToFile:nil error:error];
    [self updateMemoryCache:nil];
    return ok;
}

@end
