#import "BrowserScraperValueTransform.h"
#import "BrowserScraperModels.h"
#import <math.h>

@implementation BrowserScraperTransformContext
+ (instancetype)defaultContext {
    BrowserScraperTransformContext *ctx = [[self alloc] init];
    ctx.now = [NSDate date];
    ctx.onError = @"empty";
    return ctx;
}
@end

@implementation BrowserScraperValueTransform

+ (NSString *)stringify:(id)value {
    if (value == nil || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return [value description] ?: @"";
}

+ (BOOL)isEmpty:(NSString *)s {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

+ (NSString *)fail:(BrowserScraperTransformContext *)ctx raw:(NSString *)raw {
    if ([ctx.onError isEqualToString:@"raw"]) return raw ?: @"";
    return @"";
}

#pragma mark - Public

+ (NSString *)applyTransforms:(NSArray *)transforms
                     rawValue:(NSString *)rawValue
                          row:(NSDictionary *)rowSoFar
                      context:(BrowserScraperTransformContext *)context {
    BrowserScraperTransformContext *ctx = context ?: [BrowserScraperTransformContext defaultContext];
    NSString *raw = [self stringify:rawValue];
    if (![transforms isKindOfClass:[NSArray class]] || transforms.count == 0) {
        return raw;
    }
    id current = raw;
    for (id step in transforms) {
        if (![step isKindOfClass:[NSDictionary class]]) continue;
        current = [self evalNode:step input:current raw:raw row:rowSoFar context:ctx];
        if (current == nil) current = [self fail:ctx raw:raw];
    }
    return [self stringify:current];
}

+ (NSDictionary *)normalizeRow:(NSDictionary *)rawRow
                        fields:(NSArray *)fields
                       context:(BrowserScraperTransformContext *)context {
    if (![rawRow isKindOfClass:[NSDictionary class]]) return @{};
    BrowserScraperTransformContext *ctx = context ?: [BrowserScraperTransformContext defaultContext];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSArray *list = [fields isKindOfClass:[NSArray class]] ? fields : @[];
    for (id item in list) {
        BrowserScraperField *field = nil;
        if ([item isKindOfClass:[BrowserScraperField class]]) {
            field = (BrowserScraperField *)item;
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            field = [BrowserScraperField fieldWithDictionary:(NSDictionary *)item];
        }
        if (!field || !field.enabled) continue;
        NSString *name = field.name.length ? field.name : field.fieldID;
        NSString *raw = [self stringify:rawRow[name]];
        NSString *norm = [self applyTransforms:field.transforms rawValue:raw row:out context:ctx];
        out[name] = norm;
    }
    // 保留未在 fields 中声明的键（少见）
    [rawRow enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if (!out[key]) out[key] = [self stringify:obj];
    }];
    return out;
}

+ (NSArray<NSDictionary *> *)normalizeRows:(NSArray<NSDictionary *> *)rows
                                    fields:(NSArray *)fields
                                   context:(BrowserScraperTransformContext *)context {
    NSMutableArray *out = [NSMutableArray array];
    for (id row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        [out addObject:[self normalizeRow:(NSDictionary *)row fields:fields context:context]];
    }
    return out;
}

+ (NSString *)summaryForTransforms:(NSArray *)transforms {
    if (![transforms isKindOfClass:[NSArray class]] || transforms.count == 0) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    for (id step in transforms) {
        if (![step isKindOfClass:[NSDictionary class]]) continue;
        NSString *op = [self stringify:((NSDictionary *)step)[@"op"]];
        if (op.length) [parts addObject:op];
    }
    return [parts componentsJoinedByString:@"→"];
}

#pragma mark - Eval

+ (id)evalNode:(id)node
         input:(id)input
           raw:(NSString *)raw
           row:(NSDictionary *)row
       context:(BrowserScraperTransformContext *)ctx {
    if ([node isKindOfClass:[NSString class]] || [node isKindOfClass:[NSNumber class]]) {
        return node;
    }
    if (![node isKindOfClass:[NSDictionary class]]) {
        return input;
    }
    NSDictionary *step = (NSDictionary *)node;
    NSString *op = [[self stringify:step[@"op"]] lowercaseString];
    if (op.length == 0) return input;

    // 若步骤声明了嵌套 input，先求它
    id working = input;
    if (step[@"input"] != nil) {
        working = [self evalNode:step[@"input"] input:input raw:raw row:row context:ctx];
    }

    if ([op isEqualToString:@"raw"]) return raw ?: @"";
    if ([op isEqualToString:@"const"]) return [self stringify:step[@"value"]];
    if ([op isEqualToString:@"field"]) {
        NSString *name = [self stringify:step[@"name"]];
        return [self stringify:row[name]];
    }
    if ([op isEqualToString:@"coalesce"]) {
        NSArray *inputs = [step[@"inputs"] isKindOfClass:[NSArray class]] ? step[@"inputs"] : @[];
        for (id part in inputs) {
            id v = [self evalNode:part input:working raw:raw row:row context:ctx];
            NSString *s = [self stringify:v];
            if (![self isEmpty:s]) return s;
        }
        return @"";
    }
    if ([op isEqualToString:@"concat"]) {
        NSArray *parts = [step[@"parts"] isKindOfClass:[NSArray class]] ? step[@"parts"] : @[];
        NSMutableString *acc = [NSMutableString string];
        if (parts.count == 0) {
            [acc appendString:[self stringify:working]];
        } else {
            for (id part in parts) {
                id v = [self evalNode:part input:working raw:raw row:row context:ctx];
                [acc appendString:[self stringify:v]];
            }
        }
        return acc;
    }
    if ([op isEqualToString:@"default"]) {
        NSString *s = [self stringify:working];
        if ([self isEmpty:s]) return [self stringify:step[@"value"]];
        return s;
    }
    if ([op isEqualToString:@"ifEmpty"]) {
        NSString *s = [self stringify:working];
        if ([self isEmpty:s] && step[@"then"] != nil) {
            return [self evalNode:step[@"then"] input:working raw:raw row:row context:ctx];
        }
        return working;
    }

    NSString *text = [self stringify:working];

    if ([op isEqualToString:@"trim"]) {
        return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([op isEqualToString:@"collapsespace"] || [op isEqualToString:@"collapseSpace"]) {
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:&err];
        NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return [re stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@" "];
    }
    if ([op isEqualToString:@"lower"]) return text.lowercaseString;
    if ([op isEqualToString:@"upper"]) return text.uppercaseString;
    if ([op isEqualToString:@"remove"]) {
        NSString *chars = [self stringify:step[@"chars"]];
        if (chars.length == 0) chars = @"¥￥$€£,，";
        NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:chars];
        return [[text componentsSeparatedByCharactersInSet:set] componentsJoinedByString:@""];
    }
    if ([op isEqualToString:@"replace"]) {
        NSString *pattern = [self stringify:step[@"pattern"]];
        NSString *with = [self stringify:step[@"with"]];
        BOOL useRegex = [step[@"regex"] boolValue];
        if (pattern.length == 0) return text;
        if (useRegex) {
            NSError *err = nil;
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&err];
            if (!re) return [self fail:ctx raw:raw];
            return [re stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:with];
        }
        return [text stringByReplacingOccurrencesOfString:pattern withString:with];
    }
    if ([op isEqualToString:@"regex"]) {
        NSString *pattern = [self stringify:step[@"pattern"]];
        NSInteger group = step[@"group"] != nil ? [step[@"group"] integerValue] : 1;
        if (pattern.length == 0) return [self fail:ctx raw:raw];
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&err];
        if (!re) return [self fail:ctx raw:raw];
        NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (!m) return [self fail:ctx raw:raw];
        if (group >= 0 && group < (NSInteger)m.numberOfRanges) {
            NSRange r = [m rangeAtIndex:group];
            if (r.location != NSNotFound) return [text substringWithRange:r];
        }
        return [text substringWithRange:m.range];
    }
    if ([op isEqualToString:@"substr"]) {
        NSInteger start = [step[@"start"] integerValue];
        NSInteger length = step[@"length"] != nil ? [step[@"length"] integerValue] : NSIntegerMax;
        NSInteger n = (NSInteger)text.length;
        if (start < 0) start = MAX(0, n + start);
        if (start >= n) return @"";
        if (length < 0) length = 0;
        NSInteger end = (length == NSIntegerMax) ? n : MIN(n, start + length);
        if (end < start) return @"";
        return [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
    }
    if ([op isEqualToString:@"before"]) {
        NSString *sep = [self stringify:step[@"sep"]];
        NSRange r = [text rangeOfString:sep];
        if (r.location == NSNotFound) return text;
        return [text substringToIndex:r.location];
    }
    if ([op isEqualToString:@"after"]) {
        NSString *sep = [self stringify:step[@"sep"]];
        NSRange r = [text rangeOfString:sep];
        if (r.location == NSNotFound) return @"";
        return [text substringFromIndex:NSMaxRange(r)];
    }
    if ([op isEqualToString:@"between"]) {
        NSString *left = [self stringify:step[@"left"]];
        NSString *right = [self stringify:step[@"right"]];
        NSRange r1 = [text rangeOfString:left];
        if (r1.location == NSNotFound) return [self fail:ctx raw:raw];
        NSString *rest = [text substringFromIndex:NSMaxRange(r1)];
        NSRange r2 = [rest rangeOfString:right];
        if (r2.location == NSNotFound) return rest;
        return [rest substringToIndex:r2.location];
    }
    if ([op isEqualToString:@"digits"]) {
        return [self extractDigits:text keepPlus:[step[@"keepPlus"] boolValue]];
    }
    if ([op isEqualToString:@"number"]) {
        return [self parseNumber:text style:[self stringify:step[@"style"]]];
    }
    if ([op isEqualToString:@"round"] || [op isEqualToString:@"floor"] || [op isEqualToString:@"ceil"]) {
        double v = [self parseNumberValue:text];
        NSInteger precision = step[@"precision"] != nil ? [step[@"precision"] integerValue] : 0;
        double scale = pow(10.0, MAX(0, precision));
        if ([op isEqualToString:@"floor"]) v = floor(v * scale) / scale;
        else if ([op isEqualToString:@"ceil"]) v = ceil(v * scale) / scale;
        else v = round(v * scale) / scale;
        if (precision <= 0) return [NSString stringWithFormat:@"%.0f", v];
        NSString *fmt = [NSString stringWithFormat:@"%%.%ldf", (long)precision];
        return [NSString stringWithFormat:fmt, v];
    }
    if ([op isEqualToString:@"scale"]) {
        double v = [self parseNumberValue:text];
        double mul = step[@"multiply"] != nil ? [step[@"multiply"] doubleValue] : 1.0;
        double div = step[@"divide"] != nil ? [step[@"divide"] doubleValue] : 1.0;
        if (fabs(div) < 1e-12) return [self fail:ctx raw:raw];
        v = v * mul / div;
        return [self stringify:@(v)];
    }
    if ([op isEqualToString:@"clamp"]) {
        double v = [self parseNumberValue:text];
        if (step[@"min"] != nil) v = MAX(v, [step[@"min"] doubleValue]);
        if (step[@"max"] != nil) v = MIN(v, [step[@"max"] doubleValue]);
        return [self stringify:@(v)];
    }
    if ([op isEqualToString:@"reltime"] || [op isEqualToString:@"relTime"]) {
        NSDate *date = [self parseRelativeTime:text now:ctx.now ?: [NSDate date]];
        if (!date) return [self fail:ctx raw:raw];
        NSString *unit = [[self stringify:step[@"unit"]] lowercaseString];
        NSTimeInterval ts = date.timeIntervalSince1970;
        if ([unit isEqualToString:@"ms"]) return [NSString stringWithFormat:@"%.0f", ts * 1000.0];
        return [NSString stringWithFormat:@"%.0f", ts];
    }
    if ([op isEqualToString:@"parsetime"] || [op isEqualToString:@"parseTime"]) {
        NSString *fmt = [self stringify:step[@"format"]];
        if (fmt.length == 0) fmt = @"yyyy-MM-dd HH:mm:ss";
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        df.dateFormat = fmt;
        NSDate *date = [df dateFromString:text];
        if (!date) return [self fail:ctx raw:raw];
        NSString *unit = [[self stringify:step[@"unit"]] lowercaseString];
        NSTimeInterval ts = date.timeIntervalSince1970;
        if ([unit isEqualToString:@"ms"]) return [NSString stringWithFormat:@"%.0f", ts * 1000.0];
        return [NSString stringWithFormat:@"%.0f", ts];
    }
    if ([op isEqualToString:@"formattime"] || [op isEqualToString:@"formatTime"]) {
        double ts = [self parseNumberValue:text];
        NSString *unit = [[self stringify:step[@"unit"]] lowercaseString];
        if ([unit isEqualToString:@"ms"]) ts /= 1000.0;
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSString *fmt = [self stringify:step[@"format"]];
        if (fmt.length == 0) fmt = @"yyyy-MM-dd HH:mm:ss";
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        df.dateFormat = fmt;
        return [df stringFromDate:date] ?: @"";
    }
    if ([op isEqualToString:@"absurl"] || [op isEqualToString:@"absUrl"]) {
        NSString *base = [self stringify:step[@"base"]];
        if (base.length == 0) base = ctx.baseURL ?: @"";
        NSURL *baseURL = base.length ? [NSURL URLWithString:base] : nil;
        NSURL *abs = [NSURL URLWithString:text relativeToURL:baseURL];
        return abs.absoluteString ?: text;
    }
    if ([op isEqualToString:@"striptags"] || [op isEqualToString:@"stripTags"]) {
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:&err];
        return [re stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    }
    if ([op isEqualToString:@"decodeentities"] || [op isEqualToString:@"decodeEntities"]) {
        NSDictionary *map = @{
            @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'", @"&nbsp;": @" "
        };
        NSString *s = text;
        for (NSString *k in map) {
            s = [s stringByReplacingOccurrencesOfString:k withString:map[k]];
        }
        return s;
    }

    return working;
}

#pragma mark - Number helpers

+ (NSString *)extractDigits:(NSString *)text keepPlus:(BOOL)keepPlus {
    NSMutableString *out = [NSMutableString string];
    BOOL seenDot = NO;
    BOOL seenPlus = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [out appendFormat:@"%C", c];
        } else if ((c == '.' || c == 0xFF0E) && !seenDot) {
            seenDot = YES;
            [out appendString:@"."];
        } else if (keepPlus && c == '+' && !seenPlus && out.length > 0) {
            seenPlus = YES;
            [out appendString:@"+"];
        }
    }
    return out;
}

+ (double)parseNumberValue:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    t = [t stringByReplacingOccurrencesOfString:@"," withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"，" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"¥" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"￥" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"+" withString:@""];
    double mul = 1.0;
    if ([t containsString:@"亿"]) {
        mul = 100000000.0;
        t = [t stringByReplacingOccurrencesOfString:@"亿" withString:@""];
    } else if ([t containsString:@"万"]) {
        mul = 10000.0;
        t = [t stringByReplacingOccurrencesOfString:@"万" withString:@""];
    }
    NSString *digits = [self extractDigits:t keepPlus:NO];
    if (digits.length == 0) return 0;
    return digits.doubleValue * mul;
}

+ (NSString *)parseNumber:(NSString *)text style:(NSString *)style {
    double v = [self parseNumberValue:text];
    NSString *s = style.lowercaseString;
    if ([s isEqualToString:@"integer"]) {
        return [NSString stringWithFormat:@"%.0f", round(v)];
    }
    if ([s isEqualToString:@"decimal"]) {
        if (fabs(v - round(v)) < 1e-9) return [NSString stringWithFormat:@"%.0f", v];
        NSString *fmt = [NSString stringWithFormat:@"%.4f", v];
        while ([fmt hasSuffix:@"0"]) fmt = [fmt substringToIndex:fmt.length - 1];
        if ([fmt hasSuffix:@"."]) fmt = [fmt substringToIndex:fmt.length - 1];
        return fmt;
    }
    // string: keep cleaned digit form when possible
    NSString *d = [self extractDigits:text keepPlus:NO];
    return d.length ? d : [NSString stringWithFormat:@"%g", v];
}

#pragma mark - Relative time

+ (NSDate *)parseRelativeTime:(NSString *)text now:(NSDate *)now {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length == 0) return nil;
    if ([t isEqualToString:@"刚刚"] || [t isEqualToString:@"刚才"]) return now;

    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"(\\d+(?:\\.\\d+)?)\\s*(秒|分钟|分|小时|时|天|日|周|星期|月|年)\\s*前"
                             options:0 error:&err];
    NSTextCheckingResult *m = [re firstMatchInString:t options:0 range:NSMakeRange(0, t.length)];
    if (m && m.numberOfRanges >= 3) {
        double n = [[t substringWithRange:[m rangeAtIndex:1]] doubleValue];
        NSString *unit = [t substringWithRange:[m rangeAtIndex:2]];
        NSTimeInterval sec = 0;
        if ([unit hasPrefix:@"秒"]) sec = n;
        else if ([unit hasPrefix:@"分"]) sec = n * 60.0;
        else if ([unit hasPrefix:@"小时"] || [unit hasPrefix:@"时"]) sec = n * 3600.0;
        else if ([unit hasPrefix:@"天"] || [unit hasPrefix:@"日"]) sec = n * 86400.0;
        else if ([unit hasPrefix:@"周"] || [unit hasPrefix:@"星期"]) sec = n * 86400.0 * 7.0;
        else if ([unit hasPrefix:@"月"]) sec = n * 86400.0 * 30.0;
        else if ([unit hasPrefix:@"年"]) sec = n * 86400.0 * 365.0;
        return [now dateByAddingTimeInterval:-sec];
    }

    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDateComponents *day = [[NSDateComponents alloc] init];
    if ([t hasPrefix:@"昨天"] || [t isEqualToString:@"昨天"]) {
        day.day = -1;
        NSDate *base = [cal dateByAddingComponents:day toDate:now options:0];
        return [self applyClockIfPresent:t onDay:base calendar:cal];
    }
    if ([t hasPrefix:@"前天"]) {
        day.day = -2;
        NSDate *base = [cal dateByAddingComponents:day toDate:now options:0];
        return [self applyClockIfPresent:t onDay:base calendar:cal];
    }
    if ([t hasPrefix:@"今天"]) {
        return [self applyClockIfPresent:t onDay:now calendar:cal];
    }

    // 中文数字简易：一小时前
    NSDictionary *cn = @{ @"半": @0.5, @"一": @1, @"二": @2, @"两": @2, @"三": @3, @"四": @4, @"五": @5,
                          @"六": @6, @"七": @7, @"八": @8, @"九": @9, @"十": @10 };
    re = [NSRegularExpression regularExpressionWithPattern:@"([半一两二三四五六七八九十]+)\\s*(秒|分钟|分|小时|时|天)\\s*前"
                                                   options:0 error:&err];
    m = [re firstMatchInString:t options:0 range:NSMakeRange(0, t.length)];
    if (m && m.numberOfRanges >= 3) {
        NSString *cnNum = [t substringWithRange:[m rangeAtIndex:1]];
        NSNumber *num = cn[cnNum];
        double n = num != nil ? num.doubleValue : 1;
        NSString *unit = [t substringWithRange:[m rangeAtIndex:2]];
        NSTimeInterval sec = [unit hasPrefix:@"秒"] ? n : ([unit hasPrefix:@"分"] ? n * 60 : ([unit hasPrefix:@"天"] ? n * 86400 : n * 3600));
        return [now dateByAddingTimeInterval:-sec];
    }
    return nil;
}

+ (NSDate *)applyClockIfPresent:(NSString *)text onDay:(NSDate *)day calendar:(NSCalendar *)cal {
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d{1,2}):(\\d{2})" options:0 error:&err];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    NSDateComponents *base = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day];
    if (m) {
        base.hour = [[text substringWithRange:[m rangeAtIndex:1]] integerValue];
        base.minute = [[text substringWithRange:[m rangeAtIndex:2]] integerValue];
        base.second = 0;
    }
    return [cal dateFromComponents:base] ?: day;
}

#pragma mark - Catalog / presets

+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)presetTemplates {
    return @{
        @"提取数字": @[ @{ @"op": @"digits" }, @{ @"op": @"number", @"style": @"integer" } ],
        @"提取小数": @[ @{ @"op": @"digits" }, @{ @"op": @"number", @"style": @"decimal" } ],
        @"去货币转价格": @[ @{ @"op": @"remove", @"chars": @"¥￥$€£,， " }, @{ @"op": @"digits" }, @{ @"op": @"number", @"style": @"decimal" } ],
        @"销量数字": @[ @{ @"op": @"regex", @"pattern": @"(\\d+(?:\\.\\d+)?)", @"group": @1 }, @{ @"op": @"number", @"style": @"integer" } ],
        @"相对时间→时间戳": @[ @{ @"op": @"relTime", @"unit": @"s" } ],
        @"去空白": @[ @{ @"op": @"trim" }, @{ @"op": @"collapseSpace" } ],
        @"补全https": @[ @{ @"op": @"concat", @"parts": @[ @{ @"op": @"const", @"value": @"https:" }, @{ @"op": @"raw" } ] } ],
    };
}

+ (NSArray<NSDictionary *> *)catalog {
    return @[
        @{ @"op": @"trim", @"title": @"去首尾空白", @"group": @"字符串",
           @"help": @"去掉字符串开头和结尾的空格、换行等空白字符。",
           @"usage": @"{\"op\":\"trim\"}",
           @"example": @"\"  18人付款  \" → \"18人付款\"" },
        @{ @"op": @"collapseSpace", @"title": @"压缩空格", @"group": @"字符串",
           @"help": @"先 trim，再把连续空白压缩为单个空格。",
           @"usage": @"{\"op\":\"collapseSpace\"}",
           @"example": @"\"已售   300+\" → \"已售 300+\"" },
        @{ @"op": @"lower", @"title": @"转小写", @"group": @"字符串",
           @"help": @"将英文字母转为小写。",
           @"usage": @"{\"op\":\"lower\"}",
           @"example": @"\"Hello\" → \"hello\"" },
        @{ @"op": @"upper", @"title": @"转大写", @"group": @"字符串",
           @"help": @"将英文字母转为大写。",
           @"usage": @"{\"op\":\"upper\"}",
           @"example": @"\"Hello\" → \"HELLO\"" },
        @{ @"op": @"replace", @"title": @"替换", @"group": @"字符串",
           @"help": @"把 pattern 替换为 with。regex 为 true 时按正则替换。",
           @"usage": @"{\"op\":\"replace\",\"pattern\":\"人付款\",\"with\":\"\"}\n{\"op\":\"replace\",\"pattern\":\"\\\\d+\",\"with\":\"#\",\"regex\":true}",
           @"example": @"\"18人付款\" → \"18\"" },
        @{ @"op": @"regex", @"title": @"正则提取", @"group": @"字符串",
           @"help": @"用正则匹配并提取捕获组。group 默认 1；无匹配则按 onError 返回空或原文。",
           @"usage": @"{\"op\":\"regex\",\"pattern\":\"(\\\\d+(?:\\\\.\\\\d+)?)\",\"group\":1}",
           @"example": @"\"已售300+\" → \"300\"" },
        @{ @"op": @"substr", @"title": @"截取", @"group": @"字符串",
           @"help": @"按 start / length 截取。start 可为负数（从末尾倒数）。",
           @"usage": @"{\"op\":\"substr\",\"start\":0,\"length\":2}",
           @"example": @"\"abcdef\" → \"ab\"" },
        @{ @"op": @"before", @"title": @"分隔符前", @"group": @"字符串",
           @"help": @"取第一次出现 sep 之前的子串；找不到则返回全文。",
           @"usage": @"{\"op\":\"before\",\"sep\":\"|\"}",
           @"example": @"\"瓶装|进口\" → \"瓶装\"" },
        @{ @"op": @"after", @"title": @"分隔符后", @"group": @"字符串",
           @"help": @"取第一次出现 sep 之后的子串。",
           @"usage": @"{\"op\":\"after\",\"sep\":\"¥\"}",
           @"example": @"\"¥369\" → \"369\"" },
        @{ @"op": @"between", @"title": @"夹取", @"group": @"字符串",
           @"help": @"取 left 与 right 之间的内容。",
           @"usage": @"{\"op\":\"between\",\"left\":\"【\",\"right\":\"】\"}",
           @"example": @"\"价【7.8】元\" → \"7.8\"" },
        @{ @"op": @"remove", @"title": @"删除字符", @"group": @"字符串",
           @"help": @"删除 chars 中出现的任意字符。默认删除常见货币符号与逗号。",
           @"usage": @"{\"op\":\"remove\",\"chars\":\"¥￥$€£,， \"}",
           @"example": @"\"¥7.8\" → \"7.8\"" },
        @{ @"op": @"concat", @"title": @"拼接", @"group": @"字符串",
           @"help": @"按 parts 顺序拼接；part 可为 const / raw / field 或嵌套步骤。",
           @"usage": @"{\"op\":\"concat\",\"parts\":[{\"op\":\"const\",\"value\":\"https:\"},{\"op\":\"raw\"}]}",
           @"example": @"\"//item.jd.com/1\" → \"https://item.jd.com/1\"" },
        @{ @"op": @"default", @"title": @"默认值", @"group": @"字符串",
           @"help": @"当前值为空时用 value 代替。",
           @"usage": @"{\"op\":\"default\",\"value\":\"0\"}",
           @"example": @"\"\" → \"0\"" },
        @{ @"op": @"coalesce", @"title": @"取首个非空", @"group": @"字符串",
           @"help": @"在 inputs 中求值，返回第一个非空结果。",
           @"usage": @"{\"op\":\"coalesce\",\"inputs\":[{\"op\":\"field\",\"name\":\"副标题\"},{\"op\":\"raw\"}]}",
           @"example": @"副标题空时回退到原文" },
        @{ @"op": @"const", @"title": @"常量", @"group": @"字符串",
           @"help": @"输出固定字符串，常用于 concat。",
           @"usage": @"{\"op\":\"const\",\"value\":\"https:\"}",
           @"example": @"→ \"https:\"" },
        @{ @"op": @"raw", @"title": @"字段原文", @"group": @"字符串",
           @"help": @"始终取本字段抽取的原始值（忽略上一步输出）。",
           @"usage": @"{\"op\":\"raw\"}",
           @"example": @"管线中间重新取原文" },
        @{ @"op": @"field", @"title": @"引用其他字段", @"group": @"字符串",
           @"help": @"取同行中已处理完的字段值。只能引用排在当前字段前面的列。",
           @"usage": @"{\"op\":\"field\",\"name\":\"价格\"}",
           @"example": @"拼接「价格」字段的结果" },
        @{ @"op": @"ifEmpty", @"title": @"空则分支", @"group": @"字符串",
           @"help": @"当前为空时执行 then 嵌套节点。",
           @"usage": @"{\"op\":\"ifEmpty\",\"then\":{\"op\":\"const\",\"value\":\"未知\"}}",
           @"example": @"\"\" → \"未知\"" },

        @{ @"op": @"digits", @"title": @"提取数字字符", @"group": @"数值",
           @"help": @"只保留数字和一个小数点；keepPlus 为 true 时可保留末尾 +。",
           @"usage": @"{\"op\":\"digits\"}\n{\"op\":\"digits\",\"keepPlus\":true}",
           @"example": @"\"已售300+\" → \"300\" 或 \"300+\"" },
        @{ @"op": @"number", @"title": @"转为数值", @"group": @"数值",
           @"help": @"解析数字，支持 万/亿、去掉货币与逗号。style: integer | decimal | string。",
           @"usage": @"{\"op\":\"number\",\"style\":\"integer\"}\n{\"op\":\"number\",\"style\":\"decimal\"}",
           @"example": @"\"3.5万\" → \"35000\"" },
        @{ @"op": @"round", @"title": @"四舍五入", @"group": @"数值",
           @"help": @"按 precision 小数位四舍五入。",
           @"usage": @"{\"op\":\"round\",\"precision\":2}",
           @"example": @"\"3.1415\" → \"3.14\"" },
        @{ @"op": @"floor", @"title": @"向下取整", @"group": @"数值",
           @"help": @"按 precision 向下取整。",
           @"usage": @"{\"op\":\"floor\",\"precision\":0}",
           @"example": @"\"3.9\" → \"3\"" },
        @{ @"op": @"ceil", @"title": @"向上取整", @"group": @"数值",
           @"help": @"按 precision 向上取整。",
           @"usage": @"{\"op\":\"ceil\",\"precision\":0}",
           @"example": @"\"3.1\" → \"4\"" },
        @{ @"op": @"scale", @"title": @"缩放", @"group": @"数值",
           @"help": @"结果 = 值 × multiply ÷ divide。常用于分转元。",
           @"usage": @"{\"op\":\"scale\",\"multiply\":1,\"divide\":100}",
           @"example": @"\"880\" 分 → \"8.8\" 元" },
        @{ @"op": @"clamp", @"title": @"限制范围", @"group": @"数值",
           @"help": @"把数值限制在 min～max。",
           @"usage": @"{\"op\":\"clamp\",\"min\":0,\"max\":100}",
           @"example": @"\"150\" → \"100\"" },

        @{ @"op": @"relTime", @"title": @"相对时间→时间戳", @"group": @"时间",
           @"help": @"解析「一小时前」「3天前」「刚刚」「昨天」等，输出 Unix 时间戳。unit: s（默认）或 ms。",
           @"usage": @"{\"op\":\"relTime\"}\n{\"op\":\"relTime\",\"unit\":\"ms\"}",
           @"example": @"\"一小时前\" → 当前时间减 3600 秒的时间戳" },
        @{ @"op": @"parseTime", @"title": @"解析绝对时间", @"group": @"时间",
           @"help": @"按 format 解析日期时间字符串为时间戳。默认时区 Asia/Shanghai。",
           @"usage": @"{\"op\":\"parseTime\",\"format\":\"yyyy-MM-dd HH:mm:ss\"}",
           @"example": @"\"2026-09-10 12:00:00\" → Unix 秒" },
        @{ @"op": @"formatTime", @"title": @"格式化时间", @"group": @"时间",
           @"help": @"把时间戳格式化为字符串。输入默认秒；unit 为 ms 时按毫秒解析。",
           @"usage": @"{\"op\":\"formatTime\",\"format\":\"yyyy-MM-dd HH:mm:ss\"}",
           @"example": @"1720000000 → \"2024-...\"" },

        @{ @"op": @"absUrl", @"title": @"绝对 URL", @"group": @"URL",
           @"help": @"相对链接转绝对地址。可用 base，否则用当前页 URL。",
           @"usage": @"{\"op\":\"absUrl\"}\n{\"op\":\"absUrl\",\"base\":\"https://www.jd.com/\"}",
           @"example": @"\"//item.jd.com/1.html\" → \"https://item.jd.com/1.html\"" },
        @{ @"op": @"stripTags", @"title": @"去 HTML 标签", @"group": @"URL",
           @"help": @"去掉 HTML 标签，保留文本。",
           @"usage": @"{\"op\":\"stripTags\"}",
           @"example": @"\"<b>标题</b>\" → \"标题\"" },
        @{ @"op": @"decodeEntities", @"title": @"解码实体", @"group": @"URL",
           @"help": @"解码常见 HTML 实体（&amp; &lt; &nbsp; 等）。",
           @"usage": @"{\"op\":\"decodeEntities\"}",
           @"example": @"\"A&amp;B\" → \"A&B\"" },
    ];
}

+ (NSString *)helpDocumentText {
    NSMutableString *doc = [NSMutableString string];
    [doc appendString:@"字段值处理函数说明\n"];
    [doc appendString:@"====================\n\n"];
    [doc appendString:@"用法概述\n"];
    [doc appendString:@"--------\n"];
    [doc appendString:@"每个字段的 transforms 是一个「步骤数组」，按顺序执行。\n"];
    [doc appendString:@"上一步的输出是下一步的输入；默认输入是字段抽取原文。\n\n"];
    [doc appendString:@"示例（已售300+ → 300）：\n"];
    [doc appendString:@"[\n"];
    [doc appendString:@"  {\"op\":\"digits\"},\n"];
    [doc appendString:@"  {\"op\":\"number\",\"style\":\"integer\"}\n"];
    [doc appendString:@"]\n\n"];
    [doc appendString:@"步骤可嵌套：concat / coalesce / ifEmpty 的 parts、inputs、then、input 可为子节点。\n\n"];

    NSArray *catalog = [self catalog];
    NSMutableArray *groups = [NSMutableArray array];
    NSMutableDictionary *byGroup = [NSMutableDictionary dictionary];
    for (NSDictionary *item in catalog) {
        NSString *g = item[@"group"] ?: @"其他";
        if (!byGroup[g]) {
            byGroup[g] = [NSMutableArray array];
            [groups addObject:g];
        }
        [byGroup[g] addObject:item];
    }
    for (NSString *g in groups) {
        [doc appendFormat:@"【%@】\n", g];
        [doc appendString:@"--------------------\n"];
        for (NSDictionary *item in byGroup[g]) {
            [doc appendFormat:@"◆ %@（%@）\n", item[@"op"] ?: @"", item[@"title"] ?: @""];
            if ([item[@"help"] length]) [doc appendFormat:@"  说明：%@\n", item[@"help"]];
            if ([item[@"usage"] length]) {
                [doc appendString:@"  用法：\n"];
                for (NSString *line in [item[@"usage"] componentsSeparatedByString:@"\n"]) {
                    [doc appendFormat:@"    %@\n", line];
                }
            }
            if ([item[@"example"] length]) [doc appendFormat:@"  示例：%@\n", item[@"example"]];
            [doc appendString:@"\n"];
        }
    }

    [doc appendString:@"预设模板\n"];
    [doc appendString:@"--------\n"];
    NSDictionary *presets = [self presetTemplates];
    NSArray *keys = [[presets allKeys] sortedArrayUsingSelector:@selector(localizedCompare:)];
    for (NSString *k in keys) {
        [doc appendFormat:@"· %@\n", k];
        NSData *data = [NSJSONSerialization dataWithJSONObject:presets[k]
                                                       options:0
                                                         error:nil];
        NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        [doc appendFormat:@"  %@\n\n", json];
    }
    return doc;
}

@end
