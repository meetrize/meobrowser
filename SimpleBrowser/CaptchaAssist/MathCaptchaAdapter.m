#import "MathCaptchaAdapter.h"

@implementation MathCaptchaAdapter

+ (NSString *)solveMathText:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSString *normalized = [self normalizedMathString:text];
    if (normalized.length == 0) {
        return nil;
    }

    // 长文本中抽取首个「数字 运算符 数字」片段（面板可能含按钮/标签文案）
    NSError *error = nil;
    NSRegularExpression *extract = [NSRegularExpression regularExpressionWithPattern:@"(-?\\d+)([\\+\\-\\*/×÷xX＋－])(-?\\d+)"
                                                                               options:0
                                                                                 error:&error];
    if (!extract) {
        return nil;
    }
    NSTextCheckingResult *found = [extract firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
    if (!found || found.numberOfRanges < 4) {
        return nil;
    }
    NSString *expr = [normalized substringWithRange:found.range];
    return [self evaluateNormalizedExpression:expr];
}

+ (NSString *)evaluateNormalizedExpression:(NSString *)normalized {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(-?\\d+)([\\+\\-\\*/×÷xX＋－])(-?\\d+)$"
                                                                           options:0
                                                                             error:&error];
    if (!regex) {
        return nil;
    }
    NSTextCheckingResult *match = [regex firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
    if (!match || match.numberOfRanges < 4) {
        return nil;
    }

    NSInteger a = [[normalized substringWithRange:[match rangeAtIndex:1]] integerValue];
    NSString *op = [normalized substringWithRange:[match rangeAtIndex:2]];
    NSInteger b = [[normalized substringWithRange:[match rangeAtIndex:3]] integerValue];

    if ([op isEqualToString:@"+"] || [op isEqualToString:@"＋"]) {
        return [NSString stringWithFormat:@"%ld", (long)(a + b)];
    }
    if ([op isEqualToString:@"-"] || [op isEqualToString:@"－"] || [op isEqualToString:@"−"]) {
        return [NSString stringWithFormat:@"%ld", (long)(a - b)];
    }
    if ([op isEqualToString:@"*"] || [op isEqualToString:@"×"] || [op isEqualToString:@"x"] || [op isEqualToString:@"X"]) {
        return [NSString stringWithFormat:@"%ld", (long)(a * b)];
    }
    if ([op isEqualToString:@"/"] || [op isEqualToString:@"÷"]) {
        if (b == 0) {
            return nil;
        }
        if (a % b == 0) {
            return [NSString stringWithFormat:@"%ld", (long)(a / b)];
        }
        return [NSString stringWithFormat:@"%g", (double)a / (double)b];
    }
    return nil;
}

+ (NSString *)normalizedMathString:(NSString *)text {
    NSMutableString *s = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] mutableCopy];
    [s replaceOccurrencesOfString:@"？" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"?" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"=" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

@end
