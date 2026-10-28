#import "AIBridgeUpstreamClient.h"

@implementation AIBridgeUpstreamClient

+ (instancetype)sharedClient {
    static AIBridgeUpstreamClient *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[AIBridgeUpstreamClient alloc] init];
    });
    return c;
}

- (NSURL *)chatCompletionsURLForBase:(NSString *)baseURL {
    NSString *base = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    if ([base hasSuffix:@"/v1/chat/completions"]) {
        return [NSURL URLWithString:base];
    }
    if ([base hasSuffix:@"/v1"]) {
        return [NSURL URLWithString:[base stringByAppendingString:@"/chat/completions"]];
    }
    return [NSURL URLWithString:[base stringByAppendingString:@"/v1/chat/completions"]];
}

- (NSURL *)modelsURLForBase:(NSString *)baseURL {
    NSString *base = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    if ([base hasSuffix:@"/v1"]) {
        return [NSURL URLWithString:[base stringByAppendingString:@"/models"]];
    }
    return [NSURL URLWithString:[base stringByAppendingString:@"/v1/models"]];
}

- (void)forwardChatCompletionsBody:(NSData *)body
                           baseURL:(NSString *)baseURL
                            apiKey:(NSString *)apiKey
                        completion:(AIBridgeUpstreamCompletion)completion {
    NSURL *url = [self chatCompletionsURLForBase:baseURL];
    if (!url) {
        if (completion) {
            completion(502, nil, nil, @"invalid upstream baseURL");
        }
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (apiKey.length) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    }
    req.timeoutInterval = 120;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                completion(502, nil, nil, error.localizedDescription);
            }
            return;
        }
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http ? http.statusCode : 502;
        NSString *ct = http.allHeaderFields[@"Content-Type"] ?: @"application/json; charset=utf-8";
        if (completion) {
            completion(status, data ?: [NSData data], ct, nil);
        }
    }] resume];
}

- (void)pingBaseURL:(NSString *)baseURL
             apiKey:(NSString *)apiKey
         completion:(void (^)(BOOL, NSString *_Nullable))completion {
    NSURL *url = [self modelsURLForBase:baseURL];
    if (!url) {
        if (completion) {
            completion(NO, @"invalid baseURL");
        }
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 3;
    if (apiKey.length) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    }
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                      completionHandler:^(NSData *_Nullable __unused data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error.localizedDescription);
            }
            return;
        }
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        BOOL ok = http && http.statusCode >= 200 && http.statusCode < 500;
        if (completion) {
            completion(ok, [NSString stringWithFormat:@"HTTP %ld", (long)(http ? http.statusCode : 0)]);
        }
    }] resume];
}

@end
