#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString *OTPInboxSource NS_TYPED_EXTENSIBLE_ENUM;
extern OTPInboxSource const OTPInboxSourceCompanion;
extern OTPInboxSource const OTPInboxSourcePaste;
extern OTPInboxSource const OTPInboxSourceClipboard;
extern OTPInboxSource const OTPInboxSourceMock;

extern NSNotificationName const OTPInboxDidReceiveCodeNotification;
/// userInfo: source, waiting, buffered, copiedToClipboard (NSNumber bool)

typedef void (^OTPInboxWaitCompletion)(NSString * _Nullable code, NSError * _Nullable error);

/// 进程内 OTP 收件箱：Companion / 粘贴 / 剪贴板 / Mock 的单一出口。
@interface OTPInbox : NSObject

@property (nonatomic, assign) NSTimeInterval ttlSeconds; // 默认 120

+ (instancetype)sharedInbox;

/// 提交验证码。返回 YES 表示已接受（可能立即唤醒 waiter）。
- (BOOL)submitCode:(NSString *)code
            source:(OTPInboxSource)source
         timestamp:(NSTimeInterval)timestamp
             error:(NSError * _Nullable * _Nullable)error;

- (void)waitForCodeWithTimeout:(NSTimeInterval)timeout
                    completion:(OTPInboxWaitCompletion)completion;

- (void)cancelWait;

/// 从文本中提取最后一组 4～8 位数字；无则 nil。
+ (nullable NSString *)extractOTPFromText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
