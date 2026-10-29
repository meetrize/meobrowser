#import "AIPageContextBundle.h"
#import "AIPageContextResource.h"

NSString * const AIPageContextLayerMeta = @"meta";
NSString * const AIPageContextLayerArticle = @"article";
NSString * const AIPageContextLayerOutline = @"outline";
NSString * const AIPageContextLayerHTML = @"html";
NSString * const AIPageContextLayerMarkdown = @"markdown";

@implementation AIPageContextBundle

+ (NSArray<NSString *> *)allLayerIds {
    return @[
        AIPageContextLayerMeta,
        AIPageContextLayerArticle,
        AIPageContextLayerOutline,
        AIPageContextLayerHTML,
        AIPageContextLayerMarkdown,
    ];
}

+ (nullable instancetype)bundleFromCaptureDictionary:(NSDictionary *)dict
                                               tabID:(NSUUID *)tabID {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id okVal = dict[@"ok"];
    if ([okVal respondsToSelector:@selector(boolValue)] && ![okVal boolValue]) {
        return nil;
    }

    AIPageContextBundle *b = [[AIPageContextBundle alloc] init];
    b.bundleId = [[NSUUID UUID] UUIDString];
    b.tabID = tabID;
    b.capturedAt = [NSDate date];
    b.stale = NO;
    b.resources = [NSMutableArray array];

    NSString *url = dict[@"url"];
    b.urlString = [url isKindOfClass:[NSString class]] ? url : nil;
    NSString *title = dict[@"title"];
    b.title = [title isKindOfClass:[NSString class]] ? title : nil;

    NSDictionary *meta = [dict[@"meta"] isKindOfClass:[NSDictionary class]] ? dict[@"meta"] : nil;
    if (meta) {
        NSString *desc = meta[@"description"];
        b.metaDescription = [desc isKindOfClass:[NSString class]] ? desc : nil;
        NSString *lang = meta[@"lang"];
        b.metaLanguage = [lang isKindOfClass:[NSString class]] ? lang : nil;
        NSString *canon = meta[@"canonical"];
        b.canonicalURL = [canon isKindOfClass:[NSString class]] ? canon : nil;
        if (!b.title.length) {
            NSString *mt = meta[@"title"];
            if ([mt isKindOfClass:[NSString class]]) b.title = mt;
        }
        if (!b.urlString.length) {
            NSString *mu = meta[@"url"];
            if ([mu isKindOfClass:[NSString class]]) b.urlString = mu;
        }
    }

    NSDictionary *article = [dict[@"article"] isKindOfClass:[NSDictionary class]] ? dict[@"article"] : nil;
    if (article) {
        NSString *text = article[@"text"];
        b.articleText = [text isKindOfClass:[NSString class]] ? text : nil;
        NSString *q = article[@"quality"];
        if ([q isKindOfClass:[NSString class]]) {
            if ([q isEqualToString:@"high"]) b.articleQuality = AIPageContextArticleQualityHigh;
            else if ([q isEqualToString:@"low"]) b.articleQuality = AIPageContextArticleQualityLow;
            else b.articleQuality = AIPageContextArticleQualityUnknown;
        }
        NSString *warn = article[@"warning"];
        b.articleWarning = [warn isKindOfClass:[NSString class]] ? warn : nil;
    }

    NSString *vis = dict[@"visibleText"];
    if ([vis isKindOfClass:[NSString class]]) {
        b.visibleText = vis;
    } else {
        NSDictionary *visDict = [dict[@"visible"] isKindOfClass:[NSDictionary class]] ? dict[@"visible"] : nil;
        NSString *vt = visDict[@"text"];
        if ([vt isKindOfClass:[NSString class]]) b.visibleText = vt;
    }

    NSDictionary *outline = [dict[@"outline"] isKindOfClass:[NSDictionary class]] ? dict[@"outline"] : nil;
    if (outline) {
        NSString *ot = outline[@"text"];
        b.outlineText = [ot isKindOfClass:[NSString class]] ? ot : nil;
    }

    NSDictionary *html = [dict[@"html"] isKindOfClass:[NSDictionary class]] ? dict[@"html"] : nil;
    if (html) {
        NSString *ht = html[@"text"];
        b.htmlText = [ht isKindOfClass:[NSString class]] ? ht : nil;
        id trunc = html[@"truncated"];
        if ([trunc respondsToSelector:@selector(boolValue)]) {
            b.htmlTruncated = [trunc boolValue];
        }
    }

    NSDictionary *md = [dict[@"markdown"] isKindOfClass:[NSDictionary class]] ? dict[@"markdown"] : nil;
    if (md) {
        NSString *mt = md[@"text"];
        b.markdownText = [mt isKindOfClass:[NSString class]] ? mt : nil;
    }

    NSArray *resArr = [dict[@"resources"] isKindOfClass:[NSArray class]] ? dict[@"resources"] : nil;
    for (id item in resArr) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        AIPageContextResource *r = [AIPageContextResource resourceFromDictionary:item];
        if (r) [b.resources addObject:r];
    }

    return b;
}

- (AIPageContextResource *)resourceWithId:(NSString *)resourceId {
    if (resourceId.length == 0) return nil;
    for (AIPageContextResource *r in self.resources) {
        if ([r.resourceId isEqualToString:resourceId]) return r;
    }
    return nil;
}

- (NSString *)effectiveArticleText {
    NSString *a = [self.articleText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (a.length > 0) return a;
    NSString *v = [self.visibleText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return v.length ? v : @"";
}

- (BOOL)hasUsableArticle {
    return [self effectiveArticleText].length > 0;
}

- (BOOL)hasContentForLayer:(NSString *)layerId {
    return [self textForLayer:layerId].length > 0;
}

- (NSString *)textForLayer:(NSString *)layerId {
    if ([layerId isEqualToString:AIPageContextLayerMeta]) {
        NSMutableString *body = [NSMutableString string];
        if (self.title.length) [body appendFormat:@"标题：%@\n", self.title];
        if (self.urlString.length) [body appendFormat:@"地址：%@\n", self.urlString];
        if (self.metaDescription.length) [body appendFormat:@"描述：%@\n", self.metaDescription];
        if (self.metaLanguage.length) [body appendFormat:@"语言：%@\n", self.metaLanguage];
        if (self.canonicalURL.length) [body appendFormat:@"Canonical：%@\n", self.canonicalURL];
        return body;
    }
    if ([layerId isEqualToString:AIPageContextLayerArticle]) {
        return [self effectiveArticleText];
    }
    if ([layerId isEqualToString:AIPageContextLayerOutline]) {
        return self.outlineText ?: @"";
    }
    if ([layerId isEqualToString:AIPageContextLayerHTML]) {
        return self.htmlText ?: @"";
    }
    if ([layerId isEqualToString:AIPageContextLayerMarkdown]) {
        return self.markdownText ?: @"";
    }
    return @"";
}

- (NSUInteger)charCountForLayer:(NSString *)layerId {
    return [self textForLayer:layerId].length;
}

- (NSString *)displayNameForLayer:(NSString *)layerId {
    if ([layerId isEqualToString:AIPageContextLayerMeta]) return @"页信息";
    if ([layerId isEqualToString:AIPageContextLayerArticle]) return @"正文";
    if ([layerId isEqualToString:AIPageContextLayerOutline]) return @"提纲";
    if ([layerId isEqualToString:AIPageContextLayerHTML]) return @"HTML";
    if ([layerId isEqualToString:AIPageContextLayerMarkdown]) return @"Markdown";
    return layerId ?: @"";
}

- (NSString *)ageDescription {
    NSTimeInterval sec = -[self.capturedAt timeIntervalSinceNow];
    if (sec < 45) return @"刚刚";
    if (sec < 3600) return [NSString stringWithFormat:@"%.0f 分钟前", floor(sec / 60.0)];
    if (sec < 86400) return [NSString stringWithFormat:@"%.0f 小时前", floor(sec / 3600.0)];
    return [NSString stringWithFormat:@"%.0f 天前", floor(sec / 86400.0)];
}

@end
