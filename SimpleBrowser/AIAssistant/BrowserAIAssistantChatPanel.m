#import "BrowserAIAssistantChatPanel.h"
#import "AIAssistantSession.h"
#import <WebKit/WebKit.h>

@interface BrowserAIAssistantChatPanel () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL pageReady;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *pending;
@end

@implementation BrowserAIAssistantChatPanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _pending = [NSMutableArray array];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        self.layer.masksToBounds = YES;

        WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
        cfg.suppressesIncrementalRendering = YES;
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
    // 兜底：内联极简页
    NSString *html = @"<!DOCTYPE html><meta charset=utf-8><body style='font:13px -apple-system'><div id=log></div>"
                      "<script>window.MeoAIChat={clear:function(){log.innerHTML=''},"
                      "appendUser:function(t){var d=document.createElement('div');d.textContent='我: '+t;log.appendChild(d);},"
                      "appendAssistant:function(t){var d=document.createElement('div');d.textContent=t;log.appendChild(d);},"
                      "appendSystem:function(t){var d=document.createElement('div');d.style.opacity=.6;d.textContent=t;log.appendChild(d);}};</script>";
    [self.webView loadHTMLString:html baseURL:nil];
}

/// 用 Base64 传文本，避免超长 / 特殊字符在 evaluateJavaScript 拼串时出问题。
- (void)callChatMethod:(NSString *)methodName utf8Text:(NSString *)text {
    NSString *s = text ?: @"";
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSString *b64 = [data base64EncodedStringWithOptions:0] ?: @"";
    // atob → 二进制串 → TextDecoder UTF-8
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
    [self.webView evaluateJavaScript:js completionHandler:nil];
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
        [weakSelf.webView evaluateJavaScript:@"window.MeoAIChat && MeoAIChat.clear()" completionHandler:nil];
    }];
}

- (void)appendUserText:(NSString *)text {
    __weak typeof(self) weakSelf = self;
    [self runWhenReady:^{
        [weakSelf callChatMethod:@"appendUser" utf8Text:text];
    }];
}

- (void)appendAssistantMarkdown:(NSString *)markdown {
    __weak typeof(self) weakSelf = self;
    [self runWhenReady:^{
        [weakSelf callChatMethod:@"appendAssistant" utf8Text:markdown];
    }];
}

- (void)appendSystemText:(NSString *)text {
    __weak typeof(self) weakSelf = self;
    [self runWhenReady:^{
        [weakSelf callChatMethod:@"appendSystem" utf8Text:text];
    }];
}

- (void)reloadMessages:(NSArray<AIAssistantMessage *> *)messages {
    __weak typeof(self) weakSelf = self;
    NSArray *copy = [messages copy] ?: @[];
    [self runWhenReady:^{
        [weakSelf.webView evaluateJavaScript:@"window.MeoAIChat && MeoAIChat.clear()" completionHandler:^(id r, NSError *e) {
            (void)r; (void)e;
            for (AIAssistantMessage *m in copy) {
                if ([m.role isEqualToString:@"assistant"]) {
                    [weakSelf callChatMethod:@"appendAssistant" utf8Text:m.content];
                } else if ([m.role isEqualToString:@"system"]) {
                    [weakSelf callChatMethod:@"appendSystem" utf8Text:m.content];
                } else {
                    [weakSelf callChatMethod:@"appendUser" utf8Text:m.content];
                }
            }
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
}

@end
