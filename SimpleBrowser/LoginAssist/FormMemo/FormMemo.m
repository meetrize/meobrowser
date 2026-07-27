#import "FormMemo.h"

@implementation FormMemoField

+ (instancetype)fieldWithLabel:(NSString *)label selector:(NSString *)selector value:(NSString *)value {
    FormMemoField *field = [[self alloc] init];
    field.label = label.length > 0 ? label : @"字段";
    field.selector = selector ?: @"";
    field.value = value ?: @"";
    return field;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fieldID = [[NSUUID UUID] UUIDString];
        _label = @"";
        _selector = @"";
        _value = @"";
        _enabled = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    FormMemoField *copy = [[FormMemoField alloc] init];
    copy.fieldID = self.fieldID;
    copy.label = self.label;
    copy.selector = self.selector;
    copy.value = self.value;
    copy.enabled = self.enabled;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"fieldID": self.fieldID ?: @"",
        @"label": self.label ?: @"",
        @"selector": self.selector ?: @"",
        @"value": self.value ?: @"",
        @"enabled": @(self.enabled),
    };
}

+ (instancetype)fieldWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *fieldID = dictionary[@"fieldID"];
    if (![fieldID isKindOfClass:[NSString class]] || fieldID.length == 0) {
        fieldID = [[NSUUID UUID] UUIDString];
    }
    FormMemoField *field = [[self alloc] init];
    field.fieldID = fieldID;
    NSString *label = dictionary[@"label"];
    field.label = [label isKindOfClass:[NSString class]] ? label : @"";
    NSString *selector = dictionary[@"selector"];
    field.selector = [selector isKindOfClass:[NSString class]] ? selector : @"";
    NSString *value = dictionary[@"value"];
    field.value = [value isKindOfClass:[NSString class]] ? value : @"";
    if (dictionary[@"enabled"] != nil) {
        field.enabled = [dictionary[@"enabled"] boolValue];
    } else {
        field.enabled = YES;
    }
    return field;
}

@end

@implementation FormMemo

+ (instancetype)memoWithHost:(NSString *)host title:(NSString *)title {
    FormMemo *memo = [[self alloc] init];
    memo.title = title.length > 0 ? title : host;
    memo.host = host.lowercaseString ?: @"";
    return memo;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoID = [[NSUUID UUID] UUIDString];
        _title = @"";
        _host = @"";
        _isDefault = NO;
        _fields = @[];
        _waitTimeoutMs = 8000;
        _updatedAt = [NSDate date].timeIntervalSince1970;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    FormMemo *copy = [[FormMemo alloc] init];
    copy.memoID = self.memoID;
    copy.title = self.title;
    copy.host = self.host;
    copy.pathPrefix = self.pathPrefix;
    copy.isDefault = self.isDefault;
    NSMutableArray<FormMemoField *> *fields = [NSMutableArray arrayWithCapacity:self.fields.count];
    for (FormMemoField *field in self.fields) {
        [fields addObject:[field copy]];
    }
    copy.fields = fields;
    copy.waitTimeoutMs = self.waitTimeoutMs;
    copy.updatedAt = self.updatedAt;
    return copy;
}

- (NSArray<FormMemoField *> *)enabledFields {
    NSMutableArray<FormMemoField *> *enabled = [NSMutableArray array];
    for (FormMemoField *field in self.fields) {
        if (field.enabled && field.selector.length > 0) {
            [enabled addObject:field];
        }
    }
    return enabled;
}

- (BOOL)matchesURL:(NSURL *)url {
    if (!url || self.host.length == 0) {
        return NO;
    }
    if (url.isFileURL) {
        if (![self.host isEqualToString:@"file"] && ![self.host isEqualToString:@"localhost"]) {
            return NO;
        }
        if (self.pathPrefix.length > 0) {
            NSString *path = url.path ?: @"";
            if (![path containsString:self.pathPrefix] && ![path hasPrefix:self.pathPrefix]) {
                return NO;
            }
        }
        return YES;
    }

    NSString *host = url.host.lowercaseString;
    if (host.length == 0) {
        return NO;
    }
    if (![host isEqualToString:self.host]) {
        NSString *strippedHost = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
        NSString *strippedSelf = [self.host hasPrefix:@"www."] ? [self.host substringFromIndex:4] : self.host;
        if (![strippedHost isEqualToString:strippedSelf]) {
            return NO;
        }
    }
    if (self.pathPrefix.length > 0) {
        NSString *path = url.path.length > 0 ? url.path : @"/";
        if (![path hasPrefix:self.pathPrefix]) {
            return NO;
        }
    }
    return YES;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *fieldDicts = [NSMutableArray arrayWithCapacity:self.fields.count];
    for (FormMemoField *field in self.fields) {
        [fieldDicts addObject:[field dictionaryRepresentation]];
    }
    NSMutableDictionary *dict = [@{
        @"memoID": self.memoID ?: @"",
        @"title": self.title ?: @"",
        @"host": self.host ?: @"",
        @"isDefault": @(self.isDefault),
        @"fields": fieldDicts,
        @"waitTimeoutMs": @(self.waitTimeoutMs > 0 ? self.waitTimeoutMs : 8000),
        @"updatedAt": @(self.updatedAt),
    } mutableCopy];
    if (self.pathPrefix.length > 0) {
        dict[@"pathPrefix"] = self.pathPrefix;
    }
    return dict;
}

+ (instancetype)memoWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *memoID = dictionary[@"memoID"];
    NSString *host = dictionary[@"host"];
    if (![memoID isKindOfClass:[NSString class]] || memoID.length == 0) {
        return nil;
    }
    if (![host isKindOfClass:[NSString class]] || host.length == 0) {
        return nil;
    }

    FormMemo *memo = [[self alloc] init];
    memo.memoID = memoID;
    memo.host = host.lowercaseString;
    NSString *title = dictionary[@"title"];
    memo.title = [title isKindOfClass:[NSString class]] && title.length > 0 ? title : host;
    memo.isDefault = [dictionary[@"isDefault"] boolValue];
    NSInteger timeout = [dictionary[@"waitTimeoutMs"] integerValue];
    memo.waitTimeoutMs = timeout > 0 ? timeout : 8000;
    memo.updatedAt = [dictionary[@"updatedAt"] doubleValue];
    if (memo.updatedAt <= 0) {
        memo.updatedAt = [NSDate date].timeIntervalSince1970;
    }
    NSString *pathPrefix = dictionary[@"pathPrefix"];
    memo.pathPrefix = [pathPrefix isKindOfClass:[NSString class]] ? pathPrefix : nil;

    NSMutableArray<FormMemoField *> *fields = [NSMutableArray array];
    id rawFields = dictionary[@"fields"];
    if ([rawFields isKindOfClass:[NSArray class]]) {
        for (id item in rawFields) {
            FormMemoField *field = [FormMemoField fieldWithDictionary:item];
            if (field) {
                [fields addObject:field];
            }
        }
    }
    memo.fields = fields;
    return memo;
}

@end
