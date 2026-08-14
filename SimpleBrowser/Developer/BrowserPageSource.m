#import "BrowserPageSource.h"

@implementation BrowserPageSource

+ (NSUInteger)maxSourceLength {
    return 5 * 1024 * 1024;
}

+ (NSString *)escapedHTMLFromString:(NSString *)string {
    if (string.length == 0) {
        return @"";
    }
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
    return [escaped copy];
}

+ (NSString *)HTMLDocumentForSource:(NSString *)source
                          pageTitle:(NSString *)pageTitle
                          truncated:(BOOL)truncated {
    NSString *trimmedTitle = [pageTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedTitle.length == 0) {
        trimmedTitle = @"页面";
    }
    NSString *docTitle = [NSString stringWithFormat:@"源代码 — %@", trimmedTitle];
    NSString *note = truncated
        ? @"当前为 DOM 快照（已截断），可能与原始 HTTP 响应不同。"
        : @"当前为 DOM 快照，可能与原始 HTTP 响应不同。";

    return [NSString stringWithFormat:
            @"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
            @"<title>%@</title>"
            @"<style>"
            @"html,body{margin:0;padding:0;background:#f6f6f6;color:#111;}"
            @"@media (prefers-color-scheme:dark){html,body{background:#1e1e1e;color:#ddd;}"
            @".note{background:#2a2a2a;border-bottom-color:#444;color:#bbb;}"
            @"pre{background:#1e1e1e;}}"
            @".note{font:12px -apple-system,BlinkMacSystemFont,sans-serif;"
            @"padding:8px 12px;background:#efefef;border-bottom:1px solid #ddd;color:#555;}"
            @"pre{margin:0;padding:12px;font:12px/1.45 ui-monospace,Menlo,Monaco,monospace;"
            @"white-space:pre-wrap;word-break:break-word;}"
            @"</style></head><body>"
            @"<div class=\"note\">%@</div>"
            @"<pre>%@</pre>"
            @"</body></html>",
            [self escapedHTMLFromString:docTitle],
            [self escapedHTMLFromString:note],
            [self escapedHTMLFromString:source ?: @""]];
}

@end
