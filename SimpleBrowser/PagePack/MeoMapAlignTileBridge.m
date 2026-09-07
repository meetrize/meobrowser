#import "MeoMapAlignTileBridge.h"
#import "LoginAssistScriptMessageProxy.h"

static NSString * const kMeoMapAlignTilesHandlerName = @"meoMapAlignTiles";

@interface MeoMapAlignTileBridge ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) LoginAssistScriptMessageProxy *messageProxy;
@end

@implementation MeoMapAlignTileBridge

+ (instancetype)sharedBridge {
    static MeoMapAlignTileBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[MeoMapAlignTileBridge alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        cfg.HTTPMaximumConnectionsPerHost = 6;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _messageProxy = [[LoginAssistScriptMessageProxy alloc] init];
        _messageProxy.target = self;
    }
    return self;
}

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) {
        return;
    }
    MeoMapAlignTileBridge *bridge = [self sharedBridge];
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    // 避免重复注册同名 handler（多窗口共用 configuration 模板时）
    @try {
        [ucc removeScriptMessageHandlerForName:kMeoMapAlignTilesHandlerName];
    } @catch (__unused NSException *ex) {
    }
    [ucc addScriptMessageHandler:bridge.messageProxy name:kMeoMapAlignTilesHandlerName];
}

+ (BOOL)isAllowedTileURL:(NSURL *)url {
    if (!url || url.scheme.length == 0) {
        return NO;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) {
        return NO;
    }
    NSString *host = url.host.lowercaseString ?: @"";
    if ([host hasSuffix:@"google.com"] || [host hasSuffix:@"googleapis.com"] || [host hasSuffix:@"gstatic.com"]) {
        return YES;
    }
    if ([host hasSuffix:@"openstreetmap.org"] || [host hasSuffix:@"tile.openstreetmap.org"]) {
        return YES;
    }
    if ([host hasSuffix:@"cartocdn.com"] || [host hasSuffix:@"basemaps.cartocdn.com"]) {
        return YES;
    }
    return NO;
}

+ (NSString *)jsonStringLiteral:(NSString *)string {
    NSString *safe = string ?: @"";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[safe] options:0 error:&error];
    if (!data) {
        return @"\"\"";
    }
    NSString *arrayLit = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayLit.length < 2) {
        return @"\"\"";
    }
    return [arrayLit substringWithRange:NSMakeRange(1, arrayLit.length - 2)];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:kMeoMapAlignTilesHandlerName]) {
        return;
    }
    if (![message.body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *reqId = [body[@"id"] isKindOfClass:[NSString class]] ? body[@"id"] : nil;
    NSString *urlStr = [body[@"url"] isKindOfClass:[NSString class]] ? body[@"url"] : nil;
    WKWebView *webView = message.webView;
    if (reqId.length == 0 || urlStr.length == 0 || !webView) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (![MeoMapAlignTileBridge isAllowedTileURL:url]) {
        [self replyOnWebView:webView requestId:reqId dataURL:nil error:@"url-not-allowed"];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://earth.google.com/" forHTTPHeaderField:@"Referer"];

    __weak typeof(self) weakSelf = self;
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf replyOnWebView:webView requestId:reqId dataURL:nil error:error.localizedDescription ?: @"empty"];
            });
            return;
        }
        NSString *mime = @"image/png";
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.statusCode < 200 || http.statusCode >= 300) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf replyOnWebView:webView requestId:reqId dataURL:nil error:[NSString stringWithFormat:@"http-%ld", (long)http.statusCode]];
                });
                return;
            }
            if (http.MIMEType.length > 0) {
                mime = http.MIMEType;
            }
        }
        NSString *b64 = [data base64EncodedStringWithOptions:0];
        NSString *dataURL = [NSString stringWithFormat:@"data:%@;base64,%@", mime, b64];
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf replyOnWebView:webView requestId:reqId dataURL:dataURL error:nil];
        });
    }] resume];
}

- (void)replyOnWebView:(WKWebView *)webView requestId:(NSString *)requestId dataURL:(NSString *)dataURL error:(NSString *)error {
    if (!webView || requestId.length == 0) {
        return;
    }
    NSString *idLit = [MeoMapAlignTileBridge jsonStringLiteral:requestId];
    NSString *js;
    if (dataURL.length > 0) {
        NSString *urlLit = [MeoMapAlignTileBridge jsonStringLiteral:dataURL];
        js = [NSString stringWithFormat:
              @"(function(){try{var m=window.__meoTileCbs;var id=%@;if(m&&m[id]){m[id](%@,null);delete m[id];}}catch(e){}})();",
              idLit, urlLit];
    } else {
        NSString *errLit = [MeoMapAlignTileBridge jsonStringLiteral:error ?: @"error"];
        js = [NSString stringWithFormat:
              @"(function(){try{var m=window.__meoTileCbs;var id=%@;if(m&&m[id]){m[id](null,%@);delete m[id];}}catch(e){}})();",
              idLit, errLit];
    }
    [webView evaluateJavaScript:js completionHandler:nil];
}

@end
