#import "BrowserTransparentModeController.h"
#import "BrowserWindowController.h"
#import "BrowserTransparentModePreferences.h"
#import "BrowserTransparentModeWindowDragMonitor.h"
#import "BrowserRiskHostPolicy.h"

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
@property (nonatomic, strong) BrowserTransparentModeWindowDragMonitor *windowDragMonitor;
@end

@implementation BrowserTransparentModeController

- (instancetype)init {
    self = [super init];
    if (self) {
        _windowDragMonitor = [[BrowserTransparentModeWindowDragMonitor alloc] init];
    }
    return self;
}

- (void)setWindowController:(BrowserWindowController *)windowController {
    _windowController = windowController;
    self.windowDragMonitor.windowController = windowController;
}

- (BOOL)shouldSuppressContextMenuForRightDrag {
    return self.windowDragMonitor.shouldSuppressContextMenu;
}

- (void)setWindowRightDragMoveEnabled:(BOOL)enabled {
    if (enabled) {
        [self.windowDragMonitor install];
    } else {
        [self.windowDragMonitor uninstall];
    }
}

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

+ (NSString *)jsonStringForObject:(id)object fallback:(NSString *)fallback {
    if (!object) {
        return fallback;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data || error) {
        return fallback;
    }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return json.length > 0 ? json : fallback;
}

+ (NSString *)jsonStringForCSSColor:(NSString *)cssColor {
    NSString *value = cssColor.length > 0 ? cssColor : @"#f2f2f2";
    return [self jsonStringForObject:@[value] fallback:@"[\"#f2f2f2\"]"];
}

- (void)evaluatePageStyleScript:(NSString *)invocation
                      onWebView:(WKWebView *)webView
                  withBootstrap:(BOOL)withBootstrap {
    if (!webView || invocation.length == 0) {
        return;
    }
    NSString *source = invocation;
    if (withBootstrap) {
        NSString *bootstrap = [[self class] pageStyleScriptSource];
        source = [NSString stringWithFormat:@"(function(){\n%@\n%@\n})();", bootstrap, invocation];
    }
    [webView evaluateJavaScript:source completionHandler:nil];
}

- (void)evaluatePageStyleScript:(NSString *)invocation onWebView:(WKWebView *)webView {
    [self evaluatePageStyleScript:invocation onWebView:webView withBootstrap:YES];
}

- (NSString *)pageStyleOptionsJSON {
    NSDictionary *options = [BrowserTransparentModePreferences pageStyleApplyOptions];
    return [[self class] jsonStringForObject:options
                                    fallback:@"{\"color\":\"#f2f2f2\",\"shadowColor\":\"#000000\",\"shadowStrength\":0.9,\"shadowRadius\":3}"];
}

- (void)applyTransparentPageStyleToWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    if ([BrowserRiskHostPolicy shouldSuppressPageAutomationForURL:webView.URL title:webView.title]) {
        return;
    }
    NSString *optionsJSON = [self pageStyleOptionsJSON];
    NSString *invocation = [NSString stringWithFormat:
                            @"window.__MeoTransparentMode.apply(%@);",
                            optionsJSON];
    [self evaluatePageStyleScript:invocation onWebView:webView withBootstrap:YES];
}

- (void)refreshTransparentPageStyleOnWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    if ([BrowserRiskHostPolicy shouldSuppressPageAutomationForURL:webView.URL title:webView.title]) {
        return;
    }
    NSString *optionsJSON = [self pageStyleOptionsJSON];
    // 轻量路径：不重复注入整包 bootstrap，只调 refresh；无 API 时回退 apply
    NSString *invocation = [NSString stringWithFormat:
                            @"(function(){var m=window.__MeoTransparentMode;"
                            @"if(m&&typeof m.refresh==='function'){m.refresh(%@);return 1;}"
                            @"return 0;})();",
                            optionsJSON];
    [webView evaluateJavaScript:invocation completionHandler:^(id result, NSError *error) {
        BOOL ok = (error == nil)
            && [result respondsToSelector:@selector(boolValue)]
            && [result boolValue];
        if (!ok) {
            [self applyTransparentPageStyleToWebView:webView];
        }
    }];
}

- (void)removeTransparentPageStyleFromWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    // 带 bootstrap，确保用到含「恢复原样式 / Canvas 重绘」的最新 remove
    [self evaluatePageStyleScript:@"window.__MeoTransparentMode && window.__MeoTransparentMode.remove();"
                        onWebView:webView
                    withBootstrap:YES];
}

- (void)setPointerOutside:(BOOL)pointerOutside onWebView:(WKWebView *)webView {
    if (!webView) {
        return;
    }
    NSString *flag = pointerOutside ? @"true" : @"false";
    NSString *invocation = [NSString stringWithFormat:
                            @"(function(){var m=window.__MeoTransparentMode;"
                            @"if(m&&typeof m.setPointerOutside==='function'){"
                            @"m.setPointerOutside(%@);return 1;}"
                            @"var r=document.documentElement;if(!r)return 0;"
                            @"r.classList.toggle('meo-pointer-outside',%@);return 1;})();",
                            flag, flag];
    [webView evaluateJavaScript:invocation completionHandler:nil];
}

@end
