#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"
#import "BrowserDOMInspectorHUD.h"

static NSWindow *gWindow;
static WKWebView *gWebView;
static BrowserDOMInspectorHUD *gHUD;

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    NSRect winRect = NSMakeRect(100, 100, 900, 700);
    gWindow = [[NSWindow alloc] initWithContentRect:winRect
                                         styleMask:NSWindowStyleMaskTitled |
                                                   NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable |
                                                   NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    gWindow.title = @"HUD iframe Test";
    [gWindow makeKeyAndOrderFront:nil];

    NSView *cv = gWindow.contentView;
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    gWebView = [[WKWebView alloc] initWithFrame:cv.bounds configuration:config];
    gWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:gWebView];

    // 简化：父子各 3 个不同 id
    NSString *html =
        @"<!DOCTYPE html><html><body style='margin:0;font:14px sans-serif;padding:12px'>"
        @"<h1 id='p-title' style='background:#eee;padding:6px'>Parent Page Title</h1>"
        @"<iframe id='ifr1' src='about:blank' style='width:600px;height:200px;"
        @"border:1px solid #888;display:block;margin-top:8px'></iframe>"
        @"<script>"
        @"var inner = document.getElementById('ifr1');"
        @"var html2 = \"<!DOCTYPE html><html><body style='margin:0;padding:8px;background:#def;font:13px'>"
        @"<h2 id='f-title'>Iframe Title</h2>"
        @"<div id='f-box' style='width:300px;height:50px;background:#7c3aed;color:white;padding:8px;border-radius:6px'>Iframe Box</div>"
        @"</body></html>\";"
        @"inner.contentDocument.open(); inner.contentDocument.write(html2); inner.contentDocument.close();"
        @"</script>"
        @"</body></html>";
    [gWebView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!gWebView.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    gHUD = [[BrowserDOMInspectorHUD alloc] init];

    __block NSInteger snapshotCount = 0;
    __block NSInteger iframeCount = 0;
    __block NSInteger parentCount = 0;
    __block NSString *lastFrameMarker = @"-";
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        snapshotCount++;
        NSString *eid = payload[@"id"] ?: @"-";
        NSString *tag = payload[@"tagName"] ?: @"-";
        BOOL inFrame = [payload[@"frameId"] isKindOfClass:[NSString class]] && [payload[@"frameId"] length] > 0;
        if (inFrame) { iframeCount++; lastFrameMarker = @"FRAME"; }
        else { parentCount++; lastFrameMarker = @"PARENT"; }
        printf("  [%ld] type=%s tag=%s id=%s frame=%s\n", (long)snapshotCount, type.UTF8String,
               tag.UTF8String, eid.UTF8String, lastFrameMarker.UTF8String);

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

    void (^fire)(NSString *, NSString *) = ^(NSString *docSelector, NSString *idVal) {
        NSString *js = [NSString stringWithFormat:
            @"var d=%@;"
             "var el=(d.getElementById?d:document).getElementById('%@');"
             "if (!el) return false;"
             "var r=el.getBoundingClientRect();"
             "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+10,clientY:r.top+5}));"
             "return true;",
            docSelector, idVal];
        [gWebView evaluateJavaScript:js completionHandler:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
    };

    fire(@"document", @"p-title");
    fire(@"document.getElementById('ifr1').contentDocument", @"f-title");
    fire(@"document.getElementById('ifr1').contentDocument", @"f-box");

    [gWindow displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    NSBitmapImageRep *rep = [gWindow.contentView bitmapImageRepForCachingDisplayInRect:gWindow.contentView.bounds];
    [gWindow.contentView cacheDisplayInRect:gWindow.contentView.bounds toBitmapImageRep:rep];
    NSData *imgData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [imgData writeToFile:@"/tmp/hud_iframe_test.png" atomically:YES];
    printf("screenshot saved to /tmp/hud_iframe_test.png\n");

    printf("\nRESULT: parent=%ld iframe=%ld total=%ld\n",
           (long)parentCount, (long)iframeCount, (long)snapshotCount);
    if (snapshotCount >= 3) {
        printf("PASS: HUD receives snapshots from both parent and iframe\n");
    } else {
        printf("FAIL: expected >= 3 snapshots\n");
    }
    return snapshotCount >= 3 ? 0 : 1;
} }
