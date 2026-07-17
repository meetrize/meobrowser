#import "BrowserFeedReader.h"

NSString * const BrowserFeedURLScheme = @"meo-feed";

static NSString * const BrowserFeedReaderErrorDomain = @"BrowserFeedReader";

@implementation BrowserFeedReader

+ (BOOL)shouldHandleNavigationResponse:(WKNavigationResponse *)navigationResponse {
    if (!navigationResponse || !navigationResponse.forMainFrame) {
        return NO;
    }
    NSURLResponse *response = navigationResponse.response;
    // 已在内部阅读 scheme 上，避免循环拦截。
    if ([self isFeedReaderURL:response.URL]) {
        return NO;
    }
    return [self isFeedMIMEType:response.MIMEType URL:response.URL];
}

+ (BOOL)isFeedMIMEType:(NSString *)mimeType URL:(NSURL *)url {
    NSString *mime = mimeType.lowercaseString ?: @"";
    if ([mime hasPrefix:@"application/rss+xml"] ||
        [mime hasPrefix:@"application/atom+xml"] ||
        [mime hasPrefix:@"application/feed+json"] ||
        [mime hasPrefix:@"application/rdf+xml"]) {
        return YES;
    }

    NSString *path = url.path.lowercaseString ?: @"";
    BOOL pathLooksLikeFeed =
        [path hasSuffix:@"/feed"] ||
        [path hasSuffix:@"/feed/"] ||
        [path hasSuffix:@"/rss"] ||
        [path hasSuffix:@"/rss/"] ||
        [path hasSuffix:@"/atom"] ||
        [path hasSuffix:@"/atom/"] ||
        [path hasSuffix:@".rss"] ||
        [path hasSuffix:@".atom"] ||
        [path containsString:@"/feed."] ||
        [path containsString:@"/rss."] ||
        [path containsString:@"/atom."];

    if (pathLooksLikeFeed) {
        if ([mime hasPrefix:@"application/xml"] ||
            [mime hasPrefix:@"text/xml"] ||
            [mime hasPrefix:@"text/plain"] ||
            mime.length == 0) {
            return YES;
        }
    }
    return NO;
}

+ (NSURL *)readerURLForFeedURL:(NSURL *)feedURL {
    NSParameterAssert(feedURL.absoluteString.length > 0);
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = BrowserFeedURLScheme;
    components.host = @"reader";
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"u" value:feedURL.absoluteString]
    ];
    return components.URL;
}

+ (NSURL *)feedURLFromReaderURL:(NSURL *)readerURL {
    if (![self isFeedReaderURL:readerURL]) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:readerURL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"u"] && item.value.length > 0) {
            return [NSURL URLWithString:item.value];
        }
    }
    return nil;
}

+ (NSURL *)publicURLForInternalURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    return [self feedURLFromReaderURL:url] ?: url;
}

+ (BOOL)isFeedReaderURL:(NSURL *)url {
    return [url.scheme.lowercaseString isEqualToString:BrowserFeedURLScheme];
}

+ (void)loadReadableHTMLForFeedURL:(NSURL *)feedURL
                 completionHandler:(void (^)(NSString * _Nullable html, NSError * _Nullable error))completionHandler {
    if (!feedURL || !completionHandler) {
        return;
    }

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithURL:feedURL
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(nil, error);
            });
            return;
        }
        if (data.length == 0) {
            NSError *empty = [NSError errorWithDomain:BrowserFeedReaderErrorDomain
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Feed 内容为空"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(nil, empty);
            });
            return;
        }

        NSError *parseError = nil;
        NSString *html = [self readableHTMLFromFeedData:data feedURL:feedURL error:&parseError];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(html, parseError);
        });
    }];
    [task resume];
}

#pragma mark - Parse

+ (NSString *)readableHTMLFromFeedData:(NSData *)data
                               feedURL:(NSURL *)feedURL
                                 error:(NSError **)error {
    NSError *xmlError = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:&xmlError];
    if (!doc || !doc.rootElement) {
        // 非严格 XML 时尝试兜底：当作纯文本展示前几 KB
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!raw) {
            raw = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        if (raw.length == 0) {
            if (error) {
                *error = xmlError ?: [NSError errorWithDomain:BrowserFeedReaderErrorDomain
                                                         code:2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"无法解析 Feed"}];
            }
            return nil;
        }
        return [self wrapPlainTextHTML:raw feedURL:feedURL title:@"Feed"];
    }

    NSString *rootName = doc.rootElement.localName.lowercaseString;
    if ([rootName isEqualToString:@"rss"] || [rootName isEqualToString:@"rdf"]) {
        return [self htmlForRSSDocument:doc feedURL:feedURL];
    }
    if ([rootName isEqualToString:@"feed"]) {
        return [self htmlForAtomDocument:doc feedURL:feedURL];
    }

    // 根不是标准 feed：若 MIME 路径像 feed，仍展示原文
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return [self wrapPlainTextHTML:raw feedURL:feedURL title:doc.rootElement.name ?: @"XML"];
}

+ (NSString *)stringValueOfFirstNodeMatchingXPath:(NSString *)xpath inNode:(NSXMLNode *)node {
    NSError *err = nil;
    NSArray *nodes = [node nodesForXPath:xpath error:&err];
    if (nodes.count == 0) {
        return @"";
    }
    NSString *value = [nodes.firstObject stringValue] ?: @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)htmlEscaped:(NSString *)text {
    if (text.length == 0) {
        return @"";
    }
    NSMutableString *s = [text mutableCopy];
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

+ (NSString *)plainTextFromHTMLFragment:(NSString *)fragment {
    if (fragment.length == 0) {
        return @"";
    }
    // 轻量去标签，避免把 content:encoded 整段 HTML 塞进列表。
    NSMutableString *s = [fragment mutableCopy];
    NSRegularExpression *tag = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                                         options:0
                                                                           error:nil];
    [tag replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    [s replaceOccurrencesOfString:@"&nbsp;" withString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&lt;" withString:@"<" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&gt;" withString:@">" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    NSRegularExpression *ws = [NSRegularExpression regularExpressionWithPattern:@"[ \\t\\r\\n]+"
                                                                        options:0
                                                                          error:nil];
    NSString *collapsed = [ws stringByReplacingMatchesInString:s
                                                       options:0
                                                         range:NSMakeRange(0, s.length)
                                                  withTemplate:@" "];
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)htmlForRSSDocument:(NSXMLDocument *)doc feedURL:(NSURL *)feedURL {
    NSXMLElement *root = doc.rootElement;
    NSXMLNode *channel = nil;
    NSError *err = nil;
    NSArray *channels = [root nodesForXPath:@"./*[local-name()='channel']" error:&err];
    channel = channels.firstObject ?: root;

    NSString *title = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='title'][1]" inNode:channel];
    NSString *link = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='link'][1]" inNode:channel];
    NSString *desc = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='description'][1]" inNode:channel];
    if (title.length == 0) {
        title = feedURL.host.length > 0 ? feedURL.host : @"RSS Feed";
    }

    NSArray *items = [channel nodesForXPath:@"./*[local-name()='item']" error:&err];
    NSMutableString *body = [NSMutableString string];
    NSUInteger index = 0;
    for (NSXMLNode *item in items) {
        index += 1;
        NSString *itemTitle = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='title'][1]" inNode:item];
        NSString *itemLink = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='link'][1]" inNode:item];
        NSString *itemDate = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='pubDate'][1]" inNode:item];
        NSString *itemDesc = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='description'][1]" inNode:item];
        if (itemDesc.length == 0) {
            itemDesc = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='encoded'][1]" inNode:item];
        }
        itemDesc = [self plainTextFromHTMLFragment:itemDesc];
        if (itemDesc.length > 400) {
            itemDesc = [[itemDesc substringToIndex:400] stringByAppendingString:@"…"];
        }
        if (itemTitle.length == 0) {
            itemTitle = itemLink.length > 0 ? itemLink : [NSString stringWithFormat:@"条目 %lu", (unsigned long)index];
        }

        [body appendString:@"<article class=\"item\">"];
        if (itemLink.length > 0) {
            [body appendFormat:@"<h2><a href=\"%@\">%@</a></h2>",
             [self htmlEscaped:itemLink], [self htmlEscaped:itemTitle]];
        } else {
            [body appendFormat:@"<h2>%@</h2>", [self htmlEscaped:itemTitle]];
        }
        if (itemDate.length > 0) {
            [body appendFormat:@"<div class=\"meta\">%@</div>", [self htmlEscaped:itemDate]];
        }
        if (itemDesc.length > 0) {
            [body appendFormat:@"<p>%@</p>", [self htmlEscaped:itemDesc]];
        }
        [body appendString:@"</article>"];
    }

    if (body.length == 0) {
        [body appendString:@"<p class=\"empty\">此 Feed 暂无条目。</p>"];
    }

    return [self wrapReaderHTMLWithTitle:title
                                    link:link
                             description:desc
                                    body:body
                                 feedURL:feedURL
                              formatName:@"RSS"];
}

+ (NSString *)htmlForAtomDocument:(NSXMLDocument *)doc feedURL:(NSURL *)feedURL {
    NSXMLElement *root = doc.rootElement;
    NSString *title = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='title'][1]" inNode:root];
    NSString *subtitle = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='subtitle'][1]" inNode:root];
    NSString *link = @"";
    NSError *err = nil;
    NSArray *links = [root nodesForXPath:@"./*[local-name()='link']" error:&err];
    for (NSXMLNode *linkNode in links) {
        if (![linkNode isKindOfClass:[NSXMLElement class]]) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)linkNode;
        NSString *rel = [[el attributeForName:@"rel"].stringValue lowercaseString] ?: @"alternate";
        NSString *href = [el attributeForName:@"href"].stringValue;
        if (href.length == 0) {
            continue;
        }
        if ([rel isEqualToString:@"alternate"] || rel.length == 0) {
            link = href;
            break;
        }
    }
    if (title.length == 0) {
        title = feedURL.host.length > 0 ? feedURL.host : @"Atom Feed";
    }

    NSArray *entries = [root nodesForXPath:@"./*[local-name()='entry']" error:&err];
    NSMutableString *body = [NSMutableString string];
    NSUInteger index = 0;
    for (NSXMLNode *entry in entries) {
        index += 1;
        NSString *itemTitle = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='title'][1]" inNode:entry];
        NSString *itemDate = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='updated'][1]" inNode:entry];
        if (itemDate.length == 0) {
            itemDate = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='published'][1]" inNode:entry];
        }
        NSString *itemLink = @"";
        NSArray *entryLinks = [entry nodesForXPath:@"./*[local-name()='link']" error:nil];
        for (NSXMLNode *linkNode in entryLinks) {
            if (![linkNode isKindOfClass:[NSXMLElement class]]) {
                continue;
            }
            NSXMLElement *el = (NSXMLElement *)linkNode;
            NSString *rel = [[el attributeForName:@"rel"].stringValue lowercaseString] ?: @"alternate";
            NSString *href = [el attributeForName:@"href"].stringValue;
            if (href.length == 0) {
                continue;
            }
            if ([rel isEqualToString:@"alternate"] || rel.length == 0) {
                itemLink = href;
                break;
            }
            if (itemLink.length == 0) {
                itemLink = href;
            }
        }
        NSString *itemDesc = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='summary'][1]" inNode:entry];
        if (itemDesc.length == 0) {
            itemDesc = [self stringValueOfFirstNodeMatchingXPath:@"./*[local-name()='content'][1]" inNode:entry];
        }
        itemDesc = [self plainTextFromHTMLFragment:itemDesc];
        if (itemDesc.length > 400) {
            itemDesc = [[itemDesc substringToIndex:400] stringByAppendingString:@"…"];
        }
        if (itemTitle.length == 0) {
            itemTitle = itemLink.length > 0 ? itemLink : [NSString stringWithFormat:@"条目 %lu", (unsigned long)index];
        }

        [body appendString:@"<article class=\"item\">"];
        if (itemLink.length > 0) {
            [body appendFormat:@"<h2><a href=\"%@\">%@</a></h2>",
             [self htmlEscaped:itemLink], [self htmlEscaped:itemTitle]];
        } else {
            [body appendFormat:@"<h2>%@</h2>", [self htmlEscaped:itemTitle]];
        }
        if (itemDate.length > 0) {
            [body appendFormat:@"<div class=\"meta\">%@</div>", [self htmlEscaped:itemDate]];
        }
        if (itemDesc.length > 0) {
            [body appendFormat:@"<p>%@</p>", [self htmlEscaped:itemDesc]];
        }
        [body appendString:@"</article>"];
    }

    if (body.length == 0) {
        [body appendString:@"<p class=\"empty\">此 Feed 暂无条目。</p>"];
    }

    return [self wrapReaderHTMLWithTitle:title
                                    link:link
                             description:subtitle
                                    body:body
                                 feedURL:feedURL
                              formatName:@"Atom"];
}

+ (NSString *)wrapReaderHTMLWithTitle:(NSString *)title
                                 link:(NSString *)link
                          description:(NSString *)description
                                 body:(NSString *)body
                              feedURL:(NSURL *)feedURL
                           formatName:(NSString *)formatName {
    NSMutableString *header = [NSMutableString string];
    [header appendFormat:@"<p class=\"badge\">%@ · 文本视图</p>", [self htmlEscaped:formatName]];
    [header appendFormat:@"<h1>%@</h1>", [self htmlEscaped:title]];
    if (description.length > 0) {
        [header appendFormat:@"<p class=\"desc\">%@</p>", [self htmlEscaped:[self plainTextFromHTMLFragment:description]]];
    }
    [header appendFormat:@"<p class=\"source\">Feed：<a href=\"%@\">%@</a>",
     [self htmlEscaped:feedURL.absoluteString], [self htmlEscaped:feedURL.absoluteString]];
    if (link.length > 0) {
        [header appendFormat:@" · 站点：<a href=\"%@\">%@</a>", [self htmlEscaped:link], [self htmlEscaped:link]];
    }
    [header appendString:@"</p>"];

    return [NSString stringWithFormat:
            @"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
            @"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            @"<title>%@</title>"
            @"<style>"
            @"html,body{margin:0;padding:0;background:#f7f5f0;color:#1c1917;}"
            @"body{font:15px/1.55 -apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif;}"
            @".wrap{max-width:720px;margin:0 auto;padding:28px 20px 64px;}"
            @"h1{font-size:28px;line-height:1.25;font-weight:700;margin:8px 0 12px;}"
            @"h2{font-size:17px;line-height:1.35;margin:0 0 6px;font-weight:600;}"
            @"a{color:#0f3d68;text-decoration:underline;text-underline-offset:2px;}"
            @".badge{display:inline-block;margin:0;font-size:12px;letter-spacing:0.04em;"
            @"text-transform:uppercase;color:#78716c;}"
            @".desc{color:#44403c;margin:0 0 10px;}"
            @".source{font-size:12px;color:#78716c;margin:0 0 28px;word-break:break-all;}"
            @".item{padding:16px 0;border-top:1px solid #e7e5e4;}"
            @".item:first-of-type{border-top:0;}"
            @".meta{font-size:12px;color:#78716c;margin:0 0 8px;}"
            @".item p{margin:0;color:#292524;}"
            @".empty{color:#78716c;}"
            @"</style></head><body><div class=\"wrap\">%@%@</div></body></html>",
            [self htmlEscaped:title], header, body];
}

+ (NSString *)wrapPlainTextHTML:(NSString *)raw feedURL:(NSURL *)feedURL title:(NSString *)title {
    NSString *clipped = raw;
    if (clipped.length > 200000) {
        clipped = [[clipped substringToIndex:200000] stringByAppendingString:@"\n…"];
    }
    NSString *body = [NSString stringWithFormat:@"<pre class=\"raw\">%@</pre>", [self htmlEscaped:clipped]];
    return [self wrapReaderHTMLWithTitle:title
                                    link:@""
                             description:@"无法按 RSS/Atom 结构化解析，已显示原始文本。"
                                    body:body
                                 feedURL:feedURL
                              formatName:@"XML"];
}

@end
