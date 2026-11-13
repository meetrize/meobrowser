#import "BrowserTextTranslationService.h"
#import "BrowserTranslationPreferences.h"
#import "BrowserSystemURLSession.h"

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
            completion:(void (^)(NSArray<NSString *> *, NSUInteger))completion {
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
            completion:(void (^)(NSArray<NSString *> *, NSUInteger))completion {
    if (texts.count == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], 0);
            });
        }
        return;
    }

    if ([self usesMTranProvider]) {
        [self translateTextsUsingMTranBatch:texts
                               targetLocale:[self normalizedTargetLocaleIdentifier:targetLocale]
                                   progress:progress
                                 completion:completion];
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
        if (progress) {
            progress([results copy]);
        }
        if (completion) {
            completion([results copy], failureCount);
        }
    });
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
