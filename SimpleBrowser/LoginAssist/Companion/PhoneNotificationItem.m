#import "PhoneNotificationItem.h"

@implementation PhoneNotificationFilter
@end

@implementation PhoneNotificationItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemID = @"";
        _packageName = @"";
        _appLabel = @"";
        _title = @"";
        _body = @"";
        _kind = PhoneNotificationItemKindGeneral;
        _postTimeMs = 0;
        _receivedAt = [NSDate date];
        _read = NO;
        _pinned = NO;
        _source = PhoneNotificationItemSourceMirror;
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"id": self.itemID ?: @"",
        @"packageName": self.packageName ?: @"",
        @"appLabel": self.appLabel ?: @"",
        @"title": self.title ?: @"",
        @"body": self.body ?: @"",
        @"kind": self.kind == PhoneNotificationItemKindOTP ? @"otp" : @"general",
        @"postTimeMs": @(self.postTimeMs),
        @"receivedAt": @([self.receivedAt timeIntervalSince1970]),
        @"read": @(self.read),
        @"pinned": @(self.pinned),
        @"source": self.source == PhoneNotificationItemSourceOTPSynthetic ? @"otp_synthetic" : @"mirror",
    } mutableCopy];
    if (self.otpCode.length > 0) {
        dict[@"otpCode"] = self.otpCode;
    }
    if (self.inlineIconHash.length > 0) {
        dict[@"inlineIconHash"] = self.inlineIconHash;
    }
    return dict;
}

+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *itemID = [self stringFrom:dictionary[@"id"]];
    if (itemID.length == 0) {
        return nil;
    }
    PhoneNotificationItem *item = [[self alloc] init];
    item.itemID = itemID;
    item.packageName = [self stringFrom:dictionary[@"packageName"]];
    item.appLabel = [self stringFrom:dictionary[@"appLabel"]];
    item.title = [self stringFrom:dictionary[@"title"]];
    item.body = [self stringFrom:dictionary[@"body"]];
    NSString *kind = [self stringFrom:dictionary[@"kind"]];
    item.kind = [kind isEqualToString:@"otp"] ? PhoneNotificationItemKindOTP : PhoneNotificationItemKindGeneral;
    item.otpCode = [self stringFrom:dictionary[@"otpCode"]];
    if (item.otpCode.length == 0) {
        item.otpCode = nil;
    }
    item.inlineIconHash = [self stringFrom:dictionary[@"inlineIconHash"]];
    if (item.inlineIconHash.length == 0) {
        item.inlineIconHash = nil;
    }
    item.postTimeMs = [dictionary[@"postTimeMs"] respondsToSelector:@selector(longLongValue)]
        ? [dictionary[@"postTimeMs"] longLongValue] : 0;
    NSTimeInterval received = [dictionary[@"receivedAt"] respondsToSelector:@selector(doubleValue)]
        ? [dictionary[@"receivedAt"] doubleValue] : 0;
    item.receivedAt = received > 0 ? [NSDate dateWithTimeIntervalSince1970:received] : [NSDate date];
    item.read = [dictionary[@"read"] boolValue];
    item.pinned = [dictionary[@"pinned"] boolValue];
    NSString *source = [self stringFrom:dictionary[@"source"]];
    item.source = [source isEqualToString:@"otp_synthetic"]
        ? PhoneNotificationItemSourceOTPSynthetic
        : PhoneNotificationItemSourceMirror;
    return item;
}

+ (NSString *)stringFrom:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

@end
