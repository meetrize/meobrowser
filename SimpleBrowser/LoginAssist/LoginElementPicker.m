#import "LoginElementPicker.h"
#import "LoginAssistScriptMessageProxy.h"

static NSString * const kLoginAssistPickHandlerName = @"loginAssistPick";
static LoginElementPickerCompletion gActiveCompletion = nil;
static __weak WKWebView *gActiveWebView = nil;

@implementation LoginElementPicker

+ (void)registerMessageHandlerOnConfiguration:(WKWebViewConfiguration *)configuration
                                     handler:(id<WKScriptMessageHandler>)handler {
    if (!configuration || !handler) {
        return;
    }
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    [ucc removeScriptMessageHandlerForName:kLoginAssistPickHandlerName];
    LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
    proxy.target = handler;
    [ucc addScriptMessageHandler:proxy name:kLoginAssistPickHandlerName];
}

+ (void)cancelActivePick {
    WKWebView *webView = gActiveWebView;
    gActiveWebView = nil;
    LoginElementPickerCompletion completion = gActiveCompletion;
    gActiveCompletion = nil;
    if (webView) {
        [webView evaluateJavaScript:@"window.__meoLoginAssistStopPick && window.__meoLoginAssistStopPick();"
                  completionHandler:nil];
    }
    if (completion) {
        completion(nil, YES);
    }
}

+ (void)startPickingInWebView:(WKWebView *)webView completion:(LoginElementPickerCompletion)completion {
    [self cancelActivePick];
    if (!webView) {
        if (completion) {
            completion(nil, YES);
        }
        return;
    }
    gActiveWebView = webView;
    gActiveCompletion = [completion copy];

    NSString *script =
        @"(function() {\n"
         "  if (window.__meoLoginAssistStopPick) { window.__meoLoginAssistStopPick(); }\n"
         "  function escIdent(value) {\n"
         "    if (window.CSS && CSS.escape) { return CSS.escape(value); }\n"
         "    return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');\n"
         "  }\n"
         "  function cssPath(el) {\n"
         "    if (!el || el.nodeType !== 1) { return ''; }\n"
         "    if (el.id) {\n"
         "      const idSel = '#' + escIdent(el.id);\n"
         "      if (document.querySelectorAll(idSel).length === 1) { return idSel; }\n"
         "    }\n"
         "    const name = el.getAttribute('name');\n"
         "    if (name) {\n"
         "      const nameSel = el.tagName.toLowerCase() + '[name=\"' + name.replace(/\"/g, '\\\\\"') + '\"]';\n"
         "      if (document.querySelectorAll(nameSel).length === 1) { return nameSel; }\n"
         "    }\n"
         "    const auto = el.getAttribute('autocomplete');\n"
         "    if (auto) {\n"
         "      const autoSel = el.tagName.toLowerCase() + '[autocomplete=\"' + auto.replace(/\"/g, '\\\\\"') + '\"]';\n"
         "      if (document.querySelectorAll(autoSel).length === 1) { return autoSel; }\n"
         "    }\n"
         "    if (el.type) {\n"
         "      const typeSel = el.tagName.toLowerCase() + '[type=\"' + el.type + '\"]';\n"
         "      if (document.querySelectorAll(typeSel).length === 1) { return typeSel; }\n"
         "    }\n"
         "    const parts = [];\n"
         "    let node = el;\n"
         "    while (node && node.nodeType === 1 && node !== document.body && parts.length < 5) {\n"
         "      let part = node.tagName.toLowerCase();\n"
         "      const parent = node.parentElement;\n"
         "      if (parent) {\n"
         "        const siblings = Array.from(parent.children).filter(c => c.tagName === node.tagName);\n"
         "        if (siblings.length > 1) {\n"
         "          part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';\n"
         "        }\n"
         "      }\n"
         "      parts.unshift(part);\n"
         "      node = parent;\n"
         "    }\n"
         "    return parts.join(' > ');\n"
         "  }\n"
         "  const style = document.createElement('style');\n"
         "  style.id = '__meoLoginAssistPickStyle';\n"
         "  style.textContent = '.__meoLoginAssistHover{outline:2px solid #0a84ff!important;cursor:crosshair!important;}';\n"
         "  document.documentElement.appendChild(style);\n"
         "  let last = null;\n"
         "  function onMove(e) {\n"
         "    const t = e.target;\n"
         "    if (last && last !== t) { last.classList.remove('__meoLoginAssistHover'); }\n"
         "    if (t && t.classList) { t.classList.add('__meoLoginAssistHover'); last = t; }\n"
         "  }\n"
         "  function cleanup() {\n"
         "    document.removeEventListener('mousemove', onMove, true);\n"
         "    document.removeEventListener('click', onClick, true);\n"
         "    document.removeEventListener('keydown', onKey, true);\n"
         "    if (last) { last.classList.remove('__meoLoginAssistHover'); }\n"
         "    const s = document.getElementById('__meoLoginAssistPickStyle');\n"
         "    if (s) { s.remove(); }\n"
         "    window.__meoLoginAssistStopPick = null;\n"
         "  }\n"
         "  function onClick(e) {\n"
         "    e.preventDefault(); e.stopPropagation();\n"
         "    const sel = cssPath(e.target);\n"
         "    cleanup();\n"
         "    try { window.webkit.messageHandlers.loginAssistPick.postMessage({selector: sel}); } catch (err) {}\n"
         "  }\n"
         "  function onKey(e) {\n"
         "    if (e.key === 'Escape') {\n"
         "      e.preventDefault(); cleanup();\n"
         "      try { window.webkit.messageHandlers.loginAssistPick.postMessage({cancelled: true}); } catch (err) {}\n"
         "    }\n"
         "  }\n"
         "  window.__meoLoginAssistStopPick = cleanup;\n"
         "  document.addEventListener('mousemove', onMove, true);\n"
         "  document.addEventListener('click', onClick, true);\n"
         "  document.addEventListener('keydown', onKey, true);\n"
         "  return 'picking';\n"
         "})();";

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        if (error && gActiveCompletion) {
            LoginElementPickerCompletion cb = gActiveCompletion;
            gActiveCompletion = nil;
            gActiveWebView = nil;
            cb(nil, YES);
        }
    }];
}

+ (void)handleScriptMessageBody:(id)body {
    LoginElementPickerCompletion completion = gActiveCompletion;
    gActiveCompletion = nil;
    gActiveWebView = nil;
    if (!completion) {
        return;
    }
    if (![body isKindOfClass:[NSDictionary class]]) {
        completion(nil, YES);
        return;
    }
    NSDictionary *dict = (NSDictionary *)body;
    if ([dict[@"cancelled"] boolValue]) {
        completion(nil, YES);
        return;
    }
    NSString *selector = dict[@"selector"];
    if (![selector isKindOfClass:[NSString class]] || selector.length == 0) {
        completion(nil, YES);
        return;
    }
    completion(selector, NO);
}

@end
