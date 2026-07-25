#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PhoneChatDirection) {
    PhoneChatDirectionIn = 0,
    PhoneChatDirectionOut = 1,
};

typedef NS_ENUM(NSInteger, PhoneChatOutboundStatus) {
    PhoneChatOutboundStatusNone = 0,
    PhoneChatOutboundStatusSending = 1,
    PhoneChatOutboundStatusSent = 2,
    PhoneChatOutboundStatusFailed = 3,
};

@interface PhoneChatThread : NSObject
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSDate *lastMessageAt;
@property (nonatomic, copy) NSString *lastPreview;
@property (nonatomic, assign) NSInteger unreadCount;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)threadWithDictionary:(NSDictionary *)dictionary;
@end

@interface PhoneChatMessage : NSObject
@property (nonatomic, copy) NSString *messageID;
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, assign) PhoneChatDirection direction;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSString *notificationID;
@property (nonatomic, copy, nullable) NSString *requestID;
@property (nonatomic, assign) PhoneChatOutboundStatus status;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)messageWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
