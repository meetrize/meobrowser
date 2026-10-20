#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *js1 = @"(function(){"
                     "  try { if (window.__x) {"
                     "    window.__x(); } } catch (e) {}"
                     "  // hello"
                     "  var fs = [];"
                     "})();";
    NSData *d = [js1 dataUsingEncoding:NSUTF8StringEncoding];
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