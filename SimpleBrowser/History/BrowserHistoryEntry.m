#import "BrowserHistoryEntry.h"

@implementation BrowserHistoryEntry

+ (instancetype)entryWithURL:(NSString *)url
                       title:(NSString *)title
                    deviceId:(NSString *)deviceId {
    BrowserHistoryEntry *entry = [[self alloc] init];
    entry.entryID = [[NSUUID UUID] UUIDString];
    entry.url = url ?: @"";
    entry.title = title.length > 0 ? title : (url ?: @"");
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    entry.visitTime = now;
    entry.visitCount = 1;
    entry.updatedAt = now;
    entry.deviceId = deviceId ?: @"";
    entry.deleted = NO;
    return entry;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entryID = [[NSUUID UUID] UUIDString];
        _url = @"";
        _title = @"";
        _deviceId = @"";
        _visitCount = 1;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *url = dictionary[@"url"];
    if (![url isKindOfClass:[NSString class]] || url.length == 0) {
        return nil;
    }
    self = [self init];
    if (self) {
        NSString *entryID = dictionary[@"id"];
        if ([entryID isKindOfClass:[NSString class]] && entryID.length > 0) {
            _entryID = [entryID copy];
        }
        _url = [url copy];
        NSString *title = dictionary[@"title"];
        _title = [title isKindOfClass:[NSString class]] && title.length > 0 ? [title copy] : [_url copy];
        id visitTime = dictionary[@"visitTime"];
        if ([visitTime respondsToSelector:@selector(doubleValue)]) {
            _visitTime = [visitTime doubleValue];
        }
        id visitCount = dictionary[@"visitCount"];
        if ([visitCount respondsToSelector:@selector(integerValue)]) {
            _visitCount = MAX(1, [visitCount integerValue]);
        }
        id updatedAt = dictionary[@"updatedAt"];
        if ([updatedAt respondsToSelector:@selector(doubleValue)]) {
            _updatedAt = [updatedAt doubleValue];
        } else {
            _updatedAt = _visitTime;
        }
        NSString *deviceId = dictionary[@"deviceId"];
        _deviceId = [deviceId isKindOfClass:[NSString class]] ? [deviceId copy] : @"";
        id deleted = dictionary[@"deleted"];
        if ([deleted respondsToSelector:@selector(boolValue)]) {
            _deleted = [deleted boolValue];
        }
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.entryID ?: @"",
        @"url": self.url ?: @"",
        @"title": self.title ?: @"",
        @"visitTime": @((long long)self.visitTime),
        @"visitCount": @(self.visitCount),
        @"updatedAt": @((long long)self.updatedAt),
        @"deviceId": self.deviceId ?: @"",
        @"deleted": @(self.deleted),
    };
}

- (NSString *)displayHost {
    NSURL *url = [NSURL URLWithString:self.url];
    NSString *host = url.host.length > 0 ? url.host : self.url;
    if ([host.lowercaseString hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return host ?: @"";
}

- (id)copyWithZone:(NSZone *)zone {
    BrowserHistoryEntry *copy = [[[self class] allocWithZone:zone] init];
    copy.entryID = self.entryID;
    copy.url = self.url;
    copy.title = self.title;
    copy.visitTime = self.visitTime;
    copy.visitCount = self.visitCount;
    copy.updatedAt = self.updatedAt;
    copy.deviceId = self.deviceId;
    copy.deleted = self.deleted;
    return copy;
}

@end
