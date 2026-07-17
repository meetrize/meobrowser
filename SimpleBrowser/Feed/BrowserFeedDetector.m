#import "BrowserFeedDetector.h"
#import "BrowserFeedItem.h"
#import "BrowserFeedReader.h"
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

+ (NSString *)scanFeedsJavaScriptBody {
    // 1) 标准 RSS Autodiscovery：<link rel="alternate|feed" type="rss|atom|...">
    // 2) 宽松：href 看起来像 Feed（/feed、.rss 等），即使缺 type
    // 3) 页面内 <a href> 指向同类路径（不少站点只放文字链接、不写 link）
    return @
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
    "  function hrefLooksLikeFeed(href) {\n"
    "    try {\n"
    "      var u = new URL(href, document.baseURI || location.href);\n"
    "      var p = (u.pathname || '').toLowerCase();\n"
    "      if (/\\/feed\\/?$/.test(p) || /\\/rss\\/?$/.test(p) || /\\/atom\\/?$/.test(p) || /\\/feeds\\/?$/.test(p)) return true;\n"
    "      if (p.indexOf('/feed.') !== -1 || p.indexOf('/rss.') !== -1 || p.indexOf('/atom.') !== -1) return true;\n"
    "      if (/\\.(rss|atom)$/.test(p)) return true;\n"
    "      if (/\\/(atom|feed|rss|index)\\.xml$/.test(p)) return true;\n"
    "      return false;\n"
    "    } catch (e) { return false; }\n"
    "  }\n"
    "\n"
    "  function absoluteURL(href) {\n"
    "    try { return new URL(href, document.baseURI || location.href).href; }\n"
    "    catch (e) { return null; }\n"
    "  }\n"
    "\n"
    "  function addFeed(feeds, seen, href, title, type) {\n"
    "    var url = absoluteURL(href);\n"
    "    if (!url || seen[url]) return;\n"
    "    seen[url] = true;\n"
    "    feeds.push({ title: (title || '').trim(), url: url, type: type || '' });\n"
    "  }\n"
    "\n"
    "  function scanLinks(feeds, seen) {\n"
    "    var nodes = document.querySelectorAll('link[href]');\n"
    "    for (var i = 0; i < nodes.length; i++) {\n"
    "      var el = nodes[i];\n"
    "      var rel = el.getAttribute('rel');\n"
    "      var type = el.getAttribute('type') || '';\n"
    "      var href = el.getAttribute('href');\n"
    "      if (!href) continue;\n"
    "      var typed = isFeedType(type);\n"
    "      var related = hasFeedRel(rel);\n"
    "      var pathLike = hrefLooksLikeFeed(href);\n"
    "      // 标准：rel + type；或 type 已标明 Feed；或 rel=alternate 且路径像 Feed；或纯路径启发式\n"
    "      if (!((related && typed) || typed || (related && pathLike) || pathLike)) continue;\n"
    "      addFeed(feeds, seen, href, el.getAttribute('title') || '', type);\n"
    "    }\n"
    "  }\n"
    "\n"
    "  function scanAnchors(feeds, seen) {\n"
    "    var nodes = document.querySelectorAll('a[href]');\n"
    "    for (var i = 0; i < nodes.length; i++) {\n"
    "      var el = nodes[i];\n"
    "      var href = el.getAttribute('href');\n"
    "      if (!href || !hrefLooksLikeFeed(href)) continue;\n"
    "      var title = (el.getAttribute('title') || el.textContent || '').trim();\n"
    "      if (title.length > 80) title = title.slice(0, 77) + '…';\n"
    "      addFeed(feeds, seen, href, title, '');\n"
    "    }\n"
    "  }\n"
    "\n"
    "  function collect() {\n"
    "    var seen = {};\n"
    "    var feeds = [];\n"
    "    try { scanLinks(feeds, seen); } catch (e) {}\n"
    "    try { scanAnchors(feeds, seen); } catch (e) {}\n"
    "    return feeds;\n"
    "  }\n";
}

+ (NSString *)scanFeedsJavaScript {
    return [NSString stringWithFormat:
            @"(function(){\n"
            @"  try {\n"
            @"%@\n"
            @"    return collect();\n"
            @"  } catch (e) { return []; }\n"
            @"})()",
            [self scanFeedsJavaScriptBody]];
}

+ (NSString *)userScriptSource {
    return [NSString stringWithFormat:
            @"(function() {\n"
            @"  function post(payload) {\n"
            @"    try {\n"
            @"      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoFeedAssist) {\n"
            @"        window.webkit.messageHandlers.meoFeedAssist.postMessage(payload);\n"
            @"      }\n"
            @"    } catch (e) {}\n"
            @"  }\n"
            @"\n"
            @"%@\n"
            @"\n"
            @"  function scan() {\n"
            @"    post({ event: 'feeds', feeds: collect(), pageURL: location.href });\n"
            @"  }\n"
            @"\n"
            @"  scan();\n"
            @"  var scheduled = false;\n"
            @"  function schedule() {\n"
            @"    if (scheduled) return;\n"
            @"    scheduled = true;\n"
            @"    setTimeout(function() { scheduled = false; scan(); }, 800);\n"
            @"  }\n"
            @"  try {\n"
            @"    var obs = new MutationObserver(schedule);\n"
            @"    obs.observe(document.documentElement || document, { childList: true, subtree: true });\n"
            @"  } catch (e) {}\n"
            @"})();\n",
            [self scanFeedsJavaScriptBody]];
}

+ (NSArray<BrowserFeedItem *> *)feedItemsFromDictionaries:(NSArray *)raw {
    if (![raw isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<BrowserFeedItem *> *parsed = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *feedDict = (NSDictionary *)item;
        NSString *urlString = feedDict[@"url"];
        if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
            continue;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url || [seen containsObject:url.absoluteString]) {
            continue;
        }
        [seen addObject:url.absoluteString];

        BrowserFeedItem *feed = [[BrowserFeedItem alloc] init];
        NSString *title = feedDict[@"title"];
        feed.title = [title isKindOfClass:[NSString class]] && title.length > 0
            ? title
            : (url.host ?: urlString);
        feed.url = url;
        NSString *type = feedDict[@"type"];
        feed.mimeType = [type isKindOfClass:[NSString class]] ? type : nil;
        [parsed addObject:feed];
    }
    return [parsed copy];
}

#pragma mark - Conventional path probe

+ (NSArray<NSString *> *)conventionalFeedPaths {
    // 覆盖 WordPress /feed、常见静态 rss/atom，以及部分中文站点习惯路径。
    return @[
        @"/feed",
        @"/feed/",
        @"/rss",
        @"/rss/",
        @"/atom.xml",
        @"/feed.xml",
        @"/rss.xml",
        @"/index.xml",
        @"/atom",
        @"/feeds",
    ];
}

+ (NSArray<NSURL *> *)conventionalFeedCandidateURLsForPageURL:(NSURL *)pageURL {
    if (!pageURL || pageURL.scheme.length == 0 || pageURL.host.length == 0) {
        return @[];
    }
    NSString *scheme = pageURL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return @[];
    }

    NSURLComponents *origin = [[NSURLComponents alloc] init];
    origin.scheme = pageURL.scheme;
    origin.host = pageURL.host;
    origin.port = pageURL.port;

    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^addURL)(NSURL *) = ^(NSURL *url) {
        if (!url.absoluteString.length || [seen containsObject:url.absoluteString]) {
            return;
        }
        [seen addObject:url.absoluteString];
        [candidates addObject:url];
    };

    for (NSString *path in [self conventionalFeedPaths]) {
        origin.path = path;
        addURL(origin.URL);
    }

    // 当前目录下的相对常见路径（如 https://example.com/blog/ → /blog/feed）
    NSString *pagePath = pageURL.path ?: @"/";
    if (pagePath.length > 1) {
        NSString *dir = pagePath;
        if (![dir hasSuffix:@"/"]) {
            dir = [dir stringByDeletingLastPathComponent];
            if (dir.length == 0) {
                dir = @"/";
            }
        }
        if (![dir hasSuffix:@"/"]) {
            dir = [dir stringByAppendingString:@"/"];
        }
        if (![dir isEqualToString:@"/"]) {
            for (NSString *suffix in @[ @"feed", @"feed/", @"rss", @"rss.xml", @"atom.xml" ]) {
                origin.path = [dir stringByAppendingString:suffix];
                addURL(origin.URL);
            }
        }
    }

    return [candidates copy];
}

+ (BOOL)bodySniffLooksLikeFeed:(NSData *)data {
    if (data.length == 0) {
        return NO;
    }
    NSUInteger len = MIN(data.length, (NSUInteger)512);
    NSData *prefix = [data subdataWithRange:NSMakeRange(0, len)];
    NSString *text = [[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:prefix encoding:NSISOLatin1StringEncoding];
    }
    if (text.length == 0) {
        return NO;
    }
    NSString *lower = text.lowercaseString;
    // 跳过 HTML 壳（安全检测页等）
    if ([lower containsString:@"<html"] || [lower containsString:@"<!doctype html"]) {
        return NO;
    }
    return [lower containsString:@"<rss"] ||
           [lower containsString:@"<feed"] ||
           [lower containsString:@"<rdf:rdf"] ||
           [lower containsString:@"\"version\":\"https://jsonfeed.org"];
}

+ (NSURLSessionTask *)probeConventionalFeedsForPageURL:(NSURL *)pageURL
                                    completionHandler:(void (^)(NSArray<BrowserFeedItem *> *feeds))completionHandler {
    if (!completionHandler) {
        return nil;
    }
    NSArray<NSURL *> *candidates = [self conventionalFeedCandidateURLsForPageURL:pageURL];
    if (candidates.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(@[]);
        });
        return nil;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 4.0;
    config.HTTPAdditionalHeaders = @{
        @"Accept": @"application/rss+xml, application/atom+xml, application/feed+json, application/xml, text/xml, */*;q=0.8",
        @"User-Agent": @"MeoBrowser FeedProbe/1.0"
    };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSMutableArray<BrowserFeedItem *> *found = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t lockQueue = dispatch_queue_create("meo.feed.probe", DISPATCH_QUEUE_SERIAL);

    // 限制并发探测数量，优先靠前的常见路径。
    NSUInteger limit = MIN(candidates.count, (NSUInteger)8);
    for (NSUInteger i = 0; i < limit; i++) {
        NSURL *candidate = candidates[i];
        dispatch_group_enter(group);
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:candidate];
        request.HTTPMethod = @"HEAD";
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *headData, NSURLResponse *response, NSError *error) {
            (void)headData;
            void (^finishOne)(BOOL, NSString *) = ^(BOOL ok, NSString *mime) {
                if (ok) {
                    dispatch_sync(lockQueue, ^{
                        if ([seen containsObject:candidate.absoluteString]) {
                            return;
                        }
                        [seen addObject:candidate.absoluteString];
                        BrowserFeedItem *item = [[BrowserFeedItem alloc] init];
                        item.url = candidate;
                        item.title = candidate.host.length > 0 ? candidate.host : @"RSS";
                        item.mimeType = mime;
                        [found addObject:item];
                    });
                }
                dispatch_group_leave(group);
            };

            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSHTTPURLResponse *)response
                : nil;
            NSInteger status = http.statusCode;
            NSString *mime = response.MIMEType;

            if (!error && status >= 200 && status < 400 &&
                [BrowserFeedReader isFeedMIMEType:mime URL:candidate]) {
                finishOne(YES, mime);
                return;
            }

            // HEAD 无 Content-Type / 405 / 路径像 Feed：拉前缀嗅探。
            BOOL shouldSniff = (!error && status >= 200 && status < 400) || status == 405 || status == 501;
            if (!shouldSniff) {
                finishOne(NO, nil);
                return;
            }

            NSMutableURLRequest *getReq = [NSMutableURLRequest requestWithURL:candidate];
            getReq.HTTPMethod = @"GET";
            getReq.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
            [getReq setValue:@"bytes=0-1023" forHTTPHeaderField:@"Range"];
            [[session dataTaskWithRequest:getReq
                        completionHandler:^(NSData *data, NSURLResponse *getResponse, NSError *getError) {
                NSString *getMime = getResponse.MIMEType ?: mime;
                NSHTTPURLResponse *getHTTP = [getResponse isKindOfClass:[NSHTTPURLResponse class]]
                    ? (NSHTTPURLResponse *)getResponse
                    : nil;
                NSInteger getStatus = getHTTP.statusCode;
                BOOL ok = NO;
                if (!getError && getStatus >= 200 && getStatus < 400) {
                    if ([BrowserFeedReader isFeedMIMEType:getMime URL:candidate] ||
                        [self bodySniffLooksLikeFeed:data]) {
                        ok = YES;
                    }
                }
                finishOne(ok, getMime);
            }] resume];
        }];
        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSArray<BrowserFeedItem *> *snapshot = @[];
        dispatch_sync(lockQueue, ^{
            snapshot = [found copy];
        });
        [session finishTasksAndInvalidate];
        // 保持候选顺序
        NSMutableArray<BrowserFeedItem *> *ordered = [NSMutableArray array];
        NSMutableSet<NSString *> *orderedSeen = [NSMutableSet set];
        for (NSURL *url in candidates) {
            for (BrowserFeedItem *item in snapshot) {
                if ([item.url.absoluteString isEqualToString:url.absoluteString] &&
                    ![orderedSeen containsObject:item.url.absoluteString]) {
                    [orderedSeen addObject:item.url.absoluteString];
                    // 用路径后缀作标题，便于菜单区分多个 Feed
                    if (item.title.length == 0 || [item.title isEqualToString:item.url.host]) {
                        NSString *path = item.url.path ?: @"/feed";
                        item.title = [NSString stringWithFormat:@"%@%@", item.url.host ?: @"", path];
                    }
                    [ordered addObject:item];
                    break;
                }
            }
        }
        NSArray<BrowserFeedItem *> *result = [ordered copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(result);
        });
    });

    // 调用方用 navigation generation 丢弃过期结果。
    return nil;
}

@end
