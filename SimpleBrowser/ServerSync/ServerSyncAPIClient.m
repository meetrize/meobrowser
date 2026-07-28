#import "ServerSyncAPIClient.h"
#import "ServerSyncSettings.h"
#import "ServerSyncAuth.h"
#import "ServerSyncEngine.h"

@implementation ServerSyncAPIClient

+ (instancetype)sharedClient {
    static ServerSyncAPIClient *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (NSURL *)urlForPath:(NSString *)path {
    NSURL *base = ServerSyncSettings.sharedSettings.normalizedBaseURL;
    if (!base) {
        return nil;
    }
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    return [NSURL URLWithString:path relativeToURL:base].absoluteURL;
}

/// PocketBase 常把字段错误放在 data 里，message 只是 "Failed to create record."
- (NSString *)humanReadableErrorFromJSON:(id)json statusCode:(NSInteger)statusCode {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *message = json[@"message"];
    if ([message isKindOfClass:[NSString class]] && message.length > 0) {
        [parts addObject:message];
    }
    id dataObj = json[@"data"];
    if ([dataObj isKindOfClass:[NSDictionary class]]) {
        [(NSDictionary *)dataObj enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            (void)stop;
            NSString *fieldMsg = nil;
            if ([obj isKindOfClass:[NSDictionary class]]) {
                fieldMsg = obj[@"message"];
            } else if ([obj isKindOfClass:[NSString class]]) {
                fieldMsg = obj;
            }
            if ([fieldMsg isKindOfClass:[NSString class]] && fieldMsg.length > 0) {
                [parts addObject:[NSString stringWithFormat:@"%@：%@", key, fieldMsg]];
            }
        }];
    }
    if (parts.count == 0) {
        return [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (void)requestMethod:(NSString *)method
                 path:(NSString *)path
                 body:(NSDictionary *)body
                token:(NSString *)token
           completion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url = [self urlForPath:path];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"ServerSyncAPI"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"请先填写服务器地址"}];
        completion(nil, error);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    req.timeoutInterval = 30;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (token.length > 0) {
        [req setValue:token forHTTPHeaderField:@"Authorization"];
    }
    if (body) {
        NSError *jsonError = nil;
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (!req.HTTPBody) {
            completion(nil, jsonError);
            return;
        }
    }
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSError *outError = error;
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection) {
                outError = [NSError errorWithDomain:@"ServerSyncAPI"
                                               code:NSURLErrorAppTransportSecurityRequiresSecureConnection
                                           userInfo:@{NSLocalizedDescriptionKey:
                    @"系统拦截了明文 HTTP。请退出 /Applications 里的旧 MeoBrowser，改用重新编译的 build/MeoBrowser.app（或覆盖安装后再开）。"}];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, outError);
            });
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        id json = nil;
        if (data.length > 0) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
        if (http.statusCode < 200 || http.statusCode >= 300) {
            if (http.statusCode == 401) {
                [[ServerSyncAuth sharedAuth] logout];
                [[ServerSyncEngine sharedEngine] stop];
                NSError *authError = [NSError errorWithDomain:@"ServerSyncAPI"
                                                         code:401
                                                     userInfo:@{NSLocalizedDescriptionKey: @"登录已失效，请重新登录"}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion([json isKindOfClass:[NSDictionary class]] ? json : nil, authError);
                });
                return;
            }
            NSString *msg = [self humanReadableErrorFromJSON:json statusCode:http.statusCode];
            NSError *httpError = [NSError errorWithDomain:@"ServerSyncAPI"
                                                     code:http.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([json isKindOfClass:[NSDictionary class]] ? json : nil, httpError);
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([json isKindOfClass:[NSDictionary class]] ? json : @{}, nil);
        });
    }] resume];
}

- (void)postJSON:(NSString *)path body:(NSDictionary *)body token:(NSString *)token completion:(void (^)(NSDictionary *, NSError *))completion {
    [self requestMethod:@"POST" path:path body:body token:token completion:completion];
}

- (void)patchJSON:(NSString *)path body:(NSDictionary *)body token:(NSString *)token completion:(void (^)(NSDictionary *, NSError *))completion {
    [self requestMethod:@"PATCH" path:path body:body token:token completion:completion];
}

- (void)getJSON:(NSString *)path token:(NSString *)token completion:(void (^)(NSDictionary *, NSError *))completion {
    [self requestMethod:@"GET" path:path body:nil token:token completion:completion];
}

@end
