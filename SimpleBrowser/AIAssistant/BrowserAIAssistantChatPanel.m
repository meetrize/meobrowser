#import "BrowserAIAssistantChatPanel.h"
#import "AIAssistantSession.h"
#import "LoginAssistScriptMessageProxy.h"
#import <WebKit/WebKit.h>

static NSString * const kMeoAIChatHandlerName = @"meoAIChat";

@interface BrowserAIAssistantChatPanel () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) LoginAssistScriptMessageProxy *scriptProxy;
@property (nonatomic, assign) BOOL pageReady;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *pending;
/// 串行化所有 JS，避免 clear/append 交错导致消息顺序颠倒
@property (nonatomic, strong) NSMutableArray<void (^)(void (^done)(void))> *jsQueue;
@property (nonatomic, assign) BOOL jsBusy;
@end

@implementation BrowserAIAssistantChatPanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _pending = [NSMutableArray array];
        _jsQueue = [NSMutableArray array];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        self.layer.masksToBounds = YES;

        WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
        cfg.suppressesIncrementalRendering = YES;
        LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
        proxy.target = self;
        self.scriptProxy = proxy;
        [cfg.userContentController addScriptMessageHandler:proxy name:kMeoAIChatHandlerName];

        WKWebView *wv = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:cfg];
        wv.translatesAutoresizingMaskIntoConstraints = NO;
        wv.navigationDelegate = self;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
        if (@available(macOS 13.3, *)) {
            wv.inspectable = YES;
        }
#endif
        if (@available(macOS 10.14, *)) {
            wv.underPageBackgroundColor = NSColor.textBackgroundColor;
        }
        [self addSubview:wv];
        [NSLayoutConstraint activateConstraints:@[
            [wv.topAnchor constraintEqualToAnchor:self.topAnchor],
            [wv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [wv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [wv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        self.webView = wv;
        [self loadChatHTML];
    }
    return self;
}

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:kMeoAIChatHandlerName];
}

- (void)loadChatHTML {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *path = [bundle pathForResource:@"chat" ofType:@"html" inDirectory:@"AIAssistant"];
    if (!path) {
        path = [bundle pathForResource:@"chat" ofType:@"html"];
    }
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
        return;
    }
    NSString *html = @"<!DOCTYPE html><meta charset=utf-8><body style='font:13px -apple-system'><div id=log></div>"
                      "<script>window.MeoAIChat={clear:function(){log.innerHTML=''},"
                      "appendUser:function(t){var d=document.createElement('div');d.textContent='我: '+t;log.appendChild(d);},"
                      "appendUserPayload:function(o){MeoAIChat.appendUser((o&&o.text)||'');},"
                      "appendAssistant:function(t){var d=document.createElement('div');d.textContent=t;log.appendChild(d);},"
                      "appendSystem:function(t){var d=document.createElement('div');d.style.opacity=.6;d.textContent=t;log.appendChild(d);},"
                      "setMessages:function(){}};</script>";
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)enqueueJS:(void (^)(void (^done)(void)))work {
    if (!work) return;
    [self.jsQueue addObject:[work copy]];
    [self drainJSQueue];
}

- (void)drainJSQueue {
    if (self.jsBusy || self.jsQueue.count == 0 || !self.pageReady) {
        return;
    }
    self.jsBusy = YES;
    void (^work)(void (^)(void)) = self.jsQueue.firstObject;
    [self.jsQueue removeObjectAtIndex:0];
    __weak typeof(self) weakSelf = self;
    work(^{
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.jsBusy = NO;
            [weakSelf drainJSQueue];
        });
    });
}

/// 用 Base64 传文本，避免超长 / 特殊字符在 evaluateJavaScript 拼串时出问题。
- (void)callChatMethod:(NSString *)methodName utf8Text:(NSString *)text done:(void (^)(void))done {
    NSString *s = text ?: @"";
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSString *b64 = [data base64EncodedStringWithOptions:0] ?: @"";
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{"
         "if(!window.MeoAIChat||typeof window.MeoAIChat[%@]!=='function')return 'noapi';"
         "var b64=%@;"
         "var bin=atob(b64);"
         "var bytes=new Uint8Array(bin.length);"
         "for(var i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);"
         "var text=new TextDecoder('utf-8').decode(bytes);"
         "window.MeoAIChat[%@](text);"
         "return 'ok';"
         "}catch(e){return 'err:'+String(e);}})()",
        [self jsQuote:methodName],
        [self jsQuote:b64],
        [self jsQuote:methodName]];
    [self.webView evaluateJavaScript:js completionHandler:^(__unused id r, __unused NSError *e) {
        if (done) done();
    }];
}

- (NSString *)jsQuote:(NSString *)s {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[ s ?: @"" ] options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayJSON.length >= 2 && [arrayJSON hasPrefix:@"["] && [arrayJSON hasSuffix:@"]"]) {
        return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
    }
    return @"\"\"";
}

- (void)runWhenReady:(dispatch_block_t)block {
    if (!block) return;
    if (self.pageReady) {
        block();
    } else {
        [self.pending addObject:[block copy]];
    }
}

- (void)clear {
    __weak typeof(self) weakSelf = self;
    [self runWhenReady:^{
        [weakSelf enqueueJS:^(void (^done)(void)) {
            [weakSelf.webView evaluateJavaScript:@"window.MeoAIChat && MeoAIChat.clear()"
                               completionHandler:^(__unused id r, __unused NSError *e) {
                if (done) done();
            }];
        }];
    }];
}

- (void)appendUserText:(NSString *)text {
    [self appendUserText:text uiAttachments:nil];
}

- (void)appendUserText:(NSString *)text imageDataURLs:(NSArray<NSString *> *)imageDataURLs {
    NSMutableArray<NSDictionary *> *atts = [NSMutableArray array];
    for (NSString *u in imageDataURLs ?: @[]) {
        if ([u isKindOfClass:[NSString class]] && [u hasPrefix:@"data:image"]) {
            [atts addObject:@{ @"kind": @"image", @"preview": u }];
        }
    }
    [self appendUserText:text uiAttachments:atts];
}

- (NSDictionary *)sanitizedUserPayloadText:(NSString *)text
                            uiAttachments:(NSArray<NSDictionary *> *)uiAttachments {
    NSMutableArray *images = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    for (NSDictionary *a in uiAttachments ?: @[]) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSString *kind = [a[@"kind"] isKindOfClass:[NSString class]] ? a[@"kind"] : @"";
        if ([kind isEqualToString:@"image"]) {
            NSString *preview = [a[@"preview"] isKindOfClass:[NSString class]] ? a[@"preview"] : nil;
            if (preview.length == 0 || ![preview hasPrefix:@"data:image"]) continue;
            NSMutableDictionary *img = [@{ @"src": preview } mutableCopy];
            if ([a[@"path"] isKindOfClass:[NSString class]] && [a[@"path"] length]) {
                img[@"path"] = a[@"path"];
            }
            [images addObject:img];
        } else if ([kind isEqualToString:@"file"]) {
            NSString *name = [a[@"name"] isKindOfClass:[NSString class]] ? a[@"name"] : @"文件";
            NSMutableDictionary *file = [@{ @"name": name } mutableCopy];
            if ([a[@"path"] isKindOfClass:[NSString class]] && [a[@"path"] length]) {
                file[@"path"] = a[@"path"];
            }
            if ([a[@"icon"] isKindOfClass:[NSString class]] && [a[@"icon"] hasPrefix:@"data:image"]) {
                file[@"icon"] = a[@"icon"];
            }
            [files addObject:file];
        }
    }
    return @{
        @"text": text ?: @"",
        @"images": images,
        @"files": files,
    };
}

- (void)appendUserText:(NSString *)text uiAttachments:(NSArray<NSDictionary *> *)uiAttachments {
    __weak typeof(self) weakSelf = self;
    NSDictionary *payload = [self sanitizedUserPayloadText:text uiAttachments:uiAttachments];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = jsonData
        ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]
        : @"{\"text\":\"\",\"images\":[],\"files\":[]}";
    [self runWhenReady:^{
        [weakSelf enqueueJS:^(void (^done)(void)) {
            NSString *js = [NSString stringWithFormat:
                @"(function(){try{"
                 "if(!window.MeoAIChat||typeof window.MeoAIChat.appendUserPayload!=='function')return 'noapi';"
                 "window.MeoAIChat.appendUserPayload(%@);"
                 "return 'ok';"
                 "}catch(e){return 'err:'+String(e);}})()",
                json ?: @"{}"];
            [weakSelf.webView evaluateJavaScript:js completionHandler:^(__unused id r, __unused NSError *e) {
                if (done) done();
            }];
        }];
    }];
}

- (void)appendAssistantMarkdown:(NSString *)markdown {
    __weak typeof(self) weakSelf = self;
    NSString *copy = [markdown copy] ?: @"";
    [self runWhenReady:^{
        [weakSelf enqueueJS:^(void (^done)(void)) {
            [weakSelf callChatMethod:@"appendAssistant" utf8Text:copy done:done];
        }];
    }];
}

- (void)appendSystemText:(NSString *)text {
    __weak typeof(self) weakSelf = self;
    NSString *copy = [text copy] ?: @"";
    [self runWhenReady:^{
        [weakSelf enqueueJS:^(void (^done)(void)) {
            [weakSelf callChatMethod:@"appendSystem" utf8Text:copy done:done];
        }];
    }];
}

- (NSArray<NSDictionary *> *)uiAttachmentsForMessage:(AIAssistantMessage *)m {
    if (m.uiAttachments.count) return m.uiAttachments;
    // 兼容旧会话：仅有 imageDataURLs
    if (!m.imageDataURLs.count) return @[];
    NSMutableArray *atts = [NSMutableArray array];
    for (NSString *u in m.imageDataURLs) {
        if ([u isKindOfClass:[NSString class]] && [u hasPrefix:@"data:image"]) {
            [atts addObject:@{ @"kind": @"image", @"preview": u }];
        }
    }
    return atts;
}

- (void)reloadMessages:(NSArray<AIAssistantMessage *> *)messages {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *payload = [NSMutableArray arrayWithCapacity:messages.count];
    for (AIAssistantMessage *m in messages ?: @[]) {
        NSString *role = m.role.length ? m.role : @"user";
        NSString *ui = m.displayContent.length ? m.displayContent : (m.content ?: @"");
        NSDictionary *userPayload = [self sanitizedUserPayloadText:ui
                                                    uiAttachments:[self uiAttachmentsForMessage:m]];
        NSMutableDictionary *item = [@{
            @"role": role,
            @"content": ui,
            @"images": userPayload[@"images"] ?: @[],
            @"files": userPayload[@"files"] ?: @[],
        } mutableCopy];
        [payload addObject:item];
    }
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"[]";
    [self runWhenReady:^{
        [weakSelf.jsQueue removeAllObjects];
        [weakSelf enqueueJS:^(void (^done)(void)) {
            NSString *js = [NSString stringWithFormat:
                @"(function(){try{"
                 "if(!window.MeoAIChat||typeof window.MeoAIChat.setMessages!=='function')return 'noapi';"
                 "window.MeoAIChat.setMessages(%@);"
                 "return 'ok';"
                 "}catch(e){return 'err:'+String(e);}})()",
                json ?: @"[]"];
            [weakSelf.webView evaluateJavaScript:js completionHandler:^(__unused id r, __unused NSError *e) {
                if (done) done();
            }];
        }];
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    self.pageReady = YES;
    NSArray<dispatch_block_t> *queued = [self.pending copy];
    [self.pending removeAllObjects];
    for (dispatch_block_t b in queued) {
        b();
    }
    [self drainJSQueue];
}

#pragma mark - Open attachment with system default app

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:kMeoAIChatHandlerName]) return;
    id body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *dict = (NSDictionary *)body;
    NSString *action = [dict[@"action"] isKindOfClass:[NSString class]] ? dict[@"action"] : @"";
    if ([action isEqualToString:@"openPath"]) {
        NSString *path = [dict[@"path"] isKindOfClass:[NSString class]] ? dict[@"path"] : nil;
        [self openLocalPath:path];
    } else if ([action isEqualToString:@"openImageData"]) {
        NSString *dataURL = [dict[@"dataURL"] isKindOfClass:[NSString class]] ? dict[@"dataURL"] : nil;
        [self openImageDataURL:dataURL];
    }
}

- (void)openLocalPath:(NSString *)path {
    if (path.length == 0 || ![path hasPrefix:@"/"]) return;
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] || isDir) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openImageDataURL:(NSString *)dataURL {
    if (dataURL.length == 0 || ![dataURL hasPrefix:@"data:image"]) return;
    NSRange comma = [dataURL rangeOfString:@","];
    if (comma.location == NSNotFound || comma.location + 1 >= dataURL.length) return;
    NSString *header = [dataURL substringToIndex:comma.location].lowercaseString;
    NSString *b64 = [dataURL substringFromIndex:comma.location + 1];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64
                                                       options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (data.length == 0) return;
    NSString *ext = @"jpg";
    if ([header containsString:@"image/png"]) ext = @"png";
    else if ([header containsString:@"image/gif"]) ext = @"gif";
    else if ([header containsString:@"image/webp"]) ext = @"webp";
    else if ([header containsString:@"image/jpeg"] || [header containsString:@"image/jpg"]) ext = @"jpg";
    NSString *name = [NSString stringWithFormat:@"meo-ai-preview-%@.%@", NSUUID.UUID.UUIDString, ext];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    if (![data writeToFile:path atomically:YES]) return;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

@end
