#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 端到端验证「iframe 内 hover → 原生 HUD 真的画出像素」。
/// 复刻 Controller→HUD 的几何换算，再把 HUD 视图挂进窗口，抓像素确认可见。

@interface HUD : NSView
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, copy) NSArray<NSString *> *attributeRows;
@property (nonatomic, assign) NSRect copyButtonRect;
@property (nonatomic, copy, nullable) void (^onCopySelector)(void);
@end

@implementation HUD
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)p { (void)p; return nil; }
- (void)drawRect:(NSRect)d {
    [[NSColor colorWithCalibratedWhite:0.10 alpha:0.97] setFill];
    NSRectFill(d);
    CGFloat y = 10;
    [self.titleText drawAtPoint:NSMakePoint(10, y) withAttributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]}];
    y += 18;
    [self.subtitleText drawAtPoint:NSMakePoint(10, y) withAttributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.7 alpha:1]}];
    y += 16;
    for (NSString *r in self.attributeRows) {
        [r drawAtPoint:NSMakePoint(10, y) withAttributes:@{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.9 alpha:1]}];
        y += 16;
    }
}
@end

@interface H : NSObject <WKScriptMessageHandler>
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, strong) NSDictionary *last;
@end

@implementation H
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *b = [m.body isKindOfClass:[NSDictionary class]] ? m.body : @{};
    if ([b[@"type"] isEqualToString:@"hover"]) { self.count++; self.last = b[@"payload"]; }
}
@end

static void pump(double s) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

static NSString *runJS(WKWebView *w, NSString *js) {
    __block NSString *out = nil;
    [w evaluateJavaScript:js completionHandler:^(id r, NSError *e) { out = [r description]; }];
    pump(0.25);
    return out;
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];

    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1920,938) configuration:cfg];

    NSString *inner =
        @"<html><body style='margin:40px;font:14px sans-serif'><table border=1 cellpadding=6>"
        @"<thead><tr><th data-field='mtasksname'><div class='th-inner '>任务名称(mtasksname)</div>"
        @"<div class='fht-cell' style='width:293px'></div></th></tr></thead>"
        @"<tbody><tr><td>报表A</td></tr></tbody></table></body></html>";
    NSString *outer = @"<html><body style='margin:0'>"
        "<div style='height:120px;background:#eee'>TOP</div>"
        "<iframe id='f' style='width:1100px;height:500px;border:0;margin-left:60px'></iframe>"
        "</body></html>";
    [web loadHTMLString:outer baseURL:[NSURL URLWithString:@"https://example.test/"]];
    pump(1.2);

    NSData *d = [NSJSONSerialization dataWithJSONObject:@[inner] options:0 error:NULL];
    NSString *ia = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    [web evaluateJavaScript:[NSString stringWithFormat:
        @"document.getElementById('f').srcdoc = %@; 'ok'",
        [ia substringWithRange:NSMakeRange(1, ia.length-2)]] completionHandler:nil];
    pump(0.8);

    NSString *script = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js" encoding:NSUTF8StringEncoding error:NULL];
    NSData *sd = [NSJSONSerialization dataWithJSONObject:@[script] options:0 error:NULL];
    NSString *sa = [[NSString alloc] initWithData:sd encoding:NSUTF8StringEncoding];
    NSString *drv = [NSString stringWithFormat:
        @"(function(){var S=%@;var seen=0;"
         "function inj(w){try{w.eval(S);seen++;return true;}catch(e){return false;}}"
         "function walk(w,d){if(d>6)return;if(!inj(w))return;"
         "try{w.addEventListener('load',function(){walk(w,d);},true);}catch(e){}"
         "var fs=[];try{fs=w.document.querySelectorAll('iframe,frame');}catch(e){return;}"
         "for(var i=0;i<fs.length;i++){try{var cw=fs[i].contentWindow;if(!cw)continue;cw.document;"
         "walk(cw,d+1);}catch(x){}}return seen;}"
         "walk(window,0);return seen;})()", [sa substringWithRange:NSMakeRange(1, sa.length-2)]];
    printf("inject: %s\n", runJS(web, drv).UTF8String);

    // 在 iframe 内派发 pointermove
    runJS(web,
        @"(function(){var cw=document.getElementById('f').contentWindow;"
         "var th=cw.document.querySelector('.th-inner');"
         "cw.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,"
         "clientX:th.getBoundingClientRect().left+100,clientY:th.getBoundingClientRect().top+10}));})()");
    pump(0.6);
    printf("messages from iframe: %ld\n", (long)h.count);

    NSDictionary *snap = h.last;
    if (!snap) { printf("NO SNAPSHOT -> message channel broken\n"); return 2; }

    NSDictionary *geo = snap[@"geometry"];
    printf("payload tag=%s selector=%s geometry=%s\n",
           [snap[@"tagName"] UTF8String], [snap[@"selector"] UTF8String],
           NSStringFromRect(NSMakeRect([geo[@"x"] doubleValue], [geo[@"y"] doubleValue],
                                        [geo[@"width"] doubleValue], [geo[@"height"] doubleValue])).UTF8String);

    // 复刻 Controller 的页面坐标 → contentView 坐标换算
    NSRect webFrame = web.frame;                 // contentView 坐标
    CGFloat px = [geo[@"x"] doubleValue], py = [geo[@"y"] doubleValue];
    CGFloat pw = [geo[@"width"] doubleValue], ph = [geo[@"height"] doubleValue];
    NSRect geoInContent = NSMakeRect(NSMinX(webFrame) + px,
                                     NSMaxY(webFrame) - (py + ph), pw, ph);
    printf("geoInContent=%s webFrame=%s\n",
           NSStringFromRect(geoInContent).UTF8String, NSStringFromRect(webFrame).UTF8String);

    // 建窗口并挂 HUD
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1920,1010)
                                               styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered defer:NO];
    [win makeKeyAndOrderFront:nil];
    [win.contentView addSubview:web];
    web.frame = webFrame;

    NSSize size = NSMakeSize(240, 10+18+16+16*2+10);
    HUD *realHUD = [[HUD alloc] initWithFrame:NSMakeRect(0,0,size.width,size.height)];
    realHUD.titleText = snap[@"tagName"] ?: @"";
    realHUD.subtitleText = @"320x24 @ (110,170)";
    realHUD.attributeRows = @[@"class=\"th-inner\"", @"data-field=\"mtasksname\""];

    // 复刻 frameForGeometry:
    NSRect content = win.contentView.bounds;
    CGFloat minY = NSMinY(webFrame), maxY = NSMaxY(webFrame);
    CGFloat x = NSMinX(geoInContent);
    CGFloat yTop = maxY - NSMaxY(geoInContent);
    CGFloat y = yTop + 14;
    if (y + size.height > maxY - minY) { y = yTop - 14 - size.height; }
    if (y < minY) y = minY;
    if (x < NSMinX(webFrame)) x = NSMinX(webFrame);
    if (x + size.width > NSMaxX(webFrame)) x = NSMaxX(webFrame) - size.width;
    NSRect hudFrame = NSMakeRect(x, NSHeight(content) - (y - minY) - size.height,
                                 size.width, size.height);
    printf("hudFrame=%s  (webView y range %g..%g)\n",
           NSStringFromRect(hudFrame).UTF8String, minY, maxY);

    realHUD.frame = hudFrame;
    [win.contentView addSubview:realHUD positioned:NSWindowAbove relativeTo:nil];
    [realHUD setNeedsDisplay:YES];
    [realHUD displayIfNeeded];
    pump(0.3);

    NSBitmapImageRep *rep = [win.contentView bitmapImageRepForCachingDisplayInRect:hudFrame];
    [win.contentView cacheDisplayInRect:hudFrame toBitmapImageRep:rep];
    NSUInteger dark = 0;
    for (int y2 = 0; y2 < rep.pixelsHigh; y2++)
        for (int x2 = 0; x2 < rep.pixelsWide; x2++)
            if ([[rep colorAtX:x2 y:y2] brightnessComponent] < 0.35) dark++;
    printf("HUD dark pixels: %lu / %ld -> %s\n", (unsigned long)dark,
           (long)(rep.pixelsWide*rep.pixelsHigh), dark > 500 ? "RENDERS" : "BLANK");
    return 0;
} }