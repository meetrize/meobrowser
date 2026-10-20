#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *exact = @"(function(){"
                      "  try { if (window.__meoDomInspectorStart && !window.__meoDomInspectorStop) {"
                      "    window.__meoDomInspectorStart(); } } catch (e) {}"
                      "  // broadcast to iframes"
                      "  var fs = [];"
                      "  try { fs = document.querySelectorAll('iframe,frame'); } catch (e) { return; }"
                      "  for (var i = 0; i < fs.length; i++) {"
                      "    try { fs[i].contentWindow.postMessage({__meo:'dom-inspector','on':1}, '*'); } catch (x) {}"
                      "  }"
                      "})();";
    NSData *d = [exact dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++) {
        unsigned char b = ((unsigned char*)d.bytes)[i];
        if (b == '\n') [hex appendString:@"\\n"];
        else if (b >= 32 && b < 127) [hex appendFormat:@"%c", b];
        else [hex appendFormat:@"\\x%02x", b];
    }
    NSLog(@"LENGTH=%lu\n%@", (unsigned long)d.length, hex);
    return 0;
}}