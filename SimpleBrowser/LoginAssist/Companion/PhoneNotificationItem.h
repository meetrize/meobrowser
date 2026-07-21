#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PhoneNotificationItemKind) {
    PhoneNotificationItemKindGeneral = 0,
    PhoneNotificationItemKindOTP = 1,
};

typedef NS_ENUM(NSInteger, PhoneNotificationItemSource) {
    PhoneNotificationItemSourceMirror = 0,
    PhoneNotificationItemSourceOTPSynthetic = 1,
};

typedef NS_ENUM(NSInteger, PhoneNotificationInboxBucket) {
    PhoneNotificationInboxBucketAll = 0,
    PhoneNotificationInboxBucketUnread = 1,
    PhoneNotificationInboxBucketOTP = 2,
    PhoneNotificationInboxBucketToday = 3,
    PhoneNotificationInboxBucketPinned = 4,
};

@interface PhoneNotificationFilter : NSObject
@property (nonatomic, assign) PhoneNotificationInboxBucket bucket;
@property (nonatomic, copy, nullable) NSString *query;
@property (nonatomic, copy, nullable) NSString *packageName;
@end

@interface PhoneNotificationItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy) NSString *appLabel;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, assign) PhoneNotificationItemKind kind;
@property (nonatomic, copy, nullable) NSString *otpCode;
@property (nonatomic, assign) long long postTimeMs;
@property (nonatomic, strong) NSDate *receivedAt;
@property (nonatomic, assign) BOOL read;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, assign) PhoneNotificationItemSource source;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
