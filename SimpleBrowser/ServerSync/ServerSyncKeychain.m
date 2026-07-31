#import "ServerSyncKeychain.h"
#import <Security/Security.h>

static NSString * const kService = @"com.example.MeoBrowser.serverSync";
static NSString * const kAccount = @"authToken";

static dispatch_queue_t ServerSyncKeychainQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("meobrowser.server-sync.keychain", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void ServerSyncPerformKeychain(void (^block)(void)) {
    if (!block) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_sync(ServerSyncKeychainQueue(), block);
        return;
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(ServerSyncKeychainQueue(), ^{
        block();
        dispatch_semaphore_signal(sem);
    });
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

@implementation ServerSyncKeychain

static NSString *sCachedToken = nil;
static BOOL sTokenCacheLoaded = NO;

+ (void)updateMemoryCache:(NSString *)token {
    sCachedToken = [token copy];
    sTokenCacheLoaded = YES;
}

+ (BOOL)setToken:(NSString *)token error:(NSError **)error {
    if (token.length == 0) {
        return [self clearToken:error];
    }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    __block OSStatus status = errSecSuccess;
    ServerSyncPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kService,
            (__bridge id)kSecAttrAccount: kAccount,
        };
        SecItemDelete((__bridge CFDictionaryRef)query);
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    });
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    [self updateMemoryCache:token];
    return YES;
}

+ (NSString *)token {
    if (sTokenCacheLoaded) {
        return sCachedToken;
    }
    __block CFTypeRef result = NULL;
    __block OSStatus status = errSecSuccess;
    ServerSyncPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kService,
            (__bridge id)kSecAttrAccount: kAccount,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        };
        status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    });
    if (status != errSecSuccess || !result) {
        if (result) {
            CFRelease(result);
        }
        [self updateMemoryCache:nil];
        return nil;
    }
    NSData *data = CFBridgingRelease(result);
    NSString *token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self updateMemoryCache:token];
    return token;
}

+ (BOOL)clearToken:(NSError **)error {
    __block OSStatus status = errSecSuccess;
    ServerSyncPerformKeychain(^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kService,
            (__bridge id)kSecAttrAccount: kAccount,
        };
        status = SecItemDelete((__bridge CFDictionaryRef)query);
    });
    [self updateMemoryCache:nil];
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    return YES;
}

@end
