#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class CaptchaDetection;

NS_ASSUME_NONNULL_BEGIN

@interface CaptchaSessionLog : NSObject

+ (NSURL *)sessionsRootDirectory;

/// 写入一次会话：meta.json + 可选 image.png；返回会话目录。
+ (nullable NSURL *)writeSessionWithDetection:(nullable CaptchaDetection *)detection
                                       image:(nullable NSImage *)image
                                       note:(nullable NSString *)note
                                      error:(NSError * _Nullable * _Nullable)outError;

+ (void)pruneOldSessionsKeeping:(NSInteger)maxCount;

@end

NS_ASSUME_NONNULL_END
