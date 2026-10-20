#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorHUD.h"

static NSWindow *gWindow;
static WKWebView *gWebView;
static BrowserDOMInspectorHUD *gHUD;

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSRect winRect = NSMakeRect(150, 150, 800, 600);
    gWindow = [[NSWindow alloc] initWithContentRect:winRect
                                         styleMask:NSWindowStyleMaskTitled |
                                                   NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable |
                                                   NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    gWindow.title = @"HUD Visual Test";
    [gWindow makeKeyAndOrderFront:nil];

    NSView *cv = gWindow.contentView;
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    gWebView = [[WKWebView alloc] initWithFrame:cv.bounds configuration:config];
    gWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:gWebView];

    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif;padding:20px'>"
        @"<h1 id='title' style='background:#eee;padding:8px'>Visual HUD Test</h1>"
        @"<p id='p1'>Hover me to see HUD tooltip</p>"
        @"<div id='box' style='width:300px;height:80px;background:#3b82f6;"
        @"color:white;padding:12px;margin-top:16px;border-radius:8px'>"
        @"Blue box here</div>"
        @"</body></html>";
    [gWebView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!gWebView.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    gHUD = [[BrowserDOMInspectorHUD alloc] init];

    __block NSInteger snapshotCount = 0;
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        snapshotCount++;
        printf("  [%ld] type=%s tag=%s\n", (long)snapshotCount, type.UTF8String,
               [payload[@"tagName"] ?: @"-" UTF8String]);
        if ([type isEqualToString:@"pinned"]) { [gHUD hide]; return; }

        NSDictionary *geo = payload[@"geometry"];
        if (!geo) return;
        CGFloat x = [geo[@"x"] doubleValue];
        CGFloat y = [geo[@"y"] doubleValue];
        CGFloat w = [geo[@"width"] doubleValue];
        CGFloat h = [geo[@"height"] doubleValue];
        NSRect webFrameInWindow = [gWebView convertRect:gWebView.bounds toView:gWindow.contentView];
        CGFloat windowY = NSMaxY(webFrameInWindow) - (y + h);
        NSRect geoInContent = NSMakeRect(NSMinX(webFrameInWindow) + x, windowY, w, h);
        [gHUD showSnapshot:payload
           geometryInContent:geoInContent
             webViewInContent:webFrameInWindow
                    inWindow:gWindow];
    };

    [bridge startInWebView:gWebView];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    void (^hoverEl)(NSString *) = ^(NSString *elId) {
        NSString *js = [NSString stringWithFormat:
            @"var el=document.getElementById('%@');"
             "var r=el.getBoundingClientRect();"
             "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+10,clientY:r.top+5}));",
            elId];
        [gWebView evaluateJavaScript:js completionHandler:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    };

    hoverEl(@"p1");
    hoverEl(@"box");
    hoverEl(@"title");

    // 强制重绘
    [gWindow displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    // 截图
    NSBitmapImageRep *rep = [gWindow.contentView bitmapImageRepForCachingDisplayInRect:gWindow.contentView.bounds];
    [gWindow.contentView cacheDisplayInRect:gWindow.contentView.bounds toBitmapImageRep:rep];

    NSData *imgData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [imgData writeToFile:@"/tmp/hud_visual_test.png" atomically:YES];
    printf("screenshot saved to /tmp/hud_visual_test.png\n");

    // 统计深色像素（HUD 背景 ~0.10, 0.10, 0.10 RGB）
    NSInteger darkPx = 0, total = 0;
    NSInteger sc = rep.samplesPerPixel;
    if (sc >= 3 && rep.bytesPerRow > 0) {
        uint8_t *p = (uint8_t *)[rep bitmapData];
        for (CGFloat yy = 0; yy < cv.bounds.size.height; yy += 2) {
            for (CGFloat xx = 0; xx < cv.bounds.size.width; xx += 2) {
                NSUInteger off = (NSUInteger)(yy * rep.bytesPerRow + xx * sc);
                if (p[off] < 50 && p[off+1] < 50 && p[off+2] < 70) {
                    darkPx++;
                }
                total++;
            }
        }
    }
    CGFloat frac = total > 0 ? (CGFloat)darkPx / total * 100.0 : 0;
    printf("dark-pixel ratio in window: %.1f%% (%ld/%ld)\n", frac, (long)darkPx, (long)total);
    if (frac >= 1.0) {
        printf("STATUS: HUD visible (dark background pixels detected)\n");
    } else {
        printf("STATUS: HUD might be invisible (no dark fill detected, but content view may use lighter scheme)\n");
    }

    printf("RESULT: %ld snapshots, HUD %s\n",
           (long)snapshotCount,
           gHUD ? "loaded" : "nil");
    return snapshotCount >= 3 ? 0 : 1;
} }
