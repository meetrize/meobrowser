#import "BrowserTransparentModeController.h"
#import "BrowserWindowController.h"
#import "BrowserTransparentModePreferences.h"

@interface BrowserTransparentModeSnapshot : NSObject
@property (nonatomic, assign) BOOL opaque;
@property (nonatomic, strong, nullable) NSColor *backgroundColor;
@property (nonatomic, assign) BOOL hasShadow;
@property (nonatomic, assign) BOOL contentContainerWantsLayer;
@property (nonatomic, strong, nullable) NSColor *contentContainerBackgroundColor;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *webViewDrawsBackgroundByPointer;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSColor *> *webViewUnderPageColorByPointer;
@end

@implementation BrowserTransparentModeSnapshot
- (instancetype)init {
    self = [super init];
    if (self) {
        _webViewDrawsBackgroundByPointer = [NSMutableDictionary dictionary];
        _webViewUnderPageColorByPointer = [NSMutableDictionary dictionary];
    }
    return self;
}
@end

@interface BrowserTransparentModeController ()
@property (nonatomic, strong, nullable) BrowserTransparentModeSnapshot *snapshot;
@end

@implementation BrowserTransparentModeController

- (BOOL)hasSnapshot {
    return self.snapshot != nil;
}

- (void)clearSnapshot {
    self.snapshot = nil;
}

- (void)captureSnapshotFromWindow:(NSWindow *)window
                contentContainer:(NSView *)contentContainer {
    if (!window) {
        return;
    }
    BrowserTransparentModeSnapshot *snap = [[BrowserTransparentModeSnapshot alloc] init];
    snap.opaque = window.opaque;
    snap.backgroundColor = window.backgroundColor;
    snap.hasShadow = window.hasShadow;
    if (contentContainer) {
        snap.contentContainerWantsLayer = contentContainer.wantsLayer;
        if (contentContainer.layer) {
            CGColorRef cg = contentContainer.layer.backgroundColor;
            if (cg) {
                snap.contentContainerBackgroundColor = [NSColor colorWithCGColor:cg];
            }
        }
    }
    self.snapshot = snap;
}

- (void)recordWebViewAppearance:(WKWebView *)webView intoSnapshot:(BrowserTransparentModeSnapshot *)snap {
    if (!webView || !snap) {
        return;
    }
    NSValue *key = [NSValue valueWithNonretainedObject:webView];
    BOOL draws = YES;
    @try {
        NSNumber *value = [webView valueForKey:@"drawsBackground"];
        if ([value isKindOfClass:[NSNumber class]]) {
            draws = value.boolValue;
        }
    } @catch (__unused NSException *ex) {
        draws = YES;
    }
    snap.webViewDrawsBackgroundByPointer[key] = @(draws);

    if (@available(macOS 12.0, *)) {
        NSColor *under = webView.underPageBackgroundColor;
        if (under) {
            snap.webViewUnderPageColorByPointer[key] = under;
        }
    }
}

- (void)applyWindowTransparency:(NSWindow *)window
              contentContainer:(NSView *)contentContainer
                      webViews:(NSArray<WKWebView *> *)webViews {
    if (!window) {
        return;
    }
    if (!self.snapshot) {
        [self captureSnapshotFromWindow:window contentContainer:contentContainer];
    }
    BrowserTransparentModeSnapshot *snap = self.snapshot;

    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.hasShadow = NO;

    if (contentContainer) {
        contentContainer.wantsLayer = YES;
        contentContainer.layer.backgroundColor = [NSColor clearColor].CGColor;
    }

    for (WKWebView *webView in webViews) {
        if (![webView isKindOfClass:[WKWebView class]]) {
            continue;
        }
        [self recordWebViewAppearance:webView intoSnapshot:snap];
        @try {
            [webView setValue:@NO forKey:@"drawsBackground"];
        } @catch (__unused NSException *ex) {
        }
        if (@available(macOS 12.0, *)) {
            webView.underPageBackgroundColor = [NSColor clearColor];
        }
    }
}

- (void)restoreWindowAppearance:(NSWindow *)window
              contentContainer:(NSView *)contentContainer
                      webViews:(NSArray<WKWebView *> *)webViews {
    BrowserTransparentModeSnapshot *snap = self.snapshot;
    if (!window || !snap) {
        return;
    }

    window.opaque = snap.opaque;
    window.backgroundColor = snap.backgroundColor ?: [NSColor windowBackgroundColor];
    window.hasShadow = snap.hasShadow;

    if (contentContainer) {
        contentContainer.wantsLayer = snap.contentContainerWantsLayer;
        if (contentContainer.layer) {
            contentContainer.layer.backgroundColor = snap.contentContainerBackgroundColor.CGColor;
        }
    }

    for (WKWebView *webView in webViews) {
        if (![webView isKindOfClass:[WKWebView class]]) {
            continue;
        }
        NSValue *key = [NSValue valueWithNonretainedObject:webView];
        NSNumber *draws = snap.webViewDrawsBackgroundByPointer[key];
        BOOL shouldDraw = draws ? draws.boolValue : YES;
        @try {
            [webView setValue:@(shouldDraw) forKey:@"drawsBackground"];
        } @catch (__unused NSException *ex) {
        }
        if (@available(macOS 12.0, *)) {
            NSColor *under = snap.webViewUnderPageColorByPointer[key];
            webView.underPageBackgroundColor = under;
        }
    }

    [self clearSnapshot];
}

+ (NSString *)pageStyleScriptSource {
    static NSString *source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"transparent-mode-style" ofType:@"js"];
        NSString *fileSource = nil;
        if (path.length > 0) {
            NSError *error = nil;
            fileSource = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
            if (error != nil || fileSource.length == 0) {
                fileSource = nil;
            }
        }
        if (fileSource.length == 0) {
            fileSource =
                @"(function(){window.__MeoTransparentMode=window.__MeoTransparentMode||{"
                "apply:function(){},remove:function(){}};})();";
        }
        source = fileSource;
    });
    return source;
}

+ (void)installPageStyleUserScriptOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) {
        return;
    }
    NSString *source = [self pageStyleScriptSource];
    if (source.length == 0) {
        return;
    }
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:script];
}

+ (NSString *)jsonStringForCSSColor:(NSString *)cssColor {
    NSString *value = cssColor.length > 0 ? cssColor : @"#f2f2f2";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:&error];
    if (!data || error) {
        return @"\"#f2f2f2\"";
    }
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayJSON.length < 2) {
        return @"\"#f2f2f2\"";
    }
    return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
}

- (void)evaluatePageStyleScript:(NSString *)invocation onWebView:(WKWebView *)webView {
    if (!webView || invocation.length == 0) {
        return;
    }
    // 若 document-start 已装好则只调 API；否则先 bootstrap 再调用。
    NSString *bootstrap = [[self class] pageStyleScriptSource];
    NSString *source = [NSString stringWithFormat:
                          @"(function(){\n%@\n%@\n})();",
                          bootstrap, invocation];
    [webView evaluateJavaScript:source completionHandler:nil];
}

- (void)applyTransparentPageStyleToWebView:(WKWebView *)webView {
    NSString *colorJSON = [[self class] jsonStringForCSSColor:[BrowserTransparentModePreferences textColorCSSHex]];
    NSString *invocation = [NSString stringWithFormat:
                            @"window.__MeoTransparentMode && window.__MeoTransparentMode.apply(%@);",
                            colorJSON];
    [self evaluatePageStyleScript:invocation onWebView:webView];
}

- (void)removeTransparentPageStyleFromWebView:(WKWebView *)webView {
    [self evaluatePageStyleScript:@"window.__MeoTransparentMode && window.__MeoTransparentMode.remove();"
                        onWebView:webView];
}

@end
