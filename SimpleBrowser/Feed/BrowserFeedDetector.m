#import "BrowserFeedDetector.h"
#import "LoginAssistScriptMessageProxy.h"

NSString * const BrowserFeedAssistHandlerName = @"meoFeedAssist";

@implementation BrowserFeedDetector

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
                messageHandler:(id<WKScriptMessageHandler>)handler {
    if (!configuration || !handler) {
        return;
    }

    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }

    [ucc removeScriptMessageHandlerForName:BrowserFeedAssistHandlerName];
    LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
    proxy.target = handler;
    [ucc addScriptMessageHandler:proxy name:BrowserFeedAssistHandlerName];

    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self userScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)userScriptSource {
    // Chrome / RSS Autodiscovery：扫描 <link rel="alternate|feed"> + RSS/Atom MIME。
    return @
    "(function() {\n"
    "  function post(payload) {\n"
    "    try {\n"
    "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoFeedAssist) {\n"
    "        window.webkit.messageHandlers.meoFeedAssist.postMessage(payload);\n"
    "      }\n"
    "    } catch (e) {}\n"
    "  }\n"
    "\n"
    "  function isFeedType(type) {\n"
    "    if (!type) return false;\n"
    "    var t = String(type).toLowerCase();\n"
    "    if (t.indexOf('application/rss+xml') !== -1) return true;\n"
    "    if (t.indexOf('application/atom+xml') !== -1) return true;\n"
    "    if (t.indexOf('application/feed+json') !== -1) return true;\n"
    "    if (t.indexOf('application/rdf+xml') !== -1) return true;\n"
    "    if ((t.indexOf('xml') !== -1 || t.indexOf('json') !== -1) &&\n"
    "        (t.indexOf('rss') !== -1 || t.indexOf('atom') !== -1 || t.indexOf('feed') !== -1)) {\n"
    "      return true;\n"
    "    }\n"
    "    return false;\n"
    "  }\n"
    "\n"
    "  function hasFeedRel(rel) {\n"
    "    if (!rel) return false;\n"
    "    var parts = String(rel).toLowerCase().split(/\\s+/);\n"
    "    for (var i = 0; i < parts.length; i++) {\n"
    "      if (parts[i] === 'alternate' || parts[i] === 'feed') return true;\n"
    "    }\n"
    "    return false;\n"
    "  }\n"
    "\n"
    "  function absoluteURL(href) {\n"
    "    try { return new URL(href, document.baseURI || location.href).href; }\n"
    "    catch (e) { return null; }\n"
    "  }\n"
    "\n"
    "  function scan() {\n"
    "    var nodes = document.querySelectorAll('link[rel]');\n"
    "    var seen = {};\n"
    "    var feeds = [];\n"
    "    for (var i = 0; i < nodes.length; i++) {\n"
    "      var el = nodes[i];\n"
    "      var rel = el.getAttribute('rel');\n"
    "      var type = el.getAttribute('type') || '';\n"
    "      var href = el.getAttribute('href');\n"
    "      if (!href || !hasFeedRel(rel) || !isFeedType(type)) continue;\n"
    "      var url = absoluteURL(href);\n"
    "      if (!url || seen[url]) continue;\n"
    "      seen[url] = true;\n"
    "      feeds.push({\n"
    "        title: (el.getAttribute('title') || '').trim(),\n"
    "        url: url,\n"
    "        type: type\n"
    "      });\n"
    "    }\n"
    "    post({ event: 'feeds', feeds: feeds, pageURL: location.href });\n"
    "  }\n"
    "\n"
    "  scan();\n"
    "  var scheduled = false;\n"
    "  function schedule() {\n"
    "    if (scheduled) return;\n"
    "    scheduled = true;\n"
    "    setTimeout(function() { scheduled = false; scan(); }, 800);\n"
    "  }\n"
    "  try {\n"
    "    var obs = new MutationObserver(schedule);\n"
    "    obs.observe(document.documentElement || document, { childList: true, subtree: true });\n"
    "  } catch (e) {}\n"
    "})();\n";
}

@end
