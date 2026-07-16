#import "OCRCaptchaAdapter.h"
#import "CaptchaHelperBridge.h"
#import "CaptchaSessionLog.h"

@implementation OCRCaptchaAdapter

+ (void)recognizeImage:(NSImage *)image
            completion:(void (^)(NSString *, NSError *))completion {
    if (!image) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"OCRCaptcha"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"无图片"}]);
        }
        return;
    }
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"meo-captcha-ocr-%@.png", [[NSUUID UUID] UUIDString]]];
    NSData *png = [self PNGDataFromImage:image];
    if (!png || ![png writeToFile:tmp atomically:YES]) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"OCRCaptcha"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey: @"无法写入临时图片"}]);
        }
        return;
    }
    [self recognizeImageAtPath:tmp completion:^(NSString *text, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        if (completion) {
            completion(text, error);
        }
    }];
}

+ (void)recognizeImageAtPath:(NSString *)path
                  completion:(void (^)(NSString *, NSError *))completion {
    [CaptchaHelperBridge recognizeTextInImageAtPath:path completion:completion];
}

+ (NSData *)PNGDataFromImage:(NSImage *)image {
    NSRect rect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&rect context:nil hints:nil];
    if (!cg) {
        return nil;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

@end
