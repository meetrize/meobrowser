#import "AIPageContextScraperBridge.h"
#import "AIPageContextBundle.h"
#import "BrowserScraperModels.h"

@implementation AIPageContextScraperBridge

+ (BrowserScraperField *)fieldNamed:(NSString *)name
                               kind:(BrowserScraperFieldKind)kind
                               path:(NSString *)path
                          attribute:(NSString *)attribute {
    NSMutableDictionary *d = [@{
        @"id": [[NSUUID UUID] UUIDString],
        @"enabled": @YES,
        @"name": name ?: @"字段",
        @"kind": [BrowserScraperField stringFromKind:kind],
        @"path": path ?: @"",
    } mutableCopy];
    if (attribute.length) d[@"attribute"] = attribute;
    BrowserScraperField *f = [BrowserScraperField fieldWithDictionary:d];
    return f;
}

+ (BrowserScraperRecipe *)draftRecipeFromBundle:(AIPageContextBundle *)bundle
                                     pickResult:(NSDictionary *)pickResult {
    NSString *pageTitle = bundle.title.length ? bundle.title : @"AI 导入";
    BrowserScraperRecipe *r = [BrowserScraperRecipe blankRecipeNamed:
                               [NSString stringWithFormat:@"AI · %@", pageTitle]];
    r.startURL = bundle.urlString;
    NSURL *url = [NSURL URLWithString:bundle.urlString ?: @""];
    if (url.host.length) {
        r.match.hosts = @[ url.host.lowercaseString ];
    }

    NSArray *suggested = [pickResult[@"suggestedFields"] isKindOfClass:[NSArray class]]
        ? pickResult[@"suggestedFields"] : nil;
    NSString *container = nil;
    NSString *rowPath = nil;

    if ([pickResult[@"cssPath"] isKindOfClass:[NSString class]] &&
        [pickResult[@"cssPath"] length] > 0) {
        container = pickResult[@"cssPath"];
    }
    if ([pickResult[@"rowPath"] isKindOfClass:[NSString class]] &&
        [pickResult[@"rowPath"] length] > 0) {
        rowPath = pickResult[@"rowPath"];
    }
    if ([pickResult[@"absolutePath"] isKindOfClass:[NSString class]] && !container.length) {
        container = pickResult[@"absolutePath"];
    }

    NSMutableArray<BrowserScraperField *> *fields = [NSMutableArray array];
    if (suggested.count > 0) {
        r.mode = BrowserScraperModeTable;
        r.containerPath = container ?: @"";
        r.rowPath = rowPath.length ? rowPath : @"tr";
        NSInteger i = 0;
        for (id item in suggested) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *fd = (NSDictionary *)item;
            NSString *name = [fd[@"name"] isKindOfClass:[NSString class]] ? fd[@"name"] : [NSString stringWithFormat:@"列%ld", (long)(i + 1)];
            NSString *kindStr = [fd[@"kind"] isKindOfClass:[NSString class]] ? fd[@"kind"] : @"text";
            NSString *path = [fd[@"path"] isKindOfClass:[NSString class]] ? fd[@"path"] : @"";
            NSString *attr = [fd[@"attribute"] isKindOfClass:[NSString class]] ? fd[@"attribute"] : nil;
            BrowserScraperFieldKind kind = [BrowserScraperField kindFromString:kindStr];
            [fields addObject:[self fieldNamed:name kind:kind path:path attribute:attr]];
            i += 1;
            if (i >= 12) break;
        }
    } else if (container.length) {
        // 点选了容器但无建议字段：标量取容器文本
        r.mode = BrowserScraperModeScalar;
        r.containerPath = container;
        r.rowPath = @"";
        [fields addObject:[self fieldNamed:@"正文" kind:BrowserScraperFieldKindText path:@"" attribute:nil]];
        NSString *hint = pickResult[@"nameHint"];
        if ([hint isKindOfClass:[NSString class]] && hint.length) {
            fields.firstObject.name = hint;
        }
    } else {
        // 无点选：用 article/main 启发式
        r.mode = BrowserScraperModeScalar;
        r.containerPath = @"article, main, [role=main], body";
        r.rowPath = @"";
        [fields addObject:[self fieldNamed:@"正文" kind:BrowserScraperFieldKindText path:@"" attribute:nil]];
        [fields addObject:[self fieldNamed:@"标题" kind:BrowserScraperFieldKindText path:@"h1" attribute:nil]];
    }
    r.fields = fields;
    r.updatedAt = [NSDate date].timeIntervalSince1970;
    return r;
}

@end
