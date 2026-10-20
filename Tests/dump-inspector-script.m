#import <Foundation/Foundation.h>
#import "BrowserDOMInspectorScript.h"

/// 把注入脚本导出为文件，供 Tests/dom-inspector-e2e.m 做端到端验证。
int main(void) { @autoreleasepool {
    NSString *js = [BrowserDOMInspectorScript startScript];
    NSString *out = @"SimpleBrowser/Developer/.dom-inspector-script.js";
    NSError *err = nil;
    BOOL ok = [js writeToFile:out atomically:YES encoding:NSUTF8StringEncoding error:&err];
    printf("%s -> %s (%lu bytes) %s\n", out.UTF8String, ok ? "written" : "FAILED",
           (unsigned long)js.length, err ? err.localizedDescription.UTF8String : "");
    return ok ? 0 : 1;
} }
