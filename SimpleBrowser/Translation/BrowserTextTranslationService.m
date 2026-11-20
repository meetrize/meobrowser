#import "BrowserTextTranslationService.h"
#import "BrowserTranslationPreferences.h"
#import "BrowserSystemURLSession.h"

NSErrorDomain const BrowserTextTranslationErrorDomain = @"BrowserTextTranslationService";
NSString * const BrowserTextTranslationHTTPStatusKey = @"BrowserTextTranslationHTTPStatus";

@interface BrowserTextTranslationService ()
@property (nonatomic, strong) NSURLSession *urlSession;
/// MTran 批量用更长超时，避免大页被 20s 掐断。
@property (nonatomic, strong) NSURLSession *mtranBatchSession;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *translationCache;
@end

@implementation BrowserTextTranslationService

/// 首屏优先批大小：先译完即可渐进上屏。
static const NSUInteger kMTranPriorityChunkSize = 36;
/// 后续批大小：单请求略大，减少往返。
static const NSUInteger kMTranFollowChunkSize = 72;
/// 后续批并行度（服务端多为单模型，2 足够）。
static const NSUInteger kMTranFollowParallelism = 2;
/// Index 公开 API 易限流，并发略降。
static const NSUInteger kIndexTranslateMinConcurrency = 8;
/// 限流命中多少次后停止继续发请求（公开 API 很敏感，1 次即停并提示续译）。
static const NSUInteger kIndexRateLimitAbortThreshold = 1;

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
        NSDictionary *headers = @{
            @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            @"Accept": @"*/*",
        };
        NSURLSessionConfiguration *config =
            [BrowserSystemURLSession ephemeralConfigurationWithRequestTimeout:20.0 resourceTimeout:45.0];
        config.HTTPAdditionalHeaders = headers;
        // Index-Translate / Google 并发路径共用；提高单主机连接上限以免信号量被连接池卡住。
        config.HTTPMaximumConnectionsPerHost = 16;
        _urlSession = [NSURLSession sessionWithConfiguration:config];

        NSURLSessionConfiguration *batchConfig =
            [BrowserSystemURLSession ephemeralConfigurationWithRequestTimeout:60.0 resourceTimeout:120.0];
        batchConfig.HTTPAdditionalHeaders = headers;
        batchConfig.HTTPMaximumConnectionsPerHost = 4;
        _mtranBatchSession = [NSURLSession sessionWithConfiguration:batchConfig];

        _translationCache = [[NSCache alloc] init];
        _translationCache.countLimit = 800;
    }
    return self;
}

- (NSString *)cacheKeyForText:(NSString *)text targetLocale:(NSString *)targetLocale {
    return [NSString stringWithFormat:@"%@\x1F%@", targetLocale ?: @"", text ?: @""];
}

- (nullable NSString *)cachedTranslationForText:(NSString *)text targetLocale:(NSString *)targetLocale {
    if (text.length == 0) {
        return nil;
    }
    return [self.translationCache objectForKey:[self cacheKeyForText:text targetLocale:targetLocale]];
}

- (void)storeCachedTranslation:(NSString *)translated
                       forText:(NSString *)text
                  targetLocale:(NSString *)targetLocale {
    if (translated.length == 0 || text.length == 0) {
        return;
    }
    [self.translationCache setObject:translated
                              forKey:[self cacheKeyForText:text targetLocale:targetLocale]];
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

/// MTranServer 使用 BCP-47（zh-Hans / zh-Hant）。
- (NSString *)mtranTargetLocaleFromNormalized:(NSString *)targetLocale {
    if ([targetLocale isEqualToString:@"zh-CN"]) {
        return @"zh-Hans";
    }
    if ([targetLocale isEqualToString:@"zh-TW"]) {
        return @"zh-Hant";
    }
    return targetLocale.length > 0 ? targetLocale : @"zh-Hans";
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

- (BOOL)looksAlreadyChineseTranslated:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        return NO;
    }
    NSUInteger cjk = 0;
    NSUInteger latin = 0;
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar c = [trimmed characterAtIndex:i];
        if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
            cjk += 1;
        } else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            latin += 1;
        }
    }
    if (cjk == 0) {
        return NO;
    }
    // 中文明显占优，视为已译，续译时跳过。
    return cjk >= 4 && cjk * 2 >= latin;
}

+ (NSString *)userFacingSummaryForBatchError:(NSError *)error {
    if (error == nil) {
        return nil;
    }
    if ([error.domain isEqualToString:BrowserTextTranslationErrorDomain]) {
        if (error.code == BrowserTextTranslationErrorRateLimited) {
            return @"翻译接口限流";
        }
        if (error.code == BrowserTextTranslationErrorServiceUnavailable) {
            return @"翻译服务暂时不可用";
        }
    }
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        if (error.code == NSURLErrorTimedOut) {
            return @"翻译请求超时";
        }
        if (error.code == NSURLErrorNotConnectedToInternet ||
            error.code == NSURLErrorNetworkConnectionLost) {
            return @"网络连接失败";
        }
    }
    NSString *desc = error.localizedDescription;
    return desc.length > 0 ? desc : @"翻译失败";
}

- (NSError *)indexTranslateErrorForHTTPStatus:(NSInteger)status bodySnippet:(NSString *)bodySnippet {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[BrowserTextTranslationHTTPStatusKey] = @(status);
    NSString *lower = bodySnippet.lowercaseString ?: @"";
    BOOL looksRateLimited = (status == 429)
        || [lower containsString:@"rate limit"]
        || [lower containsString:@"too many"]
        || [lower containsString:@"限流"]
        || [lower containsString:@"频率"];
    if (looksRateLimited || status == 429) {
        info[NSLocalizedDescriptionKey] = @"翻译接口访问过于频繁，已被限流";
        return [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                   code:BrowserTextTranslationErrorRateLimited
                               userInfo:info];
    }
    if (status == 503 || status == 502 || status == 500) {
        info[NSLocalizedDescriptionKey] = @"翻译服务暂时不可用";
        return [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                   code:BrowserTextTranslationErrorServiceUnavailable
                               userInfo:info];
    }
    if (status >= 400) {
        info[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"翻译接口错误（HTTP %ld）", (long)status];
        return [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                   code:BrowserTextTranslationErrorGeneric
                               userInfo:info];
    }
    return [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                               code:BrowserTextTranslationErrorEmptyResult
                           userInfo:@{ NSLocalizedDescriptionKey: @"未返回译文" }];
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

- (BOOL)usesMTranProvider {
    return [[BrowserTranslationPreferences sharedPreferences].provider
            isEqualToString:BrowserTranslationProviderMTran];
}

- (BOOL)usesIndexTranslateProvider {
    return [[BrowserTranslationPreferences sharedPreferences].provider
            isEqualToString:BrowserTranslationProviderIndexTranslate];
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
    if ([self usesIndexTranslateProvider]) {
        [self translateTextUsingIndexTranslate:text targetLocale:tl completion:completion];
        return;
    }
    if ([self usesMTranProvider]) {
        [self translateTextUsingMTran:text targetLocale:tl completion:completion];
        return;
    }
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
            completion:(void (^)(NSArray<NSString *> *, NSUInteger, NSError *))completion {
    [self translateTexts:texts
            targetLocale:targetLocale
             concurrency:concurrency
                progress:nil
              completion:completion];
}

- (void)translateTexts:(NSArray<NSString *> *)texts
          targetLocale:(NSString *)targetLocale
           concurrency:(NSUInteger)concurrency
              progress:(void (^)(NSArray<NSString *> *))progress
            completion:(void (^)(NSArray<NSString *> *, NSUInteger, NSError *))completion {
    if (texts.count == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], 0, nil);
            });
        }
        return;
    }

    if ([self usesMTranProvider]) {
        [self translateTextsUsingMTranBatch:texts
                               targetLocale:[self normalizedTargetLocaleIdentifier:targetLocale]
                                   progress:progress
                                 completion:^(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount) {
            if (completion) {
                NSError *batchError = nil;
                if (failureCount > 0 && failureCount >= translatedOrEmpty.count) {
                    batchError = [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                                     code:BrowserTextTranslationErrorServiceUnavailable
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"翻译服务暂时不可用" }];
                } else if (failureCount > 0) {
                    batchError = [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                                     code:BrowserTextTranslationErrorGeneric
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"部分段落未译出" }];
                }
                completion(translatedOrEmpty, failureCount, batchError);
            }
        }];
        return;
    }

    // Index-Translate：有限并发 + 限流早停；progress 逐步回传以便 Pipeline 渐进上屏。
    NSUInteger limit = MAX(1, concurrency);
    if ([self usesIndexTranslateProvider]) {
        // 公开 API 易限流：并发封顶，避免一次打爆。
        limit = MIN(MAX(limit, 4), kIndexTranslateMinConcurrency);
    }
    NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSUInteger i = 0; i < texts.count; i++) {
        [results addObject:@""];
    }
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t limiter = dispatch_semaphore_create((long)limit);
    __block NSUInteger failureCount = 0;
    __block NSUInteger rateLimitHits = 0;
    __block BOOL abortRemaining = NO;
    __block NSError *firstBatchError = nil;
    NSObject *lock = [[NSObject alloc] init];
    __block NSUInteger completedSinceProgress = 0;
    __block NSUInteger totalCompleted = 0;
    __block BOOL progressFlushScheduled = NO;

    void (^flushProgress)(BOOL) = ^(BOOL force) {
        if (!progress) {
            return;
        }
        NSArray<NSString *> *snapshot = nil;
        @synchronized (lock) {
            if (!force && completedSinceProgress == 0) {
                return;
            }
            if (!force && totalCompleted > 1 && completedSinceProgress < 3) {
                return;
            }
            completedSinceProgress = 0;
            snapshot = [results copy];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(snapshot);
        });
    };

    void (^scheduleProgress)(void) = ^{
        if (!progress) {
            return;
        }
        BOOL shouldRunNow = NO;
        @synchronized (lock) {
            if (totalCompleted == 1) {
                shouldRunNow = YES;
            } else if (completedSinceProgress >= 3) {
                shouldRunNow = YES;
            } else if (!progressFlushScheduled) {
                progressFlushScheduled = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                               dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    @synchronized (lock) {
                        progressFlushScheduled = NO;
                    }
                    flushProgress(YES);
                });
            }
        }
        if (shouldRunNow) {
            flushProgress(totalCompleted == 1);
        }
    };

    for (NSUInteger i = 0; i < texts.count; i++) {
        NSString *text = texts[i];
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            BOOL shouldAbort = NO;
            @synchronized (lock) {
                shouldAbort = abortRemaining;
            }
            if (shouldAbort) {
                @synchronized (lock) {
                    failureCount += 1;
                    completedSinceProgress += 1;
                    totalCompleted += 1;
                }
                scheduleProgress();
                dispatch_group_leave(group);
                return;
            }
            dispatch_semaphore_wait(limiter, DISPATCH_TIME_FOREVER);
            @synchronized (lock) {
                shouldAbort = abortRemaining;
            }
            if (shouldAbort) {
                @synchronized (lock) {
                    failureCount += 1;
                    completedSinceProgress += 1;
                    totalCompleted += 1;
                }
                scheduleProgress();
                dispatch_semaphore_signal(limiter);
                dispatch_group_leave(group);
                return;
            }
            [self translateText:text targetLocale:targetLocale completion:^(NSString *translated, NSError *error) {
                @synchronized (lock) {
                    if (translated.length > 0) {
                        results[i] = translated;
                    } else {
                        failureCount += 1;
                        BOOL isRate = [error.domain isEqualToString:BrowserTextTranslationErrorDomain]
                            && error.code == BrowserTextTranslationErrorRateLimited;
                        if (isRate) {
                            rateLimitHits += 1;
                            if (rateLimitHits >= kIndexRateLimitAbortThreshold) {
                                abortRemaining = YES;
                            }
                        }
                        if (error != nil
                            && (firstBatchError == nil
                                || (isRate && firstBatchError.code != BrowserTextTranslationErrorRateLimited))) {
                            firstBatchError = error;
                        } else if (error == nil && firstBatchError == nil) {
                            firstBatchError = [NSError errorWithDomain:BrowserTextTranslationErrorDomain
                                                                  code:BrowserTextTranslationErrorEmptyResult
                                                              userInfo:@{ NSLocalizedDescriptionKey: @"未返回译文" }];
                        }
                    }
                    completedSinceProgress += 1;
                    totalCompleted += 1;
                }
                scheduleProgress();
                dispatch_semaphore_signal(limiter);
                dispatch_group_leave(group);
            }];
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        flushProgress(YES);
        if (completion) {
            NSArray<NSString *> *finalResults = nil;
            NSUInteger failures = 0;
            NSError *batchError = nil;
            @synchronized (lock) {
                finalResults = [results copy];
                failures = failureCount;
                batchError = firstBatchError;
            }
            completion(finalResults, failures, batchError);
        }
    });
}

#pragma mark - Index-Translate

/// Index-Translate 语言码 → 提示词中的中文语种名（与 call_api.py LANG_NAMES 对齐）。
- (NSString *)indexTranslateLanguageNameForLocale:(NSString *)targetLocale {
    NSString *lower = targetLocale.lowercaseString ?: @"";
    if ([lower hasPrefix:@"zh"]) {
        return @"中文";
    }
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"en": @"英语",
            @"de": @"德语",
            @"fr": @"法语",
            @"es": @"西班牙语",
            @"ja": @"日语",
            @"ko": @"韩语",
            @"pt": @"葡萄牙语",
            @"ru": @"俄语",
            @"ar": @"阿拉伯语",
            @"it": @"意大利语",
            @"nl": @"荷兰语",
            @"pl": @"波兰语",
            @"ro": @"罗马尼亚语",
            @"sv": @"瑞典语",
            @"tr": @"土耳其语",
            @"hi": @"印地语",
            @"vi": @"越南语",
            @"th": @"泰语",
            @"id": @"印尼语",
            @"ms": @"马来语",
            @"uk": @"乌克兰语",
            @"fa": @"波斯语",
            @"cs": @"捷克语",
            @"el": @"希腊语",
            @"da": @"丹麦语",
            @"hu": @"匈牙利语",
            @"fi": @"芬兰语",
            @"no": @"书面挪威语",
            @"nb": @"书面挪威语",
            @"sk": @"斯洛伐克语",
            @"bg": @"保加利亚语",
        };
    });
    NSArray<NSString *> *parts = [lower componentsSeparatedByString:@"-"];
    NSString *primary = parts.firstObject.length > 0 ? parts.firstObject : @"zh";
    return map[primary] ?: @"中文";
}

- (NSString *)indexTranslatePromptForText:(NSString *)text targetLocale:(NSString *)targetLocale {
    NSString *langName = [self indexTranslateLanguageNameForLocale:targetLocale];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [NSString stringWithFormat:
            @"请将以下文本翻译为%@，直接输出翻译结果，不要进行任何解释。\n\n%@",
            langName, trimmed];
}

- (NSString *)stripIndexTranslateThinking:(NSString *)text {
    if (text.length == 0) {
        return text;
    }
    NSString *result = text;
    NSRange close = [result rangeOfString:@"</think>"];
    if (close.location != NSNotFound) {
        result = [result substringFromIndex:NSMaxRange(close)];
    }
    NSString *trimmed = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasPrefix:@"<think>"]) {
        trimmed = [[trimmed substringFromIndex:@"<think>".length]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return trimmed;
}

- (nullable NSURL *)indexTranslateChatCompletionsURL {
    NSString *base = [[BrowserTranslationPreferences sharedPreferences] normalizedAPIBaseURL];
    if (base.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/chat/completions", base]];
}

- (void)applyIndexTranslateAuthToRequest:(NSMutableURLRequest *)request {
    // 公开 API 经 WAF，必须带官方客户端 UA；自建服务同样兼容。
    [request setValue:@"Index-Translate-Client/1.0" forHTTPHeaderField:@"User-Agent"];
    NSString *token = [BrowserTranslationPreferences sharedPreferences].apiToken;
    if (token.length == 0) {
        return;
    }
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
}

- (void)translateTextUsingIndexTranslate:(NSString *)text
                            targetLocale:(NSString *)targetLocale
                              completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSString *cached = [self cachedTranslationForText:text targetLocale:targetLocale];
    if (cached.length > 0) {
        if (completion) {
            completion(cached, nil);
        }
        return;
    }

    NSURL *url = [self indexTranslateChatCompletionsURL];
    if (url == nil) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"BrowserTextTranslationService" code:20 userInfo:nil]);
        }
        return;
    }

    BrowserTranslationPreferences *prefs = BrowserTranslationPreferences.sharedPreferences;
    NSString *model = prefs.model.length > 0 ? prefs.model : BrowserTranslationDefaultIndexTranslateModel;
    NSString *prompt = [self indexTranslatePromptForText:text targetLocale:targetLocale];
    NSUInteger maxTokens = MIN(4096, MAX(256, (NSUInteger)(text.length * 2 + 64)));

    NSDictionary *body = @{
        @"model": model,
        @"messages": @[
            @{ @"role": @"user", @"content": prompt },
        ],
        @"temperature": @0.0,
        @"max_tokens": @(maxTokens),
        @"stream": @NO,
        @"chat_template_kwargs": @{ @"enable_thinking": @NO },
    };
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (bodyData == nil) {
        if (completion) {
            completion(nil, jsonError);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [self applyIndexTranslateAuthToRequest:request];
    request.HTTPBody = bodyData;

    __weak typeof(self) weakSelf = self;
    [[self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            status = [(NSHTTPURLResponse *)response statusCode];
        }
        NSString *bodyText = data.length > 0
            ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"")
            : @"";
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        if (status >= 400 || data.length == 0) {
            NSUInteger snipLen = MIN((NSUInteger)240, bodyText.length);
            NSString *snippet = snipLen > 0 ? [bodyText substringToIndex:snipLen] : @"";
            if (completion) {
                completion(nil, [weakSelf indexTranslateErrorForHTTPStatus:(status > 0 ? status : 502)
                                                              bodySnippet:snippet]);
            }
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        // 有些网关 200 但仍返回 error 对象。
        if ([json isKindOfClass:[NSDictionary class]]) {
            id errObj = json[@"error"];
            if ([errObj isKindOfClass:[NSDictionary class]] || [errObj isKindOfClass:[NSString class]]) {
                NSString *snippet = [errObj isKindOfClass:[NSString class]]
                    ? (NSString *)errObj
                    : ([errObj description] ?: bodyText);
                if (completion) {
                    completion(nil, [weakSelf indexTranslateErrorForHTTPStatus:(status > 0 ? status : 429)
                                                                  bodySnippet:snippet]);
                }
                return;
            }
        }
        NSString *translated = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            id choices = json[@"choices"];
            if ([choices isKindOfClass:[NSArray class]] && [choices count] > 0) {
                id first = choices[0];
                if ([first isKindOfClass:[NSDictionary class]]) {
                    id message = first[@"message"];
                    if ([message isKindOfClass:[NSDictionary class]]) {
                        id content = message[@"content"];
                        if ([content isKindOfClass:[NSString class]]) {
                            translated = [weakSelf stripIndexTranslateThinking:content];
                        }
                    }
                }
            }
        }
        if (translated.length > 0) {
            [weakSelf storeCachedTranslation:translated forText:text targetLocale:targetLocale];
        }
        if (completion) {
            completion(translated, translated.length > 0
                       ? nil
                       : [weakSelf indexTranslateErrorForHTTPStatus:status bodySnippet:bodyText]);
        }
    }] resume];
}

#pragma mark - MTranServer

- (nullable NSURL *)mtranURLWithPath:(NSString *)path {
    NSString *base = [[BrowserTranslationPreferences sharedPreferences] normalizedAPIBaseURL];
    if (base.length == 0 || path.length == 0) {
        return nil;
    }
    NSString *joined = [NSString stringWithFormat:@"%@%@", base, path];
    return [NSURL URLWithString:joined];
}

- (void)applyMTranAuthToRequest:(NSMutableURLRequest *)request {
    NSString *token = [BrowserTranslationPreferences sharedPreferences].apiToken;
    if (token.length == 0) {
        return;
    }
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
}

- (void)translateTextUsingMTran:(NSString *)text
                   targetLocale:(NSString *)targetLocale
                     completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSString *cached = [self cachedTranslationForText:text targetLocale:targetLocale];
    if (cached.length > 0) {
        if (completion) {
            completion(cached, nil);
        }
        return;
    }
    NSURL *url = [self mtranURLWithPath:@"/translate"];
    if (url == nil) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"BrowserTextTranslationService" code:10 userInfo:nil]);
        }
        return;
    }
    NSDictionary *body = @{
        @"from": @"auto",
        @"to": [self mtranTargetLocaleFromNormalized:targetLocale],
        @"text": text,
        @"html": @NO,
    };
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (bodyData == nil) {
        if (completion) {
            completion(nil, jsonError);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [self applyMTranAuthToRequest:request];
    request.HTTPBody = bodyData;

    __weak typeof(self) weakSelf = self;
    [[self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *translated = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            id value = json[@"result"];
            if ([value isKindOfClass:[NSString class]]) {
                translated = value;
            }
        }
        if (translated.length > 0) {
            [weakSelf storeCachedTranslation:translated forText:text targetLocale:targetLocale];
        }
        if (completion) {
            completion(translated, translated.length > 0 ? nil : [NSError errorWithDomain:@"BrowserTextTranslationService" code:11 userInfo:nil]);
        }
        (void)response;
    }] resume];
}

/// 去重 → 缓存命中 → 首屏优先批 → 后续并行批；progress 逐步回填展开后的全文结果。
- (void)translateTextsUsingMTranBatch:(NSArray<NSString *> *)texts
                         targetLocale:(NSString *)targetLocale
                             progress:(void (^)(NSArray<NSString *> *))progress
                           completion:(void (^)(NSArray<NSString *> *, NSUInteger))completion {
    NSMutableArray<NSString *> *uniqueTexts = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *uniqueIndexByText = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber *> *originalToUnique = [NSMutableArray arrayWithCapacity:texts.count];

    for (NSString *raw in texts) {
        NSString *text = raw ?: @"";
        NSNumber *existing = uniqueIndexByText[text];
        if (existing != nil) {
            [originalToUnique addObject:existing];
            continue;
        }
        NSNumber *idx = @(uniqueTexts.count);
        uniqueIndexByText[text] = idx;
        [uniqueTexts addObject:text];
        [originalToUnique addObject:idx];
    }

    NSMutableArray<NSString *> *uniqueResults = [NSMutableArray arrayWithCapacity:uniqueTexts.count];
    NSMutableArray<NSNumber *> *pendingUniqueIndexes = [NSMutableArray array];
    for (NSUInteger i = 0; i < uniqueTexts.count; i++) {
        NSString *cached = [self cachedTranslationForText:uniqueTexts[i] targetLocale:targetLocale];
        if (cached.length > 0) {
            [uniqueResults addObject:cached];
        } else {
            [uniqueResults addObject:@""];
            [pendingUniqueIndexes addObject:@(i)];
        }
    }

    NSArray<NSString *> * (^expandResults)(void) = ^{
        NSMutableArray<NSString *> *expanded = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSNumber *uidx in originalToUnique) {
            NSUInteger i = uidx.unsignedIntegerValue;
            [expanded addObject:(i < uniqueResults.count ? uniqueResults[i] : @"")];
        }
        return [expanded copy];
    };

    void (^emitProgress)(void) = ^{
        if (!progress) {
            return;
        }
        NSArray<NSString *> *partial = expandResults();
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(partial);
        });
    };

    void (^finishAll)(NSUInteger) = ^(NSUInteger failureCount) {
        NSArray<NSString *> *finalResults = expandResults();
        NSUInteger failures = failureCount;
        if (failures == 0) {
            for (NSString *piece in finalResults) {
                if (piece.length == 0) {
                    failures += 1;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progress) {
                progress(finalResults);
            }
            if (completion) {
                completion(finalResults, failures);
            }
        });
    };

    if (pendingUniqueIndexes.count == 0) {
        emitProgress();
        finishAll(0);
        return;
    }

    // 已有缓存时先推一版，首屏可立刻上屏。
    if (pendingUniqueIndexes.count < uniqueTexts.count) {
        emitProgress();
    }

    NSMutableArray<NSArray<NSNumber *> *> *chunks = [NSMutableArray array];
    NSUInteger cursor = 0;
    NSUInteger firstSize = MIN(kMTranPriorityChunkSize, pendingUniqueIndexes.count);
    if (firstSize > 0) {
        [chunks addObject:[pendingUniqueIndexes subarrayWithRange:NSMakeRange(0, firstSize)]];
        cursor = firstSize;
    }
    while (cursor < pendingUniqueIndexes.count) {
        NSUInteger len = MIN(kMTranFollowChunkSize, pendingUniqueIndexes.count - cursor);
        [chunks addObject:[pendingUniqueIndexes subarrayWithRange:NSMakeRange(cursor, len)]];
        cursor += len;
    }

    __weak typeof(self) weakSelf = self;
    __block NSUInteger remainingChunks = chunks.count;
    __block NSUInteger aggregateFailures = 0;
    NSObject *lock = [[NSObject alloc] init];

    void (^handleChunkIndexes)(NSArray<NSNumber *> *, NSArray<NSString *> *, NSUInteger) =
        ^(NSArray<NSNumber *> *uniqueIndexes, NSArray<NSString *> *chunkResults, NSUInteger chunkFailures) {
            typeof(self) self = weakSelf;
            @synchronized (lock) {
                aggregateFailures += chunkFailures;
                for (NSUInteger i = 0; i < uniqueIndexes.count; i++) {
                    NSUInteger uidx = uniqueIndexes[i].unsignedIntegerValue;
                    NSString *piece = (i < chunkResults.count) ? (chunkResults[i] ?: @"") : @"";
                    if (uidx < uniqueResults.count) {
                        uniqueResults[uidx] = piece;
                    }
                    if (piece.length > 0 && self && uidx < uniqueTexts.count) {
                        [self storeCachedTranslation:piece
                                             forText:uniqueTexts[uidx]
                                        targetLocale:targetLocale];
                    }
                }
                emitProgress();
                remainingChunks = (remainingChunks > 0) ? (remainingChunks - 1) : 0;
                if (remainingChunks == 0) {
                    finishAll(aggregateFailures);
                }
            }
        };

    if (chunks.count == 0) {
        finishAll(0);
        return;
    }

    // 首屏批串行优先；其余批有限并行。
    NSArray<NSNumber *> *priorityIndexes = chunks.firstObject;
    NSArray<NSString *> *priorityTexts = [self textsForUniqueIndexes:priorityIndexes inUniqueTexts:uniqueTexts];
    [self translateChunkUsingMTranBatch:priorityTexts
                           targetLocale:targetLocale
                             completion:^(NSArray<NSString *> *chunkResults, NSUInteger chunkFailures) {
        handleChunkIndexes(priorityIndexes, chunkResults, chunkFailures);

        if (chunks.count <= 1) {
            return;
        }
        typeof(self) self = weakSelf;
        if (!self) {
            return;
        }
        NSArray<NSArray<NSNumber *> *> *followChunks = [chunks subarrayWithRange:NSMakeRange(1, chunks.count - 1)];
        dispatch_semaphore_t limiter = dispatch_semaphore_create((long)MAX(1, kMTranFollowParallelism));
        for (NSArray<NSNumber *> *indexChunk in followChunks) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                dispatch_semaphore_wait(limiter, DISPATCH_TIME_FOREVER);
                NSArray<NSString *> *chunkTexts = [self textsForUniqueIndexes:indexChunk inUniqueTexts:uniqueTexts];
                [self translateChunkUsingMTranBatch:chunkTexts
                                       targetLocale:targetLocale
                                         completion:^(NSArray<NSString *> *chunkResults, NSUInteger chunkFailures) {
                    handleChunkIndexes(indexChunk, chunkResults, chunkFailures);
                    dispatch_semaphore_signal(limiter);
                }];
            });
        }
    }];
}

- (NSArray<NSString *> *)textsForUniqueIndexes:(NSArray<NSNumber *> *)indexes
                                 inUniqueTexts:(NSArray<NSString *> *)uniqueTexts {
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:indexes.count];
    for (NSNumber *num in indexes) {
        NSUInteger i = num.unsignedIntegerValue;
        [out addObject:(i < uniqueTexts.count ? uniqueTexts[i] : @"")];
    }
    return out;
}

- (void)translateChunkUsingMTranBatch:(NSArray<NSString *> *)texts
                         targetLocale:(NSString *)targetLocale
                           completion:(void (^)(NSArray<NSString *> *results, NSUInteger failureCount))completion {
    NSURL *url = [self mtranURLWithPath:@"/translate/batch"];
    if (url == nil || texts.count == 0) {
        NSMutableArray<NSString *> *empty = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSUInteger i = 0; i < texts.count; i++) {
            [empty addObject:@""];
        }
        if (completion) {
            completion(empty, texts.count);
        }
        return;
    }

    NSDictionary *body = @{
        @"from": @"auto",
        @"to": [self mtranTargetLocaleFromNormalized:targetLocale],
        @"texts": texts,
        @"html": @NO,
    };
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (bodyData == nil) {
        NSMutableArray<NSString *> *empty = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSUInteger i = 0; i < texts.count; i++) {
            [empty addObject:@""];
        }
        if (completion) {
            completion(empty, texts.count);
        }
        (void)jsonError;
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [self applyMTranAuthToRequest:request];
    request.HTTPBody = bodyData;

    [[self.mtranBatchSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSUInteger i = 0; i < texts.count; i++) {
            [out addObject:@""];
        }
        NSUInteger failures = texts.count;
        if (!error && data.length > 0) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *translatedList = nil;
            if ([json isKindOfClass:[NSDictionary class]]) {
                id value = json[@"results"];
                if ([value isKindOfClass:[NSArray class]]) {
                    translatedList = value;
                }
            }
            if (translatedList.count > 0) {
                failures = 0;
                for (NSUInteger i = 0; i < texts.count; i++) {
                    NSString *piece = @"";
                    if (i < translatedList.count && [translatedList[i] isKindOfClass:[NSString class]]) {
                        piece = translatedList[i];
                    }
                    out[i] = piece;
                    if (piece.length == 0) {
                        failures += 1;
                    }
                }
            }
        }
        if (completion) {
            completion(out, failures);
        }
        (void)response;
    }] resume];
}

#pragma mark - Google / Lingva

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
