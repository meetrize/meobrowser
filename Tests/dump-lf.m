#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *js1 = @"(function(){"
                     "  try { if (window.__x) {"
                     "    window.__x(); } } catch (e) {}"
                     "  // hello"
                     "  var fs = [];"
                     "})();";
    NSData *d = [js1 dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"LENGTH=%lu", (unsigned long)d.length);
    // 列出所有 LF 位置
    NSUInteger lf = 0;
    for (NSUInteger i = 0; i < d.length; i++) {
        unsigned char b = ((unsigned char*)d.bytes)[i];
        if (b == 0x0A) {
            printf("LF at %lu\n", (unsigned long)i);
            lf++;
        }
    }
    printf("total LF: %lu\n", (unsigned long)lf);
    return 0;
}}