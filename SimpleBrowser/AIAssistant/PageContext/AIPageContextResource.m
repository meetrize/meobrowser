#import "AIPageContextResource.h"

@implementation AIPageContextResource

+ (AIPageContextResourceKind)kindFromString:(NSString *)s {
    NSString *k = s.lowercaseString ?: @"";
    if ([k isEqualToString:@"script"] || [k isEqualToString:@"js"]) return AIPageContextResourceKindScript;
    if ([k isEqualToString:@"stylesheet"] || [k isEqualToString:@"css"] || [k isEqualToString:@"style"]) {
        return AIPageContextResourceKindStylesheet;
    }
    if ([k isEqualToString:@"json"]) return AIPageContextResourceKindJSON;
    if ([k isEqualToString:@"image"] || [k isEqualToString:@"img"]) return AIPageContextResourceKindImage;
    return AIPageContextResourceKindOther;
}

+ (instancetype)resourceFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    AIPageContextResource *r = [[AIPageContextResource alloc] init];
    NSString *rid = dict[@"id"];
    r.resourceId = [rid isKindOfClass:[NSString class]] && rid.length ? rid : [[NSUUID UUID] UUIDString];
    NSString *kind = dict[@"kind"];
    r.kind = [self kindFromString:[kind isKindOfClass:[NSString class]] ? kind : @""];
    NSString *url = dict[@"url"];
    r.urlString = [url isKindOfClass:[NSString class]] ? url : nil;
    NSString *label = dict[@"label"];
    if (![label isKindOfClass:[NSString class]] || label.length == 0) {
        if (r.urlString.length) {
            label = [NSURL URLWithString:r.urlString].lastPathComponent;
        }
        if (label.length == 0) label = r.kindDisplayName;
    }
    r.label = label;
    id inl = dict[@"inline"];
    r.inlineContent = [inl respondsToSelector:@selector(boolValue)] ? [inl boolValue] : NO;
    NSString *text = dict[@"text"];
    r.text = [text isKindOfClass:[NSString class]] ? text : nil;
    id size = dict[@"size"];
    if ([size respondsToSelector:@selector(unsignedIntegerValue)]) {
        r.reportedSize = [size unsignedIntegerValue];
    } else if (r.text.length) {
        r.reportedSize = r.text.length;
    }
    return r;
}

- (NSString *)kindDisplayName {
    switch (self.kind) {
        case AIPageContextResourceKindScript: return @"JS";
        case AIPageContextResourceKindStylesheet: return @"CSS";
        case AIPageContextResourceKindJSON: return @"JSON";
        case AIPageContextResourceKindImage: return @"图";
        default: return @"资源";
    }
}

- (NSString *)chipLabel {
    NSString *name = self.label.length ? self.label : (self.urlString ?: self.kindDisplayName);
    name = [name stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (name.length > 16) name = [[name substringToIndex:16] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@ · %@", self.kindDisplayName, name];
}

- (BOOL)hasTextBody {
    return self.text.length > 0;
}

- (BOOL)canFetchSameOrigin {
    return self.urlString.length > 0 && !self.hasTextBody && self.kind != AIPageContextResourceKindImage;
}

@end
