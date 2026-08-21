#import "PagePackModels.h"

NSErrorDomain const PagePackErrorDomain = @"PagePackErrorDomain";

@implementation PagePackFile

+ (instancetype)fileWithName:(NSString *)name kind:(PagePackFileKind)kind {
    if (![self isValidFileName:name error:nil]) {
        return nil;
    }
    PagePackFile *file = [[self alloc] init];
    file.name = name;
    file.kind = kind;
    file.runAt = PagePackRunAtDocumentEnd;
    file.mainFrameOnly = YES;
    return file;
}

+ (BOOL)isValidFileName:(NSString *)name error:(NSError **)error {
    if (name.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件名不能为空"}];
        }
        return NO;
    }
    if ([name containsString:@"/"] || [name containsString:@"\\"] || [name containsString:@".."]) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件名非法"}];
        }
        return NO;
    }
    NSString *ext = name.pathExtension.lowercaseString;
    if (![ext isEqualToString:@"css"] && ![ext isEqualToString:@"js"]) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"仅支持 .css / .js"}];
        }
        return NO;
    }
    NSString *base = name.stringByDeletingPathExtension;
    if (base.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件名非法"}];
        }
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    if ([base rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PagePackErrorDomain
                                         code:PagePackErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件名仅允许字母数字 . _ -"}];
        }
        return NO;
    }
    return YES;
}

+ (BOOL)kindForFileName:(NSString *)name outKind:(PagePackFileKind *)outKind {
    NSString *ext = name.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"css"]) {
        if (outKind) {
            *outKind = PagePackFileKindCSS;
        }
        return YES;
    }
    if ([ext isEqualToString:@"js"]) {
        if (outKind) {
            *outKind = PagePackFileKindJS;
        }
        return YES;
    }
    return NO;
}

- (NSDictionary *)dictionaryRepresentation {
    NSString *kind = (self.kind == PagePackFileKindCSS) ? @"css" : @"js";
    NSString *runAt = @"document-end";
    switch (self.runAt) {
        case PagePackRunAtDocumentStart: runAt = @"document-start"; break;
        case PagePackRunAtDocumentIdle: runAt = @"document-idle"; break;
        case PagePackRunAtDocumentEnd:
        default: break;
    }
    return @{
        @"name": self.name ?: @"",
        @"kind": kind,
        @"runAt": runAt,
        @"mainFrameOnly": @(self.mainFrameOnly),
    };
}

+ (nullable instancetype)fileWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : nil;
    if (![self isValidFileName:name error:nil]) {
        return nil;
    }
    NSString *kindStr = [dictionary[@"kind"] isKindOfClass:[NSString class]] ? dictionary[@"kind"] : name.pathExtension;
    PagePackFileKind kind = [kindStr.lowercaseString isEqualToString:@"css"] ? PagePackFileKindCSS : PagePackFileKindJS;
    PagePackFile *file = [self fileWithName:name kind:kind];
    if (!file) {
        return nil;
    }
    NSString *runAt = [dictionary[@"runAt"] isKindOfClass:[NSString class]] ? dictionary[@"runAt"] : @"document-end";
    if ([runAt isEqualToString:@"document-start"]) {
        file.runAt = PagePackRunAtDocumentStart;
    } else if ([runAt isEqualToString:@"document-idle"]) {
        file.runAt = PagePackRunAtDocumentIdle;
    } else {
        file.runAt = PagePackRunAtDocumentEnd;
    }
    if (dictionary[@"mainFrameOnly"] != nil) {
        file.mainFrameOnly = [dictionary[@"mainFrameOnly"] boolValue];
    }
    return file;
}

- (id)copyWithZone:(NSZone *)zone {
    PagePackFile *copy = [[[self class] allocWithZone:zone] init];
    copy.name = self.name;
    copy.kind = self.kind;
    copy.runAt = self.runAt;
    copy.mainFrameOnly = self.mainFrameOnly;
    return copy;
}

@end

@implementation PagePack

+ (instancetype)packWithName:(NSString *)name matches:(NSArray<NSString *> *)matches {
    PagePack *pack = [[self alloc] init];
    pack.packID = [[NSUUID UUID] UUIDString];
    pack.name = name.length > 0 ? name : @"未命名插件";
    pack.enabled = YES;
    pack.matches = matches.count > 0 ? [matches copy] : @[@"*://*/*"];
    pack.excludes = @[];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    pack.createdAt = now;
    pack.updatedAt = now;
    PagePackFile *style = [PagePackFile fileWithName:@"style.css" kind:PagePackFileKindCSS];
    style.runAt = PagePackRunAtDocumentStart;
    pack.files = style ? @[style] : @[];
    return pack;
}

- (nullable PagePackFile *)fileNamed:(NSString *)name {
    for (PagePackFile *file in self.files) {
        if ([file.name isEqualToString:name]) {
            return file;
        }
    }
    return nil;
}

- (NSString *)matchSummary {
    if (self.matches.count == 0) {
        return @"无匹配规则";
    }
    if (self.matches.count == 1) {
        return self.matches.firstObject;
    }
    return [NSString stringWithFormat:@"%@ 等 %lu 条", self.matches.firstObject, (unsigned long)self.matches.count];
}

- (BOOL)hasDangerousMatch {
    for (NSString *pattern in self.matches) {
        NSString *p = pattern.lowercaseString;
        if ([p isEqualToString:@"*://*/*"] || [p isEqualToString:@"*://*/"] || [p isEqualToString:@"*"]) {
            return YES;
        }
    }
    return NO;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:self.files.count];
    for (PagePackFile *file in self.files) {
        [files addObject:[file dictionaryRepresentation]];
    }
    NSMutableDictionary *dict = [@{
        @"id": self.packID ?: @"",
        @"name": self.name ?: @"",
        @"enabled": @(self.enabled),
        @"matches": self.matches ?: @[],
        @"excludes": self.excludes ?: @[],
        @"files": files,
        @"createdAt": @(self.createdAt),
        @"updatedAt": @(self.updatedAt),
    } mutableCopy];
    if (self.version.length > 0) {
        dict[@"version"] = self.version;
    }
    if (self.packDescription.length > 0) {
        dict[@"description"] = self.packDescription;
    }
    if (self.author.length > 0) {
        dict[@"author"] = self.author;
    }
    if (self.sourceURL.length > 0) {
        dict[@"sourceURL"] = self.sourceURL;
    }
    return dict;
}

+ (nullable instancetype)packWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *packID = [dictionary[@"id"] isKindOfClass:[NSString class]] ? dictionary[@"id"] : nil;
    if (packID.length == 0) {
        return nil;
    }
    PagePack *pack = [[self alloc] init];
    pack.packID = packID;
    pack.name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : @"未命名插件";
    pack.version = [dictionary[@"version"] isKindOfClass:[NSString class]] ? dictionary[@"version"] : nil;
    pack.packDescription = [dictionary[@"description"] isKindOfClass:[NSString class]] ? dictionary[@"description"] : nil;
    pack.author = [dictionary[@"author"] isKindOfClass:[NSString class]] ? dictionary[@"author"] : nil;
    pack.sourceURL = [dictionary[@"sourceURL"] isKindOfClass:[NSString class]] ? dictionary[@"sourceURL"] : nil;
    pack.enabled = dictionary[@"enabled"] ? [dictionary[@"enabled"] boolValue] : YES;
    pack.matches = [dictionary[@"matches"] isKindOfClass:[NSArray class]] ? dictionary[@"matches"] : @[];
    pack.excludes = [dictionary[@"excludes"] isKindOfClass:[NSArray class]] ? dictionary[@"excludes"] : @[];
    pack.createdAt = [dictionary[@"createdAt"] doubleValue];
    pack.updatedAt = [dictionary[@"updatedAt"] doubleValue];
    NSMutableArray<PagePackFile *> *files = [NSMutableArray array];
    id rawFiles = dictionary[@"files"];
    if ([rawFiles isKindOfClass:[NSArray class]]) {
        for (id item in rawFiles) {
            PagePackFile *file = [PagePackFile fileWithDictionary:item];
            if (file) {
                [files addObject:file];
            }
        }
    }
    pack.files = files;
    return pack;
}

- (id)copyWithZone:(NSZone *)zone {
    PagePack *copy = [[[self class] allocWithZone:zone] init];
    copy.packID = self.packID;
    copy.name = self.name;
    copy.version = self.version;
    copy.packDescription = self.packDescription;
    copy.author = self.author;
    copy.sourceURL = self.sourceURL;
    copy.enabled = self.enabled;
    copy.matches = self.matches;
    copy.excludes = self.excludes;
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:self.files.count];
    for (PagePackFile *file in self.files) {
        [files addObject:[file copy]];
    }
    copy.files = files;
    copy.createdAt = self.createdAt;
    copy.updatedAt = self.updatedAt;
    return copy;
}

@end
