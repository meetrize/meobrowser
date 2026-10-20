#import "BrowserDOMValueSegmenter.h"

static const NSUInteger kMaxSegmentDepth = 2;
static const NSUInteger kMaxSegments = 200;
static const NSUInteger kMinSplitParts = 2;

@implementation DomValueSegment

- (instancetype)initWithKind:(DomSegmentKind)kind
                         text:(NSString *)text
                    fullPath:(NSString *)fullPath
                       depth:(NSUInteger)depth {
    self = [super init];
    if (self) {
        _kind = kind;
        _text = [text copy] ?: @"";
        _fullPath = [fullPath copy] ?: @"";
        _depth = depth;
    }
    return self;
}

@end

@implementation BrowserDOMValueSegmenter

+ (BOOL)shouldSegmentValue:(NSString *)value {
    if (value.length == 0) return NO;
    if ([self jsonObjectForValue:value]) return YES;
    if ([self bracketPartsForValue:value].count >= kMinSplitParts) return YES;
    if ([self separatorPartsForValue:value].count >= kMinSplitParts) return YES;
    if ([self keyValuePairsForValue:value].count >= kMinSplitParts) return YES;
    return NO;
}

+ (NSArray<DomValueSegment *> *)segmentsForValue:(NSString *)value rootPath:(NSString *)rootPath {
    NSString *root = rootPath.length > 0 ? rootPath : @"";
    if (value.length == 0) {
        return @[[[DomValueSegment alloc] initWithKind:DomSegmentKindLiteral
                                                  text:@"（空）"
                                             fullPath:root
                                                depth:0]];
    }
    NSMutableArray<DomValueSegment *> *out = [NSMutableArray array];
    [self appendSegmentsForValue:value rootPath:root depth:0 into:out];
    if (out.count == 0) {
        [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindLiteral
                                                       text:value
                                                  fullPath:root
                                                     depth:0]];
    }
    return [out copy];
}

#pragma mark - Core

+ (void)appendSegmentsForValue:(NSString *)value
                      rootPath:(NSString *)rootPath
                        depth:(NSUInteger)depth
                         into:(NSMutableArray<DomValueSegment *> *)out {
    if (out.count >= kMaxSegments || value.length == 0) return;

    // R1：合法 JSON
    id json = [self jsonObjectForValue:value];
    if (json) {
        [self appendJSONValue:json path:rootPath depth:depth into:out];
        return;
    }

    // R2：标识符 + 一个或多个 []，如 row[price] / cfg[theme][colors]
    NSArray<NSString *> *brackets = [self bracketPartsForValue:value];
    if (brackets.count >= kMinSplitParts) {
        NSString *identifier = [self identifierPartOfBracketExpression:value];
        if (identifier.length > 0) {
            [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindIdentifier
                                                           text:identifier
                                                      fullPath:rootPath.length > 0 ? rootPath : identifier
                                                         depth:depth]];
        }
        for (NSString *bracket in brackets) {
            [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindBracketKey
                                                           text:bracket
                                                      fullPath:[self pathByAppending:rootPath component:bracket]
                                                         depth:depth]];
        }
        return;
    }

    // R6：括号键值，如 id=a&b=c
    NSArray<NSDictionary *> *pairs = [self keyValuePairsForValue:value];
    if (pairs.count >= kMinSplitParts) {
        for (NSDictionary *pair in pairs) {
            NSString *key = pair[@"key"] ?: @"";
            NSString *val = pair[@"value"] ?: @"";
            NSString *keyPath = [self pathByAppending:rootPath component:key];
            [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindIdentifier
                                                           text:key
                                                      fullPath:keyPath
                                                         depth:depth]];
            if (depth < kMaxSegmentDepth) {
                [self appendSegmentsForValue:val rootPath:keyPath depth:depth + 1 into:out];
            } else {
                [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindLiteral
                                                               text:val
                                                          fullPath:keyPath
                                                             depth:depth + 1]];
            }
        }
        return;
    }

    // R3：分隔符切分
    NSArray<NSString *> *parts = [self separatorPartsForValue:value];
    if (parts.count >= kMinSplitParts) {
        for (NSString *part in parts) {
            [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindLiteral
                                                           text:part
                                                      fullPath:[self pathByAppending:rootPath component:part]
                                                         depth:depth]];
        }
        return;
    }

    // R5：超长 / 兜底单段
    [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindLiteral
                                                   text:value
                                              fullPath:rootPath
                                                 depth:depth]];
}

#pragma mark - JSON

+ (id)jsonObjectForValue:(NSString *)value {
    if (value.length < 2) return nil;
    unichar first = [value characterAtIndex:0];
    unichar last = [value characterAtIndex:value.length - 1];
    BOOL looksJSON = (first == '{' && last == '}') || (first == '[' && last == ']');
    if (!looksJSON) return nil;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    BOOL ok = [parsed isKindOfClass:[NSDictionary class]] || [parsed isKindOfClass:[NSArray class]];
    return ok ? parsed : nil;
}

+ (void)appendJSONValue:(id)value
                   path:(NSString *)path
                 depth:(NSUInteger)depth
                  into:(NSMutableArray<DomValueSegment *> *)out {
    if (out.count >= kMaxSegments) return;

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = value;
        for (NSString *key in dict) {
            NSString *childPath = [self pathByAppending:path component:key];
            [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindIdentifier
                                                           text:key
                                                      fullPath:childPath
                                                         depth:depth]];
            [self appendJSONValue:dict[key] path:childPath depth:depth + 1 into:out];
        }
        return;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        for (NSUInteger i = 0; i < array.count; i++) {
            id child = array[i];
            NSString *key = [NSString stringWithFormat:@"[%lu]", (unsigned long)i];
            NSString *childPath = [self pathByAppending:path component:key];
            BOOL nested = [child isKindOfClass:[NSDictionary class]] || [child isKindOfClass:[NSArray class]];
            [out addObject:[[DomValueSegment alloc] initWithKind:(nested ? DomSegmentKindIdentifier
                                                                         : DomSegmentKindJSONLeaf)
                                                           text:(nested ? key : [self stringFromJSONLeaf:child])
                                                      fullPath:childPath
                                                         depth:depth]];
            if (nested) {
                [self appendJSONValue:child path:childPath depth:depth + 1 into:out];
            }
        }
        return;
    }
    [out addObject:[[DomValueSegment alloc] initWithKind:DomSegmentKindJSONLeaf
                                                   text:[self stringFromJSONLeaf:value]
                                              fullPath:path
                                                 depth:depth]];
}

+ (NSString *)stringFromJSONLeaf:(id)leaf {
    if (!leaf) return @"null";
    if ([leaf isKindOfClass:[NSString class]]) return leaf;
    if ([leaf isKindOfClass:[NSNumber class]]) return [leaf stringValue];
    return [leaf description] ?: @"";
}

#pragma mark - Bracket Expression

/// `row[price][0]` → @[@"[price]", @"[0]"]。必须整串被 `标识符 + []+` 覆盖，避免误伤普通文本。
+ (NSArray<NSString *> *)bracketPartsForValue:(NSString *)value {
    NSString *identifier = [self identifierPartOfBracketExpression:value];
    if (identifier.length == 0) return @[];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger length = value.length;
    NSUInteger i = identifier.length;
    while (i < length) {
        if ([value characterAtIndex:i] != '[') return @[];
        NSRange close = [value rangeOfString:@"]"
                                   options:NSLiteralSearch
                                     range:NSMakeRange(i, length - i)];
        if (close.location == NSNotFound) return @[];
        [parts addObject:[value substringWithRange:NSMakeRange(i, close.location - i + 1)]];
        i = close.location + close.length;
    }
    return [parts copy];
}

+ (NSString *)identifierPartOfBracketExpression:(NSString *)value {
    NSUInteger i = 0;
    while (i < value.length) {
        unichar c = [value characterAtIndex:i];
        BOOL identChar = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                         (c >= '0' && c <= '9') || c == '_' || c == '$' || c == '-' || c == '.';
        if (!identChar) break;
        i++;
    }
    if (i == 0 || i >= value.length) return @"";
    if ([value characterAtIndex:i] != '[') return @"";
    return [value substringToIndex:i];
}

#pragma mark - Key Value

/// `a=1&b=2` / `a=1;b=2` → @[@{key,value}]；任一段缺 `=` 则整体放弃（避免误判）。
+ (NSArray<NSDictionary *> *)keyValuePairsForValue:(NSString *)value {
    NSArray<NSString *> *rawParts = [value componentsSeparatedByCharactersInSet:
                                     [NSCharacterSet characterSetWithCharactersInString:@"&;"]];
    if (rawParts.count < kMinSplitParts) return @[];
    NSMutableArray<NSDictionary *> *pairs = [NSMutableArray array];
    for (NSString *part in rawParts) {
        NSRange eq = [part rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) return @[];
        [pairs addObject:@{ @"key": [part substringToIndex:eq.location],
                            @"value": [part substringFromIndex:eq.location + 1] }];
    }
    return [pairs copy];
}

#pragma mark - Separators

+ (NSArray<NSString *> *)separatorPartsForValue:(NSString *)value {
    if (value.length < 2) return @[];
    if ([value rangeOfString:@":"].location != NSNotFound) return @[]; // URL / 时间戳不切
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@","];
    if (parts.count >= kMinSplitParts) {
        BOOL allNonEmpty = YES;
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) { allNonEmpty = NO; break; }
        }
        if (allNonEmpty) return parts;
    }
    parts = [value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (parts.count >= kMinSplitParts) return parts;
    return @[];
}

#pragma mark - Path

+ (NSString *)pathByAppending:(NSString *)path component:(NSString *)component {
    if (component.length == 0) return path ?: @"";
    if (path.length == 0) return component;
    return [NSString stringWithFormat:@"%@ → %@", path, component];
}

@end
