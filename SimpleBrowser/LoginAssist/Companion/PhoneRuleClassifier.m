#import "PhoneRuleClassifier.h"

@implementation PhoneRuleClassifyResult
@end

@interface PhoneRuleClassifier ()
@property (nonatomic, copy) NSArray<NSDictionary *> *rules;
@property (nonatomic, copy) NSDictionary *fallback;
@end

@implementation PhoneRuleClassifier

+ (instancetype)sharedClassifier {
    static PhoneRuleClassifier *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
        [shared loadRules];
    });
    return shared;
}

- (void)loadRules {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"simple_rules"
                                                     ofType:@"json"
                                                inDirectory:@"PhoneRules"];
    if (path.length == 0) {
        path = [[NSBundle mainBundle] pathForResource:@"simple_rules" ofType:@"json"];
    }
    NSData *data = path.length > 0 ? [NSData dataWithContentsOfFile:path] : nil;
    if (data) {
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([root isKindOfClass:[NSDictionary class]]) {
            NSArray *rules = root[@"rules"];
            if ([rules isKindOfClass:[NSArray class]]) {
                self.rules = rules;
            }
            NSDictionary *fb = root[@"fallback"];
            if ([fb isKindOfClass:[NSDictionary class]]) {
                self.fallback = fb;
            }
        }
    }
    if (self.rules.count == 0) {
        self.rules = @[];
    }
    if (self.fallback.count == 0) {
        self.fallback = @{@"category": @"unknown", @"label": @"未知类型"};
    }
}

+ (NSString *)normalizedDigits:(NSString *)raw {
    if (raw.length == 0) {
        return @"";
    }
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }
    if ([digits hasPrefix:@"86"] && digits.length >= 13) {
        return [digits substringFromIndex:2];
    }
    if ([digits hasPrefix:@"0086"] && digits.length > 4) {
        return [digits substringFromIndex:4];
    }
    return digits;
}

- (PhoneRuleClassifyResult *)classifyNumber:(NSString *)number
                              presentation:(NSString *)presentation {
    PhoneRuleClassifyResult *result = [[PhoneRuleClassifyResult alloc] init];
    NSString *pres = presentation ?: @"";
    NSString *digits = [PhoneRuleClassifier normalizedDigits:number];

    for (NSDictionary *rule in self.rules) {
        if (![rule isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *when = rule[@"when"];
        if ([when isEqualToString:@"empty_or_restricted"]) {
            if (digits.length == 0 ||
                [pres isEqualToString:@"restricted"] ||
                [pres isEqualToString:@"unknown"]) {
                result.category = rule[@"category"] ?: @"private";
                result.label = rule[@"label"] ?: @"私人号码";
                return result;
            }
            continue;
        }
        if (digits.length == 0) {
            continue;
        }
        if ([when isEqualToString:@"prefix"]) {
            NSArray *prefixes = rule[@"prefix"];
            NSInteger minLen = [rule[@"minLen"] respondsToSelector:@selector(integerValue)]
                ? [rule[@"minLen"] integerValue] : 0;
            NSInteger maxLen = [rule[@"maxLen"] respondsToSelector:@selector(integerValue)]
                ? [rule[@"maxLen"] integerValue] : NSIntegerMax;
            if ((NSInteger)digits.length < minLen || (NSInteger)digits.length > maxLen) {
                continue;
            }
            for (id p in prefixes) {
                if (![p isKindOfClass:[NSString class]]) continue;
                if ([digits hasPrefix:(NSString *)p]) {
                    result.category = rule[@"category"] ?: @"unknown";
                    result.label = rule[@"label"] ?: @"";
                    return result;
                }
            }
            continue;
        }
        if ([when isEqualToString:@"length_in"]) {
            NSInteger minLen = [rule[@"minLen"] integerValue];
            NSInteger maxLen = [rule[@"maxLen"] integerValue];
            if ((NSInteger)digits.length >= minLen && (NSInteger)digits.length <= maxLen) {
                result.category = rule[@"category"] ?: @"hotline";
                result.label = rule[@"label"] ?: @"";
                return result;
            }
            continue;
        }
        if ([when isEqualToString:@"regex"]) {
            NSString *pattern = rule[@"pattern"];
            if (pattern.length == 0) continue;
            NSRegularExpression *re =
                [NSRegularExpression regularExpressionWithPattern:pattern
                                                          options:0
                                                            error:nil];
            if (!re) continue;
            NSRange full = NSMakeRange(0, digits.length);
            if ([re numberOfMatchesInString:digits options:0 range:full] > 0) {
                result.category = rule[@"category"] ?: @"unknown";
                result.label = rule[@"label"] ?: @"";
                return result;
            }
        }
    }

    result.category = self.fallback[@"category"] ?: @"unknown";
    result.label = self.fallback[@"label"] ?: @"未知类型";
    return result;
}

@end
