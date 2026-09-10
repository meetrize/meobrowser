#import "BrowserScraperModels.h"

static NSString *MeoNonNullString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

@implementation BrowserScraperField

+ (instancetype)fieldWithDictionary:(NSDictionary *)dict {
    BrowserScraperField *field = [[self alloc] init];
    field.fieldID = MeoNonNullString(dict[@"id"]);
    if (field.fieldID.length == 0) {
        field.fieldID = [[NSUUID UUID] UUIDString];
    }
    field.enabled = dict[@"enabled"] == nil ? YES : [dict[@"enabled"] boolValue];
    field.name = MeoNonNullString(dict[@"name"]);
    field.kind = [self kindFromString:MeoNonNullString(dict[@"kind"])];
    field.path = MeoNonNullString(dict[@"path"]);
    NSString *attr = MeoNonNullString(dict[@"attribute"]);
    field.attribute = attr.length > 0 ? attr : nil;
    return field;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"id": self.fieldID ?: @"",
        @"enabled": @(self.enabled),
        @"name": self.name ?: @"",
        @"kind": [[self class] stringFromKind:self.kind],
        @"path": self.path ?: @"",
    } mutableCopy];
    if (self.attribute.length > 0) {
        dict[@"attribute"] = self.attribute;
    }
    return dict;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] fieldWithDictionary:[self dictionaryRepresentation]];
}

+ (NSString *)stringFromKind:(BrowserScraperFieldKind)kind {
    switch (kind) {
        case BrowserScraperFieldKindHref: return @"href";
        case BrowserScraperFieldKindSrc: return @"src";
        case BrowserScraperFieldKindAttribute: return @"attribute";
        case BrowserScraperFieldKindHTML: return @"html";
        default: return @"text";
    }
}

+ (BrowserScraperFieldKind)kindFromString:(NSString *)string {
    if ([string isEqualToString:@"href"]) return BrowserScraperFieldKindHref;
    if ([string isEqualToString:@"src"]) return BrowserScraperFieldKindSrc;
    if ([string isEqualToString:@"attribute"]) return BrowserScraperFieldKindAttribute;
    if ([string isEqualToString:@"html"]) return BrowserScraperFieldKindHTML;
    return BrowserScraperFieldKindText;
}

@end

@implementation BrowserScraperPagination

+ (instancetype)defaultPagination {
    BrowserScraperPagination *p = [[self alloc] init];
    p.type = BrowserScraperPaginationTypeNone;
    p.selector = @"";
    p.maxPages = 10;
    p.maxRows = 5000;
    p.pageDelayMs = 800;
    p.waitForSelector = @"";
    p.waitTimeoutMs = 15000;
    p.scrollStepPx = 800;
    p.scrollSettleMs = 600;
    return p;
}

+ (instancetype)paginationWithDictionary:(NSDictionary *)dict {
    BrowserScraperPagination *p = [self defaultPagination];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return p;
    }
    p.type = [self typeFromString:MeoNonNullString(dict[@"type"])];
    p.selector = MeoNonNullString(dict[@"selector"]);
    if (dict[@"maxPages"]) p.maxPages = MAX(1, [dict[@"maxPages"] integerValue]);
    if (dict[@"maxRows"]) p.maxRows = MAX(1, [dict[@"maxRows"] integerValue]);
    if (dict[@"pageDelayMs"]) p.pageDelayMs = MAX(0, [dict[@"pageDelayMs"] integerValue]);
    p.waitForSelector = MeoNonNullString(dict[@"waitForSelector"]);
    if (dict[@"waitTimeoutMs"]) p.waitTimeoutMs = MAX(0, [dict[@"waitTimeoutMs"] integerValue]);
    if (dict[@"scrollStepPx"]) p.scrollStepPx = MAX(1, [dict[@"scrollStepPx"] integerValue]);
    if (dict[@"scrollSettleMs"]) p.scrollSettleMs = MAX(0, [dict[@"scrollSettleMs"] integerValue]);
    return p;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"type": [[self class] stringFromType:self.type],
        @"selector": self.selector ?: @"",
        @"maxPages": @(self.maxPages),
        @"maxRows": @(self.maxRows),
        @"pageDelayMs": @(self.pageDelayMs),
        @"waitForSelector": self.waitForSelector ?: @"",
        @"waitTimeoutMs": @(self.waitTimeoutMs),
        @"scrollStepPx": @(self.scrollStepPx),
        @"scrollSettleMs": @(self.scrollSettleMs),
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] paginationWithDictionary:[self dictionaryRepresentation]];
}

+ (NSString *)stringFromType:(BrowserScraperPaginationType)type {
    switch (type) {
        case BrowserScraperPaginationTypeNextButton: return @"nextButton";
        case BrowserScraperPaginationTypePageNumbers: return @"pageNumbers";
        case BrowserScraperPaginationTypeLoadMore: return @"loadMore";
        case BrowserScraperPaginationTypeInfiniteScroll: return @"infiniteScroll";
        default: return @"none";
    }
}

+ (BrowserScraperPaginationType)typeFromString:(NSString *)string {
    if ([string isEqualToString:@"nextButton"]) return BrowserScraperPaginationTypeNextButton;
    if ([string isEqualToString:@"pageNumbers"]) return BrowserScraperPaginationTypePageNumbers;
    if ([string isEqualToString:@"loadMore"]) return BrowserScraperPaginationTypeLoadMore;
    if ([string isEqualToString:@"infiniteScroll"]) return BrowserScraperPaginationTypeInfiniteScroll;
    return BrowserScraperPaginationTypeNone;
}

@end

@implementation BrowserScraperMySQLConfig

+ (instancetype)configWithDictionary:(NSDictionary *)dict {
    BrowserScraperMySQLConfig *c = [[self alloc] init];
    c.host = MeoNonNullString(dict[@"host"]);
    if (c.host.length == 0) c.host = @"127.0.0.1";
    c.port = dict[@"port"] ? [dict[@"port"] integerValue] : 3306;
    c.database = MeoNonNullString(dict[@"database"]);
    c.user = MeoNonNullString(dict[@"user"]);
    c.passwordKeychainAccount = MeoNonNullString(dict[@"passwordKeychainAccount"]);
    c.table = MeoNonNullString(dict[@"table"]);
    NSString *mode = MeoNonNullString(dict[@"writeMode"]);
    if ([mode isEqualToString:@"replace"]) c.writeMode = BrowserScraperMySQLWriteModeReplace;
    else if ([mode isEqualToString:@"upsert"]) c.writeMode = BrowserScraperMySQLWriteModeUpsert;
    else c.writeMode = BrowserScraperMySQLWriteModeAppend;
    NSArray *keys = dict[@"upsertKeys"];
    c.upsertKeys = [keys isKindOfClass:[NSArray class]] ? [keys copy] : @[];
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    NSString *mode = @"append";
    if (self.writeMode == BrowserScraperMySQLWriteModeReplace) mode = @"replace";
    else if (self.writeMode == BrowserScraperMySQLWriteModeUpsert) mode = @"upsert";
    return @{
        @"host": self.host ?: @"",
        @"port": @(self.port),
        @"database": self.database ?: @"",
        @"user": self.user ?: @"",
        @"passwordKeychainAccount": self.passwordKeychainAccount ?: @"",
        @"table": self.table ?: @"",
        @"writeMode": mode,
        @"upsertKeys": self.upsertKeys ?: @[],
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] configWithDictionary:[self dictionaryRepresentation]];
}

@end

@implementation BrowserScraperSink

+ (instancetype)sinkWithDictionary:(NSDictionary *)dict {
    BrowserScraperSink *sink = [[self alloc] init];
    NSString *type = MeoNonNullString(dict[@"type"]);
    if ([type isEqualToString:@"csv"]) sink.type = BrowserScraperSinkTypeCSV;
    else if ([type isEqualToString:@"json"]) sink.type = BrowserScraperSinkTypeJSON;
    else if ([type isEqualToString:@"mysql"]) sink.type = BrowserScraperSinkTypeMySQL;
    else sink.type = BrowserScraperSinkTypeXLSX;
    id path = dict[@"filePath"];
    sink.filePath = [path isKindOfClass:[NSString class]] ? path : nil;
    id mysql = dict[@"mysql"];
    if ([mysql isKindOfClass:[NSDictionary class]]) {
        sink.mysql = [BrowserScraperMySQLConfig configWithDictionary:mysql];
    }
    return sink;
}

- (NSDictionary *)dictionaryRepresentation {
    NSString *type = @"xlsx";
    if (self.type == BrowserScraperSinkTypeCSV) type = @"csv";
    else if (self.type == BrowserScraperSinkTypeJSON) type = @"json";
    else if (self.type == BrowserScraperSinkTypeMySQL) type = @"mysql";
    NSMutableDictionary *dict = [@{ @"type": type } mutableCopy];
    dict[@"filePath"] = self.filePath ?: [NSNull null];
    dict[@"mysql"] = self.mysql ? [self.mysql dictionaryRepresentation] : [NSNull null];
    return dict;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] sinkWithDictionary:[self dictionaryRepresentation]];
}

@end

@implementation BrowserScraperSchedule

+ (instancetype)defaultSchedule {
    BrowserScraperSchedule *s = [[self alloc] init];
    s.enabled = NO;
    s.intervalMinutes = 60;
    return s;
}

+ (instancetype)scheduleWithDictionary:(NSDictionary *)dict {
    BrowserScraperSchedule *s = [self defaultSchedule];
    if (![dict isKindOfClass:[NSDictionary class]]) return s;
    s.enabled = [dict[@"enabled"] boolValue];
    if (dict[@"intervalMinutes"]) s.intervalMinutes = MAX(1, [dict[@"intervalMinutes"] integerValue]);
    if ([dict[@"startAt"] isKindOfClass:[NSNumber class]]) {
        s.startAt = [NSDate dateWithTimeIntervalSince1970:[dict[@"startAt"] doubleValue]];
    }
    if ([dict[@"endAt"] isKindOfClass:[NSNumber class]]) {
        s.endAt = [NSDate dateWithTimeIntervalSince1970:[dict[@"endAt"] doubleValue]];
    }
    NSString *label = MeoNonNullString(dict[@"launchAgentLabel"]);
    s.launchAgentLabel = label.length > 0 ? label : nil;
    return s;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"enabled": @(self.enabled),
        @"intervalMinutes": @(self.intervalMinutes),
        @"startAt": self.startAt ? @([self.startAt timeIntervalSince1970]) : [NSNull null],
        @"endAt": self.endAt ? @([self.endAt timeIntervalSince1970]) : [NSNull null],
        @"launchAgentLabel": self.launchAgentLabel ?: [NSNull null],
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] scheduleWithDictionary:[self dictionaryRepresentation]];
}

@end

@implementation BrowserScraperMatch

+ (instancetype)matchWithDictionary:(NSDictionary *)dict {
    BrowserScraperMatch *m = [[self alloc] init];
    NSArray *hosts = dict[@"hosts"];
    m.hosts = [hosts isKindOfClass:[NSArray class]] ? [hosts copy] : @[];
    NSString *contains = MeoNonNullString(dict[@"urlContains"]);
    m.urlContains = contains.length > 0 ? contains : nil;
    return m;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"hosts": self.hosts ?: @[],
        @"urlContains": self.urlContains ?: [NSNull null],
    };
}

- (BOOL)matchesURL:(NSURL *)url {
    if (!url) return NO;
    NSString *host = url.host.lowercaseString ?: @"";
    BOOL hostOK = self.hosts.count == 0;
    for (NSString *h in self.hosts) {
        NSString *allowed = h.lowercaseString;
        if ([host isEqualToString:allowed] || [host hasSuffix:[@"." stringByAppendingString:allowed]]) {
            hostOK = YES;
            break;
        }
    }
    if (!hostOK) return NO;
    if (self.urlContains.length > 0) {
        NSString *full = url.absoluteString ?: @"";
        if ([full rangeOfString:self.urlContains options:NSCaseInsensitiveSearch].location == NSNotFound) {
            return NO;
        }
    }
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] matchWithDictionary:[self dictionaryRepresentation]];
}

@end

@implementation BrowserScraperRecipe

+ (instancetype)blankRecipeNamed:(NSString *)name {
    BrowserScraperRecipe *r = [[self alloc] init];
    r.recipeID = [[NSUUID UUID] UUIDString];
    r.name = name.length > 0 ? name : @"未命名配方";
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    r.createdAt = now;
    r.updatedAt = now;
    r.match = [BrowserScraperMatch matchWithDictionary:@{}];
    r.mode = BrowserScraperModeTable;
    r.containerPath = @"";
    r.rowPath = @"";
    r.fields = @[];
    r.pagination = [BrowserScraperPagination defaultPagination];
    r.dedupeKeyFieldIds = @[];
    r.dropEmptyRows = YES;
    r.absoluteURLs = YES;
    r.session = BrowserScraperSessionReuseProfile;
    r.schedule = [BrowserScraperSchedule defaultSchedule];
    r.schedule.launchAgentLabel = [NSString stringWithFormat:@"com.example.MeoBrowser.scrape.%@", r.recipeID];
    r.sink = [BrowserScraperSink sinkWithDictionary:@{ @"type": @"xlsx" }];
    return r;
}

+ (instancetype)recipeWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    BrowserScraperRecipe *r = [[self alloc] init];
    r.recipeID = MeoNonNullString(dict[@"id"]);
    if (r.recipeID.length == 0) return nil;
    r.name = MeoNonNullString(dict[@"name"]);
    r.createdAt = [dict[@"createdAt"] doubleValue];
    r.updatedAt = [dict[@"updatedAt"] doubleValue];
    r.match = [BrowserScraperMatch matchWithDictionary:[dict[@"match"] isKindOfClass:[NSDictionary class]] ? dict[@"match"] : @{}];
    r.startURL = MeoNonNullString(dict[@"startURL"]);
    if (r.startURL.length == 0) r.startURL = nil;
    r.mode = [self modeFromString:MeoNonNullString(dict[@"mode"])];
    r.containerPath = MeoNonNullString(dict[@"containerPath"]);
    r.rowPath = MeoNonNullString(dict[@"rowPath"]);
    NSMutableArray *fields = [NSMutableArray array];
    id rawFields = dict[@"fields"];
    if ([rawFields isKindOfClass:[NSArray class]]) {
        for (id item in rawFields) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [fields addObject:[BrowserScraperField fieldWithDictionary:item]];
            }
        }
    }
    r.fields = fields;
    r.pagination = [BrowserScraperPagination paginationWithDictionary:
                    [dict[@"pagination"] isKindOfClass:[NSDictionary class]] ? dict[@"pagination"] : @{}];
    id dedupe = dict[@"dedupeKeyFieldIds"];
    r.dedupeKeyFieldIds = [dedupe isKindOfClass:[NSArray class]] ? [dedupe copy] : @[];
    r.dropEmptyRows = dict[@"dropEmptyRows"] == nil ? YES : [dict[@"dropEmptyRows"] boolValue];
    r.absoluteURLs = dict[@"absoluteURLs"] == nil ? YES : [dict[@"absoluteURLs"] boolValue];
    NSString *session = MeoNonNullString(dict[@"session"]);
    r.session = [session isEqualToString:@"ephemeral"] ? BrowserScraperSessionEphemeral : BrowserScraperSessionReuseProfile;
    r.schedule = [BrowserScraperSchedule scheduleWithDictionary:
                  [dict[@"schedule"] isKindOfClass:[NSDictionary class]] ? dict[@"schedule"] : @{}];
    if (r.schedule.launchAgentLabel.length == 0) {
        r.schedule.launchAgentLabel = [NSString stringWithFormat:@"com.example.MeoBrowser.scrape.%@", r.recipeID];
    }
    r.sink = [BrowserScraperSink sinkWithDictionary:
              [dict[@"sink"] isKindOfClass:[NSDictionary class]] ? dict[@"sink"] : @{ @"type": @"xlsx" }];
    return r;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *fields = [NSMutableArray array];
    for (BrowserScraperField *f in self.fields) {
        [fields addObject:[f dictionaryRepresentation]];
    }
    return @{
        @"id": self.recipeID ?: @"",
        @"name": self.name ?: @"",
        @"createdAt": @(self.createdAt),
        @"updatedAt": @(self.updatedAt),
        @"match": [self.match dictionaryRepresentation],
        @"startURL": self.startURL ?: [NSNull null],
        @"mode": [[self class] stringFromMode:self.mode],
        @"containerPath": self.containerPath ?: @"",
        @"rowPath": self.rowPath ?: @"",
        @"fields": fields,
        @"pagination": [self.pagination dictionaryRepresentation],
        @"dedupeKeyFieldIds": self.dedupeKeyFieldIds ?: @[],
        @"dropEmptyRows": @(self.dropEmptyRows),
        @"absoluteURLs": @(self.absoluteURLs),
        @"session": self.session == BrowserScraperSessionEphemeral ? @"ephemeral" : @"reuseProfile",
        @"schedule": [self.schedule dictionaryRepresentation],
        @"sink": [self.sink dictionaryRepresentation],
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] recipeWithDictionary:[self dictionaryRepresentation]];
}

+ (NSString *)stringFromMode:(BrowserScraperMode)mode {
    return mode == BrowserScraperModeScalar ? @"scalar" : @"table";
}

+ (BrowserScraperMode)modeFromString:(NSString *)string {
    return [string isEqualToString:@"scalar"] ? BrowserScraperModeScalar : BrowserScraperModeTable;
}

@end
