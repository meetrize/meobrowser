#import "ServerSyncKeychain.h"

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
    NSData *data = [NSData dataWithContentsOfFile:[self tokenFilePath]];
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

+ (void)warmMemoryCacheInBackground {
    if (sTokenCacheLoaded) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (sTokenCacheLoaded) {
            return;
        }
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
    [self updateMemoryCache:token];
    return YES;
}

+ (NSString *)token {
    if (sTokenCacheLoaded) {
        return sCachedToken;
    }
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
