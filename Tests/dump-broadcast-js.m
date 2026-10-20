#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

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
    NSLog(@"JS = <<%@>>", js);
    NSLog(@"length=%lu", (unsigned long)js.length);
    for (NSUInteger i = 0; i < js.length; i++) {
        unichar ch = [js characterAtIndex:i];
        if (ch < 32 && ch != '\n' && ch != '\r' && ch != '\t') {
            printf("BAD CHAR at %lu: 0x%02x\n", (unsigned long)i, ch);
        }
    }
    printf("DONE\n");
    return 0;
}}