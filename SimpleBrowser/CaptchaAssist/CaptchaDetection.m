#import "CaptchaDetection.h"

@implementation CaptchaDetection

+ (instancetype)detectionFromMessageBody:(id)body pageURL:(NSString *)pageURL {
    if (![body isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)body;
    NSString *vendor = dict[@"vendor"];
    NSString *kind = dict[@"kind"];
    if (![vendor isKindOfClass:[NSString class]] || vendor.length == 0) {
        vendor = @"generic";
    }
    if (![kind isKindOfClass:[NSString class]] || kind.length == 0) {
        kind = @"unknown";
    }

    CaptchaDetection *d = [[CaptchaDetection alloc] init];
    d.vendor = vendor;
    d.kind = kind;
    d.confidence = [dict[@"confidence"] respondsToSelector:@selector(doubleValue)]
        ? [dict[@"confidence"] doubleValue]
        : 0.5;
    d.frameHint = [dict[@"frame"] isKindOfClass:[NSString class]] ? dict[@"frame"] : nil;
    d.detail = [dict[@"detail"] isKindOfClass:[NSString class]] ? dict[@"detail"] : nil;
    d.inputSelector = [dict[@"inputSelector"] isKindOfClass:[NSString class]] ? dict[@"inputSelector"] : nil;
    d.imageSelector = [dict[@"imageSelector"] isKindOfClass:[NSString class]] ? dict[@"imageSelector"] : nil;
    d.containerSelector = [dict[@"containerSelector"] isKindOfClass:[NSString class]] ? dict[@"containerSelector"] : nil;
    d.mathText = [dict[@"mathText"] isKindOfClass:[NSString class]] ? dict[@"mathText"] : nil;
    d.pageURL = pageURL;
    d.detectedAt = [NSDate date];
    d.rect = CGRectNull;

    id rectObj = dict[@"rect"];
    if ([rectObj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *r = (NSDictionary *)rectObj;
        CGFloat x = [r[@"x"] doubleValue];
        CGFloat y = [r[@"y"] doubleValue];
        CGFloat w = [r[@"w"] doubleValue];
        CGFloat h = [r[@"h"] doubleValue];
        if (w > 1 && h > 1) {
            d.rect = CGRectMake(x, y, w, h);
        }
    }
    return d;
}

- (id)copyWithZone:(NSZone *)zone {
    CaptchaDetection *c = [[CaptchaDetection allocWithZone:zone] init];
    c.vendor = self.vendor;
    c.kind = self.kind;
    c.confidence = self.confidence;
    c.rect = self.rect;
    c.frameHint = self.frameHint;
    c.pageURL = self.pageURL;
    c.detectedAt = self.detectedAt;
    c.detail = self.detail;
    c.inputSelector = self.inputSelector;
    c.imageSelector = self.imageSelector;
    c.containerSelector = self.containerSelector;
    c.mathText = self.mathText;
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [@{
        @"vendor": self.vendor ?: @"",
        @"kind": self.kind ?: @"",
        @"confidence": @(self.confidence),
        @"detectedAt": @([self.detectedAt timeIntervalSince1970]),
    } mutableCopy];
    if (self.pageURL) {
        d[@"pageURL"] = self.pageURL;
    }
    if (self.frameHint) {
        d[@"frame"] = self.frameHint;
    }
    if (self.detail) {
        d[@"detail"] = self.detail;
    }
    if (self.inputSelector) {
        d[@"inputSelector"] = self.inputSelector;
    }
    if (self.imageSelector) {
        d[@"imageSelector"] = self.imageSelector;
    }
    if (self.containerSelector) {
        d[@"containerSelector"] = self.containerSelector;
    }
    if (self.mathText) {
        d[@"mathText"] = self.mathText;
    }
    if (!CGRectIsNull(self.rect)) {
        d[@"rect"] = @{
            @"x": @(self.rect.origin.x),
            @"y": @(self.rect.origin.y),
            @"w": @(self.rect.size.width),
            @"h": @(self.rect.size.height),
        };
    }
    return d;
}

- (NSString *)summaryLabel {
    return [NSString stringWithFormat:@"%@ · %@", self.vendor, self.kind];
}

@end
