#import <Foundation/Foundation.h>
#import "PhoneNotificationItem.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PhoneNotificationInboxDidChangeNotification;

/// 手机通知收件箱本地持久化（Application Support JSON）。
@interface PhoneNotificationInboxStore : NSObject

+ (instancetype)sharedStore;

- (void)upsertMirrorPayload:(NSDictionary *)payload;
- (void)upsertOTPCode:(NSString *)code;

- (NSArray<PhoneNotificationItem *> *)itemsMatchingFilter:(nullable PhoneNotificationFilter *)filter;
- (nullable PhoneNotificationItem *)itemForID:(NSString *)itemID;
- (NSUInteger)unreadCount;
- (NSUInteger)itemCount;

- (void)setRead:(BOOL)read forId:(NSString *)itemID;
- (void)setPinned:(BOOL)pinned forId:(NSString *)itemID;
- (void)deleteId:(NSString *)itemID;
- (void)markAllRead;
- (void)purgeRead;
- (void)purgeAll;

- (void)setMuted:(BOOL)muted forPackage:(NSString *)packageName;
- (BOOL)isMutedPackage:(NSString *)packageName;
- (NSArray<NSString *> *)mutedPackages;

@end

NS_ASSUME_NONNULL_END
