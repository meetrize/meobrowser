#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BrowserDOMInspectorBridge.h"

@interface TestHarness : NSObject
@property NSInteger hoverTotal;
@property NSInteger pinnedTotal;
@end
@implementation TestHarness @end

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    TestHarness *h = [[TestHarness alloc] init];

    NSRect winRect = NSMakeRect(200, 200, 900, 700);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:winRect
                                                styleMask:NSWindowStyleMaskTitled |
                                                          NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskMiniaturizable |
                                                          NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    window.title = @"HUD Test";
    [window makeKeyAndOrderFront:nil];

    NSView *contentView = window.contentView;
    CGFloat ww = NSWidth(contentView.bounds);
    CGFloat wh = NSHeight(contentView.bounds);
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    [BrowserDOMInspectorBridge installOnConfiguration:config];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, ww, wh)
                                            configuration:config];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:webView];

    NSString *html =
        @"<html><body style='margin:0;font:14px sans-serif;padding:10px'>"
        @"<h1 id='title' style='background:#eee;padding:8px'>HUD Test Title</h1>"
        @"<p id='para1' style='margin-top:8px'>Hover me to see tooltip</p>"
        @"<div id='box' style='width:300px;height:120px;background:#3b82f6;"
        @"color:white;padding:16px;margin-top:16px;border-radius:8px'>"
        @"Blue box - hover or click to pin</div>"
        @"</body></html>";
    [webView loadHTMLString:html baseURL:[NSURL URLWithString:@"https://example.test/"]];
    for (int i = 0; i < 100; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!webView.isLoading) break;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    printf("== Start probe ==\n");
    BrowserDOMInspectorBridge *bridge = [[BrowserDOMInspectorBridge alloc] init];
    bridge.onSnapshot = ^(NSString *type, NSDictionary *payload) {
        if ([type isEqualToString:@"hover"]) h.hoverTotal++;
        if ([type isEqualToString:@"pinned"]) h.pinnedTotal++;
        printf("  [bridge] type=%s tag=%s\n", type.UTF8String,
               [payload[@"tagName"] ?: @"-" UTF8String]);

        if ([type isEqualToString:@"pinned"]) {
            printf("  [HUD simulate] -> PINNED: panel would show\n");
            return;
        }

        // === 模拟 BrowserDOMInspectorController.handleSnapshotType ===
        NSDictionary *geo = [payload[@"geometry"] isKindOfClass:[NSDictionary class]] ? payload[@"geometry"] : nil;
        if (!geo) { printf("  [HUD] no geometry, skip\n"); return; }

        CGFloat x = [geo[@"x"] doubleValue];
        CGFloat y = [geo[@"y"] doubleValue];
        CGFloat ew = [geo[@"width"] doubleValue];
        CGFloat eh = [geo[@"height"] doubleValue];

        NSRect webFrameInWindow = [webView convertRect:webView.bounds toView:window.contentView];
        CGFloat windowY = NSMaxY(webFrameInWindow) - (y + eh);
        NSRect geoInContent = NSMakeRect(NSMinX(webFrameInWindow) + x, windowY, ew, eh);
        NSRect webViewInContent = webFrameInWindow;

        // === 模拟 BrowserDOMInspectorHUD ===
        static const CGFloat kHUDMaxWidth = 340.0;
        static const CGFloat kHUDPadding = 10.0;
        static const CGFloat kHUDTitleHeight = 18.0;
        static const CGFloat kHUDRowHeight = 16.0;
        static const NSUInteger kHUDMaxAttributeRows = 8;

        NSString *tag = [payload[@"tagName"] isKindOfClass:[NSString class]] ? payload[@"tagName"] : @"";
        NSString *elemID = [payload[@"id"] isKindOfClass:[NSString class]] ? payload[@"id"] : @"";
        NSString *titleText = elemID.length > 0
            ? [NSString stringWithFormat:@"%@#%@", tag, elemID] : tag;

        NSFont *titleFont = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold];
        NSFont *bodyFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        CGFloat hudWidth = MIN(ceil([titleText sizeWithAttributes:@{NSFontAttributeName: titleFont}].width)
                               + kHUDPadding * 2 + 46, kHUDMaxWidth);

        NSArray *attrs = [payload[@"attributes"] isKindOfClass:[NSArray class]] ? payload[@"attributes"] : @[];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *attr in attrs) {
            if (rows.count >= kHUDMaxAttributeRows) break;
            NSString *aname = [attr[@"name"] isKindOfClass:[NSString class]] ? attr[@"name"] : nil;
            if (aname.length == 0 || [aname isEqualToString:@"class"]) continue;
            NSString *aval = [attr[@"value"] isKindOfClass:[NSString class]] ? attr[@"value"] : @"";
            [rows addObject:[NSString stringWithFormat:@"%@=\"%@\"", aname, aval]];
        }
        CGFloat hudHeight = kHUDPadding * 2 + kHUDTitleHeight + rows.count * kHUDRowHeight;
        NSSize hudSize = NSMakeSize(hudWidth, hudHeight);

        // frameForGeometry（与 HUD 完全一致）
        NSRect content = window.contentView.bounds;
        CGFloat minX = NSMinX(webViewInContent);
        CGFloat minY = NSMinY(webViewInContent);
        CGFloat maxX = NSMaxX(webViewInContent);
        CGFloat maxY = NSMaxY(webViewInContent);
        CGFloat tx = NSMinX(geoInContent);
        CGFloat yTop = maxY - NSMaxY(geoInContent);
        static const CGFloat gap = 14.0;
        CGFloat yy = yTop + gap;
        if (yy + hudHeight > maxY) yy = yTop - gap - hudHeight;
        if (yy < minY) yy = minY;
        if (tx < minX) tx = minX;
        if (tx + hudWidth > maxX) tx = maxX - hudWidth;
        CGFloat hudY = NSHeight(content) - (yy - minY) - hudHeight;
        NSRect hudFrame = NSMakeRect(tx, hudY, hudWidth, hudHeight);

        NSRect visible = NSIntersectionRect(hudFrame, content);
        CGFloat visFrac = (hudFrame.size.width * hudFrame.size.height) > 0
            ? (visible.size.width * visible.size.height) / (hudFrame.size.width * hudFrame.size.height)
            : 0;

        printf("  [HUD] geoInContent=(%.0f,%.0f,%.0fx%.0f)\n",
               geoInContent.origin.x, geoInContent.origin.y, geoInContent.size.width, geoInContent.size.height);
        printf("  [HUD] webViewInContent=(%.0f,%.0f,%.0fx%.0f)\n",
               webViewInContent.origin.x, webViewInContent.origin.y,
               webViewInContent.size.width, webViewInContent.size.height);
        printf("  [HUD] content=(%.0fx%.0f) webFrameInWindow=(%.0f,%.0f,%.0fx%.0f)\n",
               content.size.width, content.size.height,
               webFrameInWindow.origin.x, webFrameInWindow.origin.y,
               webFrameInWindow.size.width, webFrameInWindow.size.height);
        printf("  [HUD] hudSize=%.0fx%.0f hudFrame(flipped)=(%.0f,%.0f,%.0fx%.0f)\n",
               hudSize.width, hudSize.height,
               hudFrame.origin.x, hudFrame.origin.y, hudFrame.size.width, hudFrame.size.height);
        if (visFrac >= 0.5) {
            printf("  [HUD] STATUS: WILL BE VISIBLE (%.0f%% visible)\n", visFrac * 100);
        } else {
            printf("  [HUD] STATUS: CLIPPED/WARNING (only %.0f%% visible)\n", visFrac * 100);
        }
    };

    [bridge startInWebView:webView];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    void (^hoverEl)(NSString *) = ^(NSString *elId) {
        NSString *js = [NSString stringWithFormat:
            @"var el=document.getElementById('%@');"
             "var r=el.getBoundingClientRect();"
             "el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,clientX:r.left+5,clientY:r.top+5}));",
            elId];
        [webView evaluateJavaScript:js completionHandler:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    };

    printf("== Hover para1 ==\n");
    hoverEl(@"para1");
    printf("== Hover box ==\n");
    hoverEl(@"box");
    printf("== Hover title ==\n");
    hoverEl(@"title");

    printf("\nRESULT: hover=%ld pinned=%ld\n", (long)h.hoverTotal, (long)h.pinnedTotal);
    [bridge stop];
    return (h.hoverTotal >= 3) ? 0 : 1;
} }
