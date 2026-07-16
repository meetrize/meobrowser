#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCRCaptchaAdapter : NSObject

+ (void)recognizeImage:(NSImage *)image
            completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

+ (void)recognizeImageAtPath:(NSString *)path
                  completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
