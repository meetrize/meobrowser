#import <Cocoa/Cocoa.h>
#import "MeoApplication.h"
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        // 必须先创建 MeoApplication，否则 NSApp 会是默认 NSApplication，无法拦截激活。
        [MeoApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
