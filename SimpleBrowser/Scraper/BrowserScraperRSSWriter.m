#import "BrowserScraperRSSWriter.h"
#import "BrowserScraperModels.h"

@implementation BrowserScraperRSSWriter

static NSString *MeoRSSEscape(NSString *raw) {
    if (raw.length == 0) {
        return @"";
    }
    NSMutableString *s = [raw mutableCopy];
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"'" withString:@"&apos;" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

static NSString *MeoRSSStringify(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

static NSString *MeoRSSNormalizedKey(NSString *key) {
    return [[key ?: @"" lowercaseString]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL MeoRSSKeyMatches(NSString *key, NSArray<NSString *> *candidates) {
    NSString *nk = MeoRSSNormalizedKey(key);
    if (nk.length == 0) {
        return NO;
    }
    for (NSString *c in candidates) {
        NSString *nc = MeoRSSNormalizedKey(c);
        if ([nk isEqualToString:nc] || [nk containsString:nc] || [nc containsString:nk]) {
            return YES;
        }
    }
    return NO;
}

static NSString *MeoRSSPick(NSDictionary *row, NSArray<NSString *> *candidates) {
    for (NSString *key in row) {
        if (MeoRSSKeyMatches(key, candidates)) {
            NSString *v = [MeoRSSStringify(row[key])
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (v.length > 0) {
                return v;
            }
        }
    }
    return @"";
}

static NSString *MeoRSSHashFragment(NSString *seed) {
    NSUInteger hash = seed.hash;
    return [NSString stringWithFormat:@"%08lx", (unsigned long)(hash & 0xffffffff)];
}

static NSString *MeoRSSRFC822Date(NSString *raw) {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @"";
    }
    static NSDateFormatter *isoFrac;
    static NSDateFormatter *isoBasic;
    static NSDateFormatter *rfc822;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        isoFrac = [[NSDateFormatter alloc] init];
        isoFrac.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        isoFrac.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        isoBasic = [[NSDateFormatter alloc] init];
        isoBasic.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        isoBasic.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        rfc822 = [[NSDateFormatter alloc] init];
        rfc822.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        rfc822.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        rfc822.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss '+0000'";
    });
    NSDate *date = [isoFrac dateFromString:trimmed];
    if (!date) {
        date = [isoBasic dateFromString:trimmed];
    }
    if (!date && trimmed.length >= 10) {
        NSDateFormatter *day = [[NSDateFormatter alloc] init];
        day.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        day.dateFormat = @"yyyy-MM-dd";
        date = [day dateFromString:[trimmed substringToIndex:10]];
    }
    if (!date) {
        // 无法解析时原样放入 description；pubDate 省略
        return @"";
    }
    return [rfc822 stringFromDate:date];
}

+ (NSData *)RSS2DataFromRows:(NSArray<NSDictionary *> *)rows
                      recipe:(BrowserScraperRecipe *)recipe {
    NSString *channelTitle = recipe.name.length ? recipe.name : @"MeoBrowser Scraper";
    NSString *channelLink = recipe.startURL.length ? recipe.startURL : @"http://127.0.0.1/";
    NSString *channelDesc = [NSString stringWithFormat:@"MeoBrowser 页面爬虫实时订阅：%@", channelTitle];

    NSMutableString *xml = [NSMutableString string];
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendString:@"<rss version=\"2.0\">\n"];
    [xml appendString:@"  <channel>\n"];
    [xml appendFormat:@"    <title>%@</title>\n", MeoRSSEscape(channelTitle)];
    [xml appendFormat:@"    <link>%@</link>\n", MeoRSSEscape(channelLink)];
    [xml appendFormat:@"    <description>%@</description>\n", MeoRSSEscape(channelDesc)];
    [xml appendString:@"    <generator>MeoBrowser Page Scraper</generator>\n"];

    static NSArray<NSString *> *titleKeys;
    static NSArray<NSString *> *linkKeys;
    static NSArray<NSString *> *descKeys;
    static NSArray<NSString *> *dateKeys;
    static dispatch_once_t onceKeys;
    dispatch_once(&onceKeys, ^{
        titleKeys = @[ @"标题", @"title", @"name", @"名称" ];
        linkKeys = @[ @"链接", @"url", @"href", @"link", @"地址" ];
        descKeys = @[ @"摘要", @"description", @"正文", @"内容", @"summary", @"desc" ];
        dateKeys = @[ @"时间", @"date", @"pubdate", @"published", @"发布时间", @"更新时间" ];
    });

    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *title = MeoRSSPick(row, titleKeys);
        if (title.length == 0) {
            title = @"无标题";
        }
        NSString *link = MeoRSSPick(row, linkKeys);
        if (link.length == 0) {
            link = [NSString stringWithFormat:@"%@#%@", channelLink, MeoRSSHashFragment(title)];
        }
        NSString *desc = MeoRSSPick(row, descKeys);
        NSString *dateRaw = MeoRSSPick(row, dateKeys);
        NSString *pubDate = MeoRSSRFC822Date(dateRaw);

        [xml appendString:@"    <item>\n"];
        [xml appendFormat:@"      <title>%@</title>\n", MeoRSSEscape(title)];
        [xml appendFormat:@"      <link>%@</link>\n", MeoRSSEscape(link)];
        [xml appendFormat:@"      <guid isPermaLink=\"%@\">%@</guid>\n",
         [link hasPrefix:@"http"] ? @"true" : @"false",
         MeoRSSEscape(link)];
        if (desc.length > 0) {
            [xml appendFormat:@"      <description>%@</description>\n", MeoRSSEscape(desc)];
        } else if (dateRaw.length > 0 && pubDate.length == 0) {
            [xml appendFormat:@"      <description>%@</description>\n", MeoRSSEscape(dateRaw)];
        }
        if (pubDate.length > 0) {
            [xml appendFormat:@"      <pubDate>%@</pubDate>\n", MeoRSSEscape(pubDate)];
        }
        [xml appendString:@"    </item>\n"];
    }

    [xml appendString:@"  </channel>\n"];
    [xml appendString:@"</rss>\n"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

@end
