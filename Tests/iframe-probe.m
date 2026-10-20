#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// 验证 iframe 场景：主框架注入后递归钻取同源 iframe，
/// 并把 iframe 内元素的坐标换算到顶层，确保气泡定位正确。

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

int main(int argc, const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication];
    H *h = [[H alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:h name:@"meoDomInspector"];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1200,800) configuration:cfg];

    NSString *inner =
        @"<html><body style='margin:40px;font:14px sans-serif'>"
        @"<table border=1 cellpadding=6>"
        @"<thead><tr><th style='text-align:center;vertical-align:middle' data-field='mtasksname'>"
        @"<div class='th-inner '>任务名称(mtasksname)</div>"
        @"<div class='fht-cell' style='width:293px'></div></th></tr></thead>"
        @"<tbody><tr><td>报表A</td></tr></tbody></table></body></html>";
    NSString *outer = [NSString stringWithFormat:
        @"<html><body style='margin:0'>"
         "<div style='height:120px;background:#eee'>TOP-NAV</div>"
         "<iframe id='f' style='width:1100px;height:500px;border:0;margin-left:60px'></iframe>"
         "</body></html>"];

    WKNavigation *nav = [web loadHTMLString:outer baseURL:[NSURL URLWithString:@"https://example.test/"]];
    (void)nav;
    pump(1.2);

    // 用 srcdoc 塞入内容（同源），确保 iframe 可被父页面访问
    NSData *innerData = [NSJSONSerialization dataWithJSONObject:@[inner] options:0 error:NULL];
    NSString *innerArr = [[NSString alloc] initWithData:innerData encoding:NSUTF8StringEncoding];
    NSString *innerEsc = [innerArr substringWithRange:NSMakeRange(1, innerArr.length - 2)];
    NSString *setSrc = [NSString stringWithFormat:
        @"document.getElementById('f').srcdoc = %@; 'ok'", innerEsc];
    __block NSString *r1 = nil;
    [web evaluateJavaScript:setSrc completionHandler:^(id r, NSError *e) { r1 = [r description]; }];
    pump(0.8);

    NSString *script = [NSString stringWithContentsOfFile:
        @"SimpleBrowser/Developer/.dom-inspector-script.js" encoding:NSUTF8StringEncoding error:NULL];

    // 复刻 Bridge 的注入方式：主框架执行 + 页面内递归钻取
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[script] options:0 error:NULL];
    NSString *arr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *escaped = [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
    NSString *bootstrap =
        @"(function(){if(window.__meoDomInspectorBooted)return;"
         "window.__meoDomInspectorBooted=true;"
         "window.__meoDomInspectorListen=function(){"
         "if(window.__meoDomInspectorReady)return;"
         "if(!window.__meoDomInspectorSource)return;"
         "window.__meoDomInspectorReady=true;"
         "try{(0,eval)(window.__meoDomInspectorSource);}catch(e){}};})();";

    NSString *driver = [NSString stringWithFormat:
        @"(function(){var S=%@;var seen=0;"
         "function inj(w){try{w.__meoDomInspectorSource=S;"
         "if(typeof w.__meoDomInspectorListen==='function'){w.__meoDomInspectorListen();}"
         "else{(0,eval)(S);}seen++;return true;}catch(e){return false;}}"
         "function walk(w,depth){if(depth>6)return;if(!inj(w))return;"
         "try{w.addEventListener('load',function(){walk(w,depth);},true);}catch(e){}"
         "var fs=[];try{fs=w.document.querySelectorAll('iframe,frame');}catch(e){return;}"
         "for(var i=0;i<fs.length;i++){try{var cw=fs[i].contentWindow;if(!cw)continue;cw.document;"
         "walk(cw,depth+1);}catch(x){}}return seen;}"
         "walk(window,0);return seen;})()", escaped];

    // 模拟 WKUserScript(forMainFrameOnly:NO)：bootstrap 在每个框架都存在。
// 这里手动给主框架和 iframe 各装一次，等价于真实环境。
[web evaluateJavaScript:bootstrap completionHandler:nil];
    __block NSString *boot2 = nil;
    [web evaluateJavaScript:
        @"(function(){try{var cw=document.getElementById('f').contentWindow;"
         "(0,eval)(arguments[0]);return 'ok';}catch(e){return 'X:'+e.name;}})()"
                completionHandler:nil];
    (void)boot2;
    pump(0.2);
    __block NSString *injected = nil;
    [web evaluateJavaScript:driver completionHandler:^(id r, NSError *e) { injected = [r description]; }];
    pump(0.6);
    printf("injected into %s frame(s)\n", injected ? injected.UTF8String : "(nil)");

    __block NSString *frameInfo = nil;
    [web evaluateJavaScript:
        @"(function(){var f=document.getElementById('f');var cw=f.contentWindow;"
         "var diag='n/a';"
         "try{ var d=cw.document; diag='ok title='+d.title+' th='+!!d.querySelector('.th-inner'); }catch(x){ diag='XDOM:'+x.name; }"
         "var ins='no';try{ins=!!cw.__meoDomInspectorStop;}catch(x){ins='X:'+x.name;}"
         "var th=cw.document.querySelector('.th-inner');"
         "var fr=f.getBoundingClientRect();"
         "var tr=th?th.getBoundingClientRect():null;"
         "return JSON.stringify({iframeHasProbe:ins, diag:diag, iframeRect:[Math.round(fr.left),Math.round(fr.top),Math.round(fr.width),Math.round(fr.height)],"
         " thInFrame:[tr?Math.round(tr.left):-1, tr?Math.round(tr.top):-1]});})()"
                completionHandler:^(id r, NSError *e) { frameInfo = [r description]; }];
    pump(0.4);
    printf("frame info: %s\n", frameInfo ? frameInfo.UTF8String : "(nil)");

    // 在 iframe 内元素上派发 pointermove，验证消息与坐标换算
    __block NSString *hv = nil;
    [web evaluateJavaScript:
        @"(function(){var cw=document.getElementById('f').contentWindow;"
         "var th=cw.document.querySelector('.th-inner');"
         "var r=th.getBoundingClientRect();"
         "var x=r.left+r.width/2,y=r.top+r.height/2;"
         "cw.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,clientX:x,clientY:y}));"
         "return 'dispatched at '+Math.round(x)+','+Math.round(y);})()"
                completionHandler:^(id r, NSError *e) { hv = [r description]; }];
    pump(0.6);
    printf("hover: %s  messages=%ld\n", hv ? hv.UTF8String : "(nil)", (long)h.count);

    if (h.last) {
        NSDictionary *g = h.last[@"geometry"];
        printf("reported geometry: %s  tag=%s selector=%s\n",
               NSStringFromRect(NSMakeRect([g[@"x"] doubleValue], [g[@"y"] doubleValue],
                                            [g[@"width"] doubleValue], [g[@"height"] doubleValue])).UTF8String,
               [h.last[@"tagName"] UTF8String], [h.last[@"selector"] UTF8String]);
    }
    return h.count > 0 ? 0 : 2;
} }