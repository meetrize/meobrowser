#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *js = @"(function(){"
                    "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) {"
                    "    window.__meoDomInspectorStart(); } } catch (e) {}"
                    "  // 广播给所有子框架（跨源同样可达）；子框架收到后继续向下转发，实现递归。"
                    "  var fs = [];"
                    "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }"
                    "  for (var i = 0; i < fs.length; i++) {"
                    "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1}, '*'); } catch (x) {}"
                    "  }"
                    "})();";
    NSData *d = [js dataUsingEncoding:NSUTF8StringEncoding];
    printf("len=%lu\n", (unsigned long)d.length);
    for (NSUInteger i = 0; i < d.length; i++) {
        unsigned char b = ((unsigned char*)d.bytes)[i];
        if (b == '\n' || b == '\r' || b == '\t') printf("\\%o", b);
        else if (b < 32 || b > 126) printf("\\x%02x", b);
        else printf("%c", b);
    }
    printf("\n--END--\n");
    return 0;
}}