#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface CaptchaDetection : NSObject <NSCopying>

@property (nonatomic, copy) NSString *vendor;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) double confidence;
@property (nonatomic, assign) CGRect rect; // CSS 像素，相对视口；无元素时为 CGRectNull
@property (nonatomic, copy, nullable) NSString *frameHint;
@property (nonatomic, copy, nullable) NSString *pageURL;
@property (nonatomic, strong) NSDate *detectedAt;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, copy, nullable) NSString *inputSelector;
@property (nonatomic, copy, nullable) NSString *imageSelector;
@property (nonatomic, copy, nullable) NSString *containerSelector;
@property (nonatomic, copy, nullable) NSString *mathText;

+ (nullable instancetype)detectionFromMessageBody:(id)body pageURL:(nullable NSString *)pageURL;

- (NSDictionary *)dictionaryRepresentation;
- (NSString *)summaryLabel;

@end

NS_ASSUME_NONNULL_END
