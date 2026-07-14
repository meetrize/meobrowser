#import "BrowserFaviconHTMLParser.h"

static const NSUInteger kMaxHTMLBytes = 64 * 1024;

@interface BrowserFaviconHTMLCandidate : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSInteger score;
@end

@implementation BrowserFaviconHTMLCandidate
@end

@implementation BrowserFaviconHTMLParser

+ (NSArray<NSURL *> *)iconURLsFromHTMLData:(NSData *)data pageURL:(NSURL *)pageURL {
    if (data.length == 0 || pageURL == nil) {
        return @[];
    }

    NSData *slice = data;
    if (data.length > kMaxHTMLBytes) {
        slice = [data subdataWithRange:NSMakeRange(0, kMaxHTMLBytes)];
    }

    NSString *html = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
    if (html == nil) {
        html = [[NSString alloc] initWithData:slice encoding:NSISOLatin1StringEncoding];
    }
    if (html.length == 0) {
        return @[];
    }

    NSError *error = nil;
    NSRegularExpression *linkRegex =
        [NSRegularExpression regularExpressionWithPattern:@"<link\\b[^>]*>"
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:&error];
    if (linkRegex == nil) {
        return @[];
    }

    NSMutableArray<BrowserFaviconHTMLCandidate *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSTextCheckingResult *> *matches =
        [linkRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in matches) {
        NSString *tag = [html substringWithRange:match.range];
        NSString *rel = [self attributeValueNamed:@"rel" inTag:tag];
        NSString *href = [self attributeValueNamed:@"href" inTag:tag];
        if (rel.length == 0 || href.length == 0) {
            continue;
        }
        if (![self relLooksLikeIcon:rel]) {
            continue;
        }
        if ([href.lowercaseString hasPrefix:@"data:"]) {
            continue;
        }

        NSURL *absolute = [NSURL URLWithString:href relativeToURL:pageURL].absoluteURL;
        if (absolute == nil || absolute.absoluteString.length == 0) {
            continue;
        }
        NSString *key = absolute.absoluteString;
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];

        NSString *sizes = [self attributeValueNamed:@"sizes" inTag:tag];
        NSString *type = [self attributeValueNamed:@"type" inTag:tag];
        BrowserFaviconHTMLCandidate *candidate = [[BrowserFaviconHTMLCandidate alloc] init];
        candidate.url = absolute;
        candidate.score = [self scoreForRel:rel
                                      sizes:sizes
                                       type:type
                                       href:absolute.absoluteString];
        [candidates addObject:candidate];
    }

    [candidates sortUsingComparator:^NSComparisonResult(BrowserFaviconHTMLCandidate *a, BrowserFaviconHTMLCandidate *b) {
        if (a.score > b.score) {
            return NSOrderedAscending;
        }
        if (a.score < b.score) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    NSMutableArray<NSURL *> *results = [NSMutableArray arrayWithCapacity:candidates.count];
    for (BrowserFaviconHTMLCandidate *candidate in candidates) {
        [results addObject:candidate.url];
    }
    return [results copy];
}

+ (NSInteger)scoreForRel:(NSString *)rel
                   sizes:(nullable NSString *)sizes
                    type:(nullable NSString *)type
                    href:(NSString *)href {
    NSInteger score = 0;
    NSString *relLower = rel.lowercaseString;
    NSString *hrefLower = href.lowercaseString;
    NSString *typeLower = type.lowercaseString ?: @"";

    if ([relLower containsString:@"apple-touch-icon"]) {
        score += 200;
    } else if ([relLower containsString:@"icon"]) {
        score += 40;
    }

    NSInteger maxSize = [self maxSizeFromSizesAttribute:sizes];
    if (maxSize > 0) {
        score += maxSize; // 180 / 192 / 512 直接拉开差距
    } else if ([hrefLower containsString:@"180"] || [hrefLower containsString:@"192"]) {
        score += 180;
    } else if ([hrefLower containsString:@"128"] || [hrefLower containsString:@"144"]) {
        score += 128;
    } else if ([hrefLower containsString:@"96"] || [hrefLower containsString:@"64"]) {
        score += 64;
    } else if ([hrefLower containsString:@"32"]) {
        score += 32;
    } else if ([hrefLower containsString:@"16"]) {
        score += 8;
    }

    if ([hrefLower hasSuffix:@".png"] || [typeLower containsString:@"png"]) {
        score += 30;
    } else if ([hrefLower hasSuffix:@".webp"] || [typeLower containsString:@"webp"]) {
        score += 25;
    } else if ([hrefLower hasSuffix:@".jpg"] || [hrefLower hasSuffix:@".jpeg"]) {
        score += 15;
    } else if ([hrefLower hasSuffix:@".ico"] || [typeLower containsString:@"icon"]) {
        score += 5; // 常含小尺寸
    } else if ([hrefLower hasSuffix:@".svg"] || [typeLower containsString:@"svg"]) {
        score += 10; // 首版可能解码失败，略减分
    }

    return score;
}

+ (NSInteger)maxSizeFromSizesAttribute:(nullable NSString *)sizes {
    if (sizes.length == 0) {
        return 0;
    }
    NSString *lower = sizes.lowercaseString;
    if ([lower isEqualToString:@"any"]) {
        return 256;
    }
    NSInteger best = 0;
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s*[x×]\\s*(\\d+)"
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:nil];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:lower options:0 range:NSMakeRange(0, lower.length)];
    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges < 3) {
            continue;
        }
        NSInteger w = [[lower substringWithRange:[match rangeAtIndex:1]] integerValue];
        NSInteger h = [[lower substringWithRange:[match rangeAtIndex:2]] integerValue];
        best = MAX(best, MAX(w, h));
    }
    return best;
}

+ (BOOL)relLooksLikeIcon:(NSString *)rel {
    NSArray<NSString *> *tokens =
        [[rel lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSString *token in tokens) {
        if (token.length > 0) {
            [set addObject:token];
        }
    }
    if ([set containsObject:@"icon"]) {
        return YES;
    }
    for (NSString *token in set) {
        if ([token hasPrefix:@"apple-touch-icon"]) {
            return YES;
        }
    }
    return NO;
}

+ (nullable NSString *)attributeValueNamed:(NSString *)name inTag:(NSString *)tag {
    if (name.length == 0 || tag.length == 0) {
        return nil;
    }
    NSString *pattern =
        [NSString stringWithFormat:@"%@\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
                                   [NSRegularExpression escapedPatternForString:name]];
    NSError *error = nil;
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:&error];
    if (regex == nil) {
        return nil;
    }
    NSTextCheckingResult *match = [regex firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    if (match == nil) {
        return nil;
    }
    for (NSUInteger i = 1; i < match.numberOfRanges; i++) {
        NSRange range = [match rangeAtIndex:i];
        if (range.location != NSNotFound && range.length > 0) {
            return [[tag substringWithRange:range] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return nil;
}

@end
