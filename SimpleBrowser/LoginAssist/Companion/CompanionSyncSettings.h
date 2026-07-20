#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CompanionSyncSettings : NSObject

+ (instancetype)sharedSettings;

/// 总开关默认 NO
@property (nonatomic, assign) BOOL syncEnabled;
/// 打开总开关后快捷方式默认 YES
@property (nonatomic, assign) BOOL syncShortcuts;
@property (nonatomic, assign) BOOL syncHistory;
@property (nonatomic, assign) BOOL syncBookmarks;
@property (nonatomic, assign) NSTimeInterval lastSyncAt;
@property (nonatomic, assign) long long epoch;

- (long long)bumpEpoch;

@end

NS_ASSUME_NONNULL_END
