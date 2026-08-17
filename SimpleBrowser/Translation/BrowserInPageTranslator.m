#import "BrowserInPageTranslator.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface BrowserInPageTranslatorSession : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) NSString *targetLocale;
@property (nonatomic, strong) NSMutableArray *collectedItems;
@property (nonatomic, copy, nullable) void (^completion)(BOOL success, NSString * _Nullable errorMessage);
@property (nonatomic, assign) BOOL startFinished;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, strong, nullable) id retainedDelegate;
@end

@implementation BrowserInPageTranslatorSession
@end

@interface BrowserInPageTranslator ()
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserInPageTranslatorSession *> *sessionsByWebView;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation BrowserInPageTranslator

+ (instancetype)sharedTranslator {
    static BrowserInPageTranslator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserInPageTranslator alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionsByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                                   valueOptions:NSPointerFunctionsStrongMemory];
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

- (BOOL)isTranslatingWebView:(WKWebView *)webView {
    return webView != nil && [self.sessionsByWebView objectForKey:webView] != nil;
}

#pragma mark - Public

- (void)translateWebView:(WKWebView *)webView
  targetLocaleIdentifier:(NSString *)localeID
              completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (webView == nil || localeID.length == 0) {
        if (completion) {
            completion(NO, @"无法翻译此页面");
        }
        return;
    }
    if ([self isTranslatingWebView:webView]) {
        if (completion) {
            completion(NO, @"正在翻译中…");
        }
        return;
    }
    if (![webView respondsToSelector:NSSelectorFromString(@"_setTextManipulationDelegate:")]
        || ![webView respondsToSelector:NSSelectorFromString(@"_startTextManipulationsWithConfiguration:completion:")]
        || ![webView respondsToSelector:NSSelectorFromString(@"_completeTextManipulationForItems:completion:")]) {
        if (completion) {
            completion(NO, @"当前系统不支持页内翻译");
        }
        return;
    }

    BrowserInPageTranslatorSession *session = [[BrowserInPageTranslatorSession alloc] init];
    session.webView = webView;
    session.targetLocale = [self googleTargetForLocaleIdentifier:localeID];
    session.collectedItems = [NSMutableArray array];
    session.completion = completion;
    session.retainedDelegate = self;
    [self.sessionsByWebView setObject:session forKey:webView];

    ((void (*)(id, SEL, id))objc_msgSend)(webView, NSSelectorFromString(@"_setTextManipulationDelegate:"), self);

    Class confCls = NSClassFromString(@"_WKTextManipulationConfiguration");
    id configuration = confCls ? [confCls new] : nil;
    if (configuration && [configuration respondsToSelector:NSSelectorFromString(@"setIncludeSubframes:")]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, NSSelectorFromString(@"setIncludeSubframes:"), YES);
    }

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        webView,
        NSSelectorFromString(@"_startTextManipulationsWithConfiguration:completion:"),
        configuration,
        ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                WKWebView *strongWebView = weakWebView;
                if (!strongSelf || !strongWebView) {
                    return;
                }
                BrowserInPageTranslatorSession *current = [strongSelf.sessionsByWebView objectForKey:strongWebView];
                if (current == nil || current.completed) {
                    return;
                }
                current.startFinished = YES;
                [strongSelf translateCollectedItemsForSession:current];
            });
        });
}

#pragma mark - _WKTextManipulationDelegate

- (void)_webView:(WKWebView *)webView didFindTextManipulationItems:(NSArray *)items {
    BrowserInPageTranslatorSession *session = [self.sessionsByWebView objectForKey:webView];
    if (session == nil || session.completed || items.count == 0) {
        return;
    }
    [session.collectedItems addObjectsFromArray:items];
}

- (void)_webView:(WKWebView *)webView didFindTextManipulationItem:(id)item {
    if (item == nil) {
        return;
    }
    [self _webView:webView didFindTextManipulationItems:@[ item ]];
}

#pragma mark - Translate pipeline

- (void)translateCollectedItemsForSession:(BrowserInPageTranslatorSession *)session {
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }
    if (session.collectedItems.count == 0) {
        [self finishSession:session success:NO message:@"未找到可翻译文本"];
        return;
    }

    NSMutableArray<NSDictionary *> *jobs = [NSMutableArray array];
    for (id item in session.collectedItems) {
        NSArray *tokens = [item valueForKey:@"tokens"];
        if (![tokens isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSUInteger index = 0;
        for (id token in tokens) {
            BOOL excluded = NO;
            @try {
                excluded = [[token valueForKey:@"isExcluded"] boolValue];
            } @catch (__unused NSException *exception) {
                excluded = NO;
            }
            NSString *content = [token valueForKey:@"content"];
            if (!excluded && [content isKindOfClass:[NSString class]] && [self shouldTranslateText:content]) {
                [jobs addObject:@{
                    @"item": item,
                    @"tokenIndex": @(index),
                    @"text": content,
                }];
            }
            index += 1;
        }
    }

    if (jobs.count == 0) {
        [self finishSession:session success:NO message:@"未找到可翻译文本"];
        return;
    }

    NSMutableDictionary<NSNumber *, NSString *> *translatedByJob = [NSMutableDictionary dictionary];
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t limiter = dispatch_semaphore_create(6);
    __block NSUInteger failureCount = 0;

    for (NSUInteger jobIndex = 0; jobIndex < jobs.count; jobIndex++) {
        NSDictionary *job = jobs[jobIndex];
        NSString *text = job[@"text"];
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_semaphore_wait(limiter, DISPATCH_TIME_FOREVER);
            [self translateText:text
                 targetLocale:session.targetLocale
                   completion:^(NSString *translated, NSError *error) {
                       if (translated.length > 0) {
                           @synchronized (translatedByJob) {
                               translatedByJob[@(jobIndex)] = translated;
                           }
                       } else {
                           @synchronized (translatedByJob) {
                               failureCount += 1;
                           }
                           (void)error;
                       }
                       dispatch_semaphore_signal(limiter);
                       dispatch_group_leave(group);
                   }];
        });
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (translatedByJob.count == 0) {
            [strongSelf finishSession:session success:NO message:@"翻译服务暂时不可用"];
            return;
        }
        [strongSelf applyTranslations:translatedByJob
                                 jobs:jobs
                              session:session
                        failureCount:failureCount];
    });
}

- (void)applyTranslations:(NSDictionary<NSNumber *, NSString *> *)translatedByJob
                     jobs:(NSArray<NSDictionary *> *)jobs
                  session:(BrowserInPageTranslatorSession *)session
             failureCount:(NSUInteger)failureCount {
    (void)failureCount;
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }

    // item -> { tokenIndex -> translated }
    NSMapTable *perItem = [NSMapTable strongToStrongObjectsMapTable];
    [translatedByJob enumerateKeysAndObjectsUsingBlock:^(NSNumber *jobIndex, NSString *translated, BOOL *stop) {
        (void)stop;
        NSDictionary *job = jobs[jobIndex.unsignedIntegerValue];
        id item = job[@"item"];
        NSMutableDictionary *map = [perItem objectForKey:item];
        if (map == nil) {
            map = [NSMutableDictionary dictionary];
            [perItem setObject:map forKey:item];
        }
        map[job[@"tokenIndex"]] = translated;
    }];

    Class itemCls = NSClassFromString(@"_WKTextManipulationItem");
    Class tokCls = NSClassFromString(@"_WKTextManipulationToken");
    if (itemCls == Nil || tokCls == Nil) {
        [self finishSession:session success:NO message:@"当前系统不支持页内翻译"];
        return;
    }

    NSMutableArray *replacements = [NSMutableArray array];
    for (id item in session.collectedItems) {
        NSDictionary *tokenMap = [perItem objectForKey:item];
        if (tokenMap.count == 0) {
            continue;
        }
        NSArray *tokens = [item valueForKey:@"tokens"];
        NSMutableArray *newTokens = [NSMutableArray arrayWithCapacity:tokens.count];
        NSUInteger index = 0;
        for (id token in tokens) {
            id newToken = [tokCls new];
            [newToken setValue:[token valueForKey:@"identifier"] forKey:@"identifier"];
            BOOL excluded = NO;
            @try {
                excluded = [[token valueForKey:@"isExcluded"] boolValue];
            } @catch (__unused NSException *exception) {
                excluded = NO;
            }
            @try {
                [newToken setValue:@(excluded) forKey:@"excluded"];
            } @catch (__unused NSException *exception) {
            }
            NSString *content = tokenMap[@(index)];
            if (content == nil) {
                content = [token valueForKey:@"content"] ?: @"";
            }
            [newToken setValue:content forKey:@"content"];
            [newTokens addObject:newToken];
            index += 1;
        }
        id newItem = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [itemCls alloc],
            NSSelectorFromString(@"initWithIdentifier:tokens:"),
            [item valueForKey:@"identifier"],
            newTokens);
        if (newItem) {
            [replacements addObject:newItem];
        }
    }

    if (replacements.count == 0) {
        [self finishSession:session success:NO message:@"翻译结果为空"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        webView,
        NSSelectorFromString(@"_completeTextManipulationForItems:completion:"),
        replacements,
        ^(NSArray *errors) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                BOOL ok = (errors == nil || errors.count == 0 || replacements.count > errors.count);
                [strongSelf finishSession:session
                                  success:ok
                                  message:ok ? nil : @"部分内容未能替换"];
            });
        });
}

- (void)finishSession:(BrowserInPageTranslatorSession *)session
              success:(BOOL)success
              message:(NSString *)message {
    if (session.completed) {
        return;
    }
    session.completed = YES;
    WKWebView *webView = session.webView;
    if (webView != nil) {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(webView, NSSelectorFromString(@"_setTextManipulationDelegate:"), nil);
        } @catch (__unused NSException *exception) {
        }
        [self.sessionsByWebView removeObjectForKey:webView];
    }
    void (^completion)(BOOL, NSString *) = session.completion;
    session.completion = nil;
    session.retainedDelegate = nil;
    if (completion) {
        completion(success, message);
    }
}

#pragma mark - Text API

- (BOOL)shouldTranslateText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        return NO;
    }
    // 纯数字 / 符号跳过
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    if ([trimmed rangeOfCharacterFromSet:letters].location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (NSString *)googleTargetForLocaleIdentifier:(NSString *)localeID {
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

- (void)translateText:(NSString *)text
         targetLocale:(NSString *)targetLocale
           completion:(void (^)(NSString * _Nullable translated, NSError * _Nullable error))completion {
    if (text.length == 0) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }

    // 优先 Google 文本接口（只传文本，不改页面域名）；失败再试 Lingva 公共实例。
    [self translateTextUsingGoogle:text targetLocale:targetLocale completion:^(NSString *translated, NSError *error) {
        if (translated.length > 0) {
            if (completion) {
                completion(translated, nil);
            }
            return;
        }
        [self translateTextUsingLingva:text targetLocale:targetLocale completion:completion];
        (void)error;
    }];
}

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
            completion(nil, [NSError errorWithDomain:@"BrowserInPageTranslator" code:1 userInfo:nil]);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    // 超长文本改用 POST，避免 URL 过长
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
            completion(translated, translated.length > 0 ? nil : [NSError errorWithDomain:@"BrowserInPageTranslator" code:2 userInfo:nil]);
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
    // Lingva 兼容前端：/api/v1/{source}/{target}/{query}
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
            completion(translated, translated.length > 0 ? nil : [NSError errorWithDomain:@"BrowserInPageTranslator" code:3 userInfo:nil]);
        }
        (void)response;
    }] resume];
}

@end
