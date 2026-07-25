#import "PhoneChatModels.h"

@implementation PhoneChatThread

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"threadId": self.threadID ?: @"",
        @"packageName": self.packageName ?: @"",
        @"title": self.title ?: @"",
        @"lastMessageAt": @((long long)(self.lastMessageAt.timeIntervalSince1970 * 1000.0)),
        @"lastPreview": self.lastPreview ?: @"",
        @"unreadCount": @(self.unreadCount),
    };
}

+ (instancetype)threadWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *tid = dictionary[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || tid.length == 0) {
        return nil;
    }
    PhoneChatThread *t = [[PhoneChatThread alloc] init];
    t.threadID = tid;
    t.packageName = [dictionary[@"packageName"] isKindOfClass:[NSString class]] ? dictionary[@"packageName"] : @"";
    t.title = [dictionary[@"title"] isKindOfClass:[NSString class]] ? dictionary[@"title"] : @"";
    long long ms = [dictionary[@"lastMessageAt"] respondsToSelector:@selector(longLongValue)]
        ? [dictionary[@"lastMessageAt"] longLongValue] : 0;
    t.lastMessageAt = ms > 0 ? [NSDate dateWithTimeIntervalSince1970:ms / 1000.0] : [NSDate date];
    t.lastPreview = [dictionary[@"lastPreview"] isKindOfClass:[NSString class]] ? dictionary[@"lastPreview"] : @"";
    t.unreadCount = [dictionary[@"unreadCount"] respondsToSelector:@selector(integerValue)]
        ? [dictionary[@"unreadCount"] integerValue] : 0;
    return t;
}

@end

@implementation PhoneChatMessage

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [@{
        @"messageId": self.messageID ?: @"",
        @"threadId": self.threadID ?: @"",
        @"direction": self.direction == PhoneChatDirectionOut ? @"out" : @"in",
        @"text": self.text ?: @"",
        @"createdAt": @((long long)(self.createdAt.timeIntervalSince1970 * 1000.0)),
        @"status": @(self.status),
    } mutableCopy];
    if (self.notificationID.length > 0) {
        d[@"notificationId"] = self.notificationID;
    }
    if (self.requestID.length > 0) {
        d[@"requestId"] = self.requestID;
    }
    return d;
}

+ (instancetype)messageWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *mid = dictionary[@"messageId"];
    NSString *tid = dictionary[@"threadId"];
    if (![mid isKindOfClass:[NSString class]] || mid.length == 0 ||
        ![tid isKindOfClass:[NSString class]] || tid.length == 0) {
        return nil;
    }
    PhoneChatMessage *m = [[PhoneChatMessage alloc] init];
    m.messageID = mid;
    m.threadID = tid;
    NSString *dir = dictionary[@"direction"];
    m.direction = ([dir isKindOfClass:[NSString class]] && [dir isEqualToString:@"out"])
        ? PhoneChatDirectionOut : PhoneChatDirectionIn;
    m.text = [dictionary[@"text"] isKindOfClass:[NSString class]] ? dictionary[@"text"] : @"";
    long long ms = [dictionary[@"createdAt"] respondsToSelector:@selector(longLongValue)]
        ? [dictionary[@"createdAt"] longLongValue] : 0;
    m.createdAt = ms > 0 ? [NSDate dateWithTimeIntervalSince1970:ms / 1000.0] : [NSDate date];
    m.notificationID = [dictionary[@"notificationId"] isKindOfClass:[NSString class]]
        ? dictionary[@"notificationId"] : nil;
    m.requestID = [dictionary[@"requestId"] isKindOfClass:[NSString class]]
        ? dictionary[@"requestId"] : nil;
    m.status = [dictionary[@"status"] respondsToSelector:@selector(integerValue)]
        ? (PhoneChatOutboundStatus)[dictionary[@"status"] integerValue]
        : PhoneChatOutboundStatusNone;
    return m;
}

@end
