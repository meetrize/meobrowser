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
                    "  // 另一段中文注释：abcdefg。"
                    "})();";
    NSLog(@"JS = <<%@>>", js);
    return 0;
}}