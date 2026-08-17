#import "BrowserTextTranslationService.h"

@interface BrowserTextTranslationService ()
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation BrowserTextTranslationService

+ (instancetype)sharedService {
    static BrowserTextTranslationService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserTextTranslationService alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 20.0;
        config.timeoutIntervalForResource = 45.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            @"Accept": @"*/*",
        };
        _urlSession = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (NSString *)normalizedTargetLocaleIdentifier:(NSString *)localeID {
    NSString *lower = localeID.lowercaseString ?: @"";
    if ([lower hasPrefix:@"zh-hans"] || [lower isEqualToString:@"zh-cn"] || [lower isEqualToString:@"zh"]) {
        return @"zh-CN";
    }
    if ([lower hasPrefix:@"zh-hant"] || [lower isEqualToString:@"zh-tw"] || [lower isEqualToString:@"zh-hk"]) {
        return @"zh-TW";
    }
    NSArray<NSString *> *parts = [localeID componentsSeparatedByString:@"-"];
    return parts.firstObject.length > 0 ? parts.firstObject : @"zh-CN";
}

- (BOOL)shouldTranslateText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        return NO;
    }
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    if ([trimmed rangeOfCharacterFromSet:letters].location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (BOOL)isSuitableForPresentationTranslation:(NSString *)text {
    NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\\s+"
                                                            withString:@" "
                                                               options:NSRegularExpressionSearch
                                                                 range:NSMakeRange(0, text.length ?: 0)]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0) {
        return NO;
    }
    NSString *lower = normalized.lowercaseString;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"www."]) {
        return NO;
    }
    // Pure domain / site label: cnbc.com, news.bbc.co.uk
    NSRegularExpression *domainRE =
        [NSRegularExpression regularExpressionWithPattern:
         @"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+/?$"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:nil];
    if (domainRE && [domainRE numberOfMatchesInString:normalized options:0 range:NSMakeRange(0, normalized.length)] > 0) {
        return NO;
    }
    if (normalized.length < 12) {
        unichar last = [normalized characterAtIndex:normalized.length - 1];
        BOOL endsWithPunct = (last == '.' || last == '!' || last == '?' || last == 0x2026 ||
                              last == 0x3002 || last == 0xFF01 || last == 0xFF1F);
        BOOL hasSpaceAndLetter = ([normalized rangeOfString:@" "].location != NSNotFound &&
                                  [normalized rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound);
        if (!endsWithPunct && !hasSpaceAndLetter) {
            return NO;
        }
    }
    return [self shouldTranslateText:normalized];
}

- (void)translateText:(NSString *)text
         targetLocale:(NSString *)targetLocale
           completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    if (text.length == 0) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }
    NSString *tl = [self normalizedTargetLocaleIdentifier:targetLocale];
    [self translateTextUsingGoogle:text targetLocale:tl completion:^(NSString *translated, NSError *error) {
        if (translated.length > 0) {
            if (completion) {
                completion(translated, nil);
            }
            return;
        }
        [self translateTextUsingLingva:text targetLocale:tl completion:completion];
        (void)error;
    }];
}

- (void)translateTexts:(NSArray<NSString *> *)texts
          targetLocale:(NSString *)targetLocale
           concurrency:(NSUInteger)concurrency
            completion:(void (^)(NSArray<NSString *> *, NSUInteger))completion {
    if (texts.count == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], 0);
            });
        }
        return;
    }
    NSUInteger limit = MAX(1, concurrency);
    NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSUInteger i = 0; i < texts.count; i++) {
        [results addObject:@""];
    }
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t limiter = dispatch_semaphore_create((long)limit);
    __block NSUInteger failureCount = 0;

    for (NSUInteger i = 0; i < texts.count; i++) {
        NSString *text = texts[i];
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_semaphore_wait(limiter, DISPATCH_TIME_FOREVER);
            [self translateText:text targetLocale:targetLocale completion:^(NSString *translated, NSError *error) {
                if (translated.length > 0) {
                    @synchronized (results) {
                        results[i] = translated;
                    }
                } else {
                    @synchronized (results) {
                        failureCount += 1;
                    }
                    (void)error;
                }
                dispatch_semaphore_signal(limiter);
                dispatch_group_leave(group);
            }];
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) {
            completion([results copy], failureCount);
        }
    });
}

#pragma mark - Backends

- (void)translateTextUsingGoogle:(NSString *)text
                    targetLocale:(NSString *)targetLocale
                      completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://translate.googleapis.com/translate_a/single"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"client" value:@"gtx"],
        [NSURLQueryItem queryItemWithName:@"sl" value:@"auto"],
        [NSURLQueryItem queryItemWithName:@"tl" value:targetLocale],
        [NSURLQueryItem queryItemWithName:@"dt" value:@"t"],
        [NSURLQueryItem queryItemWithName:@"q" value:text],
    ];
    NSURL *url = components.URL;
    if (url == nil) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"BrowserTextTranslationService" code:1 userInfo:nil]);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    if (text.length > 1200) {
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"client" value:@"gtx"],
            [NSURLQueryItem queryItemWithName:@"sl" value:@"auto"],
            [NSURLQueryItem queryItemWithName:@"tl" value:targetLocale],
            [NSURLQueryItem queryItemWithName:@"dt" value:@"t"],
        ];
        request = [NSMutableURLRequest requestWithURL:components.URL];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/x-www-form-urlencoded;charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        NSString *encodedQ = [self formEncodeString:text];
        request.HTTPBody = [[NSString stringWithFormat:@"q=%@", encodedQ] dataUsingEncoding:NSUTF8StringEncoding];
    }

    [[self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        NSString *translated = [self parseGoogleTranslateResponse:data];
        if (completion) {
            completion(translated, translated.length > 0 ? nil : [NSError errorWithDomain:@"BrowserTextTranslationService" code:2 userInfo:nil]);
        }
        (void)response;
    }] resume];
}

- (NSString *)formEncodeString:(NSString *)string {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

- (nullable NSString *)parseGoogleTranslateResponse:(NSData *)data {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSArray class]] || [json count] == 0) {
        return nil;
    }
    id segments = json[0];
    if (![segments isKindOfClass:[NSArray class]]) {
        return nil;
    }
    NSMutableString *result = [NSMutableString string];
    for (id segment in segments) {
        if (![segment isKindOfClass:[NSArray class]] || [segment count] == 0) {
            continue;
        }
        id piece = segment[0];
        if ([piece isKindOfClass:[NSString class]]) {
            [result appendString:(NSString *)piece];
        }
    }
    return result.length > 0 ? result : nil;
}

- (void)translateTextUsingLingva:(NSString *)text
                    targetLocale:(NSString *)targetLocale
                      completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSString *tl = targetLocale;
    if ([tl isEqualToString:@"zh-CN"]) {
        tl = @"zh";
    } else if ([tl isEqualToString:@"zh-TW"]) {
        tl = @"zh_HANT";
    }
    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    if (encoded.length == 0) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }
    NSString *urlString = [NSString stringWithFormat:@"https://lingva.ml/api/v1/auto/%@/%@", tl, encoded];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }
    [[self.urlSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *translated = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            id value = json[@"translation"];
            if ([value isKindOfClass:[NSString class]]) {
                translated = value;
            }
        }
        if (completion) {
            completion(translated, translated.length > 0 ? nil : [NSError errorWithDomain:@"BrowserTextTranslationService" code:3 userInfo:nil]);
        }
        (void)response;
    }] resume];
}

@end
