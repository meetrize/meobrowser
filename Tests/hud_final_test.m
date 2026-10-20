#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorHUD.h"

static NSWindow *gWindow;
static WKWebView *gWebView;
static BrowserDOMInspectorHUD *gHUD;

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSRect winRect = NSMakeRect(150, 150, 900, 700);
    gWindow = [[NSWindow alloc] initWithContentRect:winRect
                                         styleMask:NSWindowStyleMaskTitled |
                                                   NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable |
                                                   NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    gWindow.title = @"DOM Inspector E2E";
    [gWindow makeKeyAndOrderFront:nil];

    NSView *cv = gWindow.contentView;
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    gWebView = [[WKWebView alloc] initWithFrame:cv.bounds configuration:config];
    gWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:gWebView];

    // 简单页面（避免 iframe 的同步渲染问题）+ 一个复杂嵌套 div
    NSString *html =
        @"<!DOCTYPE html><html><body style='margin:0;font:14px sans-serif;padding:0'>"
        @"<h1 id='title' style='background:#f5f5f5;padding:14px;margin:0'>"
        @"DOM Inspector Final Test</h1>"
        @"<div id='card' style='margin:16px;padding:14px;background:#3b82f6;color:white;"
        @"border-radius:10px;width:340px'>"
        @"<h2 id='card-title' style='margin:0;font-size:18px'>Card Heading</h2>"
        @"<p id='card-desc' style='margin:8px 0 0 0'>Card description text</p>"
        @"</div>"
        @"<table border=1 cellpadding=8 style='margin:16px;border-collapse:collapse'>"
        @"<tr id='row1'><td id='c1'>Cell A1</td><td id='c2'>Cell A2</td></tr>"
        @"<tr id='row2'><td id='c3'>Cell B1</td><td id='c4'>Cell B2</td></tr>"
        @"</table>"
        @"</body></html>";
    [gWebView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!gWebView.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    gHUD = [[BrowserDOMInspectorHUD alloc] init];
    __block NSInteger snapCount = 0;
    __block NSInteger pinnedCount = 0;
    __block NSString *lastType = nil, *lastTag = nil;
    __block NSDictionary *lastPayload = nil;

    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        snapCount++;
        lastType = type;
        lastTag = payload[@"tagName"];
        lastPayload = payload;
        if ([type isEqualToString:@"pinned"]) {
            pinnedCount++;
            [gHUD hide];
            printf("  PINNED tag=%s title=%s\n", lastTag.UTF8String,
                   [snapshot.title UTF8String]);
            return;
        }
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
        printf("  HOVER tag=%s geo=(%.0f,%.0f,%.0fx%.0f)\n",
               lastTag.UTF8String, x, y, w, h);
    };

    [bridge startInWebView:gWebView];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    void (^hover)(NSString *) = ^(NSString *idval) {
        NSString *js = [NSString stringWithFormat:
            @"var el=document.getElementById('%@');"
             "if(!el||!el.getBoundingClientRect)return false;"
             "var r=el.getBoundingClientRect();"
             "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+10,clientY:r.top+5}));"
             "return true;",
            idval];
        [gWebView evaluateJavaScript:js completionHandler:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    };

    printf("== Hover title ==\n");
    hover(@"title");
    printf("== Hover card-desc ==\n");
    hover(@"card-desc");
    printf("== Hover c4 (table cell) ==\n");
    hover(@"c4");
    printf("== Pin c1 ==\n");
    NSString *pinJS =
        @"var el=document.getElementById('c1');"
         "var r=el.getBoundingClientRect();"
         "el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));";
    [gWebView evaluateJavaScript:pinJS completionHandler:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    [gWindow displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    // 截图
    NSBitmapImageRep *rep = [gWindow.contentView bitmapImageRepForCachingDisplayInRect:gWindow.contentView.bounds];
    [gWindow.contentView cacheDisplayInRect:gWindow.contentView.bounds toBitmapImageRep:rep];
    NSData *imgData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [imgData writeToFile:@"/tmp/hud_final.png" atomically:YES];
    printf("screenshot saved to /tmp/hud_final.png\n");

    // 统计暗色像素（HUD 背景色~rgb(25,25,25)）
    NSInteger darkPx = 0, total = 0;
    NSInteger sc = rep.samplesPerPixel;
    if (sc >= 3 && rep.bytesPerRow > 0) {
        uint8_t *p = (uint8_t *)[rep bitmapData];
        for (CGFloat yy = 0; yy < cv.bounds.size.height; yy += 2) {
            for (CGFloat xx = 0; xx < cv.bounds.size.width; xx += 2) {
                NSUInteger off = (NSUInteger)(yy * rep.bytesPerRow + xx * sc);
                if (p[off] < 60 && p[off+1] < 60 && p[off+2] < 80) darkPx++;
                total++;
            }
        }
    }
    CGFloat frac = total > 0 ? (CGFloat)darkPx / total * 100.0 : 0;
    printf("HUD dark-pixel ratio: %.1f%% (%ld/%ld)\n", frac, (long)darkPx, (long)total);

    printf("\nFINAL RESULT: snapshots=%ld pinned=%ld\n", (long)snapCount, (long)pinnedCount);
    BOOL pass = snapCount >= 3 && pinnedCount >= 1 && frac >= 1.0;
    printf(pass ? "✓ TEST PASSED\n" : "✗ TEST FAILED\n");
    return pass ? 0 : 1;
} }

typedef struct { int unused; } snapshot; // dummy so struct `snapshot` exists if needed
