#import "BrowserWebInspector.h"
#import "BrowserDeveloperPreferences.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

@implementation BrowserWebInspector

+ (BOOL)isInspectionSupported {
    if (@available(macOS 13.3, *)) {
        return YES;
    }
    return NO;
}

+ (void)applyDeveloperExtrasEnabled:(BOOL)enabled toWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    // 私有偏好：为右键「检查元素」与程序化 show 提供底座；inspectable  alone 往往不够。
    @try {
        [webView.configuration.preferences setValue:@(enabled) forKey:@"developerExtrasEnabled"];
    } @catch (__unused NSException *exception) {
    }
}

+ (void)applyInspectableToWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    BOOL allow = [BrowserDeveloperPreferences sharedPreferences].allowWebInspection;
    if (@available(macOS 13.3, *)) {
        webView.inspectable = allow;
    }
    [self applyDeveloperExtrasEnabled:allow toWebView:webView];
}

+ (nullable id)inspectorForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return nil;
    }
    id inspector = nil;
    @try {
        inspector = [webView valueForKey:@"_inspector"];
    } @catch (__unused NSException *exception) {
        inspector = nil;
    }
    if (inspector != nil) {
        return inspector;
    }

    SEL inspectorSel = NSSelectorFromString(@"_inspector");
    if (class_getInstanceMethod(object_getClass(webView), inspectorSel) == NULL
        && ![webView respondsToSelector:inspectorSel]) {
        return nil;
    }
    id (*inspectorMsg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return inspectorMsg(webView, inspectorSel);
}

+ (BOOL)invokeInspector:(id)inspector selectorName:(NSString *)name {
    if (inspector == nil || name.length == 0) {
        return NO;
    }
    SEL sel = NSSelectorFromString(name);
    if (![inspector respondsToSelector:sel]
        && class_getInstanceMethod(object_getClass(inspector), sel) == NULL) {
        return NO;
    }
    @try {
        void (*msg)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
        msg(inspector, sel);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

+ (BOOL)showInspectorForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return NO;
    }
    if (![self isInspectionSupported]) {
        return NO;
    }
    if (![BrowserDeveloperPreferences sharedPreferences].allowWebInspection) {
        return NO;
    }

    [self applyInspectableToWebView:webView];

#if MEO_ENABLE_PRIVATE_INSPECTOR_SHOW
    id inspector = [self inspectorForWebView:webView];
    if (inspector == nil) {
        return NO;
    }

    // 部分版本需先 connect，再 show。
    [self invokeInspector:inspector selectorName:@"connect"];
    if ([self invokeInspector:inspector selectorName:@"show"]) {
        // 尝试分离为独立窗口（失败可忽略）。
        [self invokeInspector:inspector selectorName:@"detach"];
        return YES;
    }
    if ([self invokeInspector:inspector selectorName:@"showConsole"]) {
        return YES;
    }
    return NO;
#else
    (void)webView;
    return NO;
#endif
}

@end
