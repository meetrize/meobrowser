#import "BrowserTranslationPipeline.h"
#import "BrowserTextTranslationService.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface BrowserTranslationPipelineSession : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) NSString *targetLocale;
@property (nonatomic, assign) BrowserTranslationPresentationMode mode;
@property (nonatomic, strong) NSMutableArray *collectedItems;
@property (nonatomic, copy, nullable) void (^completion)(BOOL success, NSString * _Nullable errorMessage);
@property (nonatomic, assign) BOOL startFinished;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, strong, nullable) id retainedDelegate;
@property (nonatomic, strong, nullable) dispatch_block_t timeoutBlock;
@end

@implementation BrowserTranslationPipelineSession
@end

@interface BrowserTranslationPipeline ()
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserTranslationPipelineSession *> *sessionsByWebView;
@end

@implementation BrowserTranslationPipeline

+ (instancetype)sharedPipeline {
    static BrowserTranslationPipeline *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserTranslationPipeline alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionsByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                                   valueOptions:NSPointerFunctionsStrongMemory];
    }
    return self;
}

- (BOOL)isTranslatingWebView:(WKWebView *)webView {
    BrowserTranslationPipelineSession *session = webView ? [self.sessionsByWebView objectForKey:webView] : nil;
    return session != nil && !session.completed && !session.cancelled;
}

#pragma mark - Script bridge

+ (NSString *)pageTranslationScriptSource {
    static NSString *source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"page-translation" ofType:@"js"];
        NSString *fileSource = nil;
        if (path.length > 0) {
            NSError *error = nil;
            fileSource = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
            if (error != nil || fileSource.length == 0) {
                fileSource = nil;
            }
        }
        if (fileSource.length == 0) {
            fileSource = @"(function(){window.__MeoTranslation=window.__MeoTranslation||{"
                         @"clear:function(){return{ok:true}},"
                         @"applyBilingual:function(){return{ok:false,applied:0,total:0}},"
                         @"applyHover:function(){return{ok:false,applied:0,total:0}}};})();";
        }
        source = fileSource;
    });
    return source;
}

+ (void)evaluateJavaScript:(NSString *)js
                 inWebView:(WKWebView *)webView
                completion:(void (^)(id _Nullable value))completion {
    if (!webView || js.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    [webView evaluateJavaScript:js completionHandler:^(id value, NSError *error) {
        (void)error;
        if (completion) {
            completion(value);
        }
    }];
}

+ (void)ensureBridgeInWebView:(WKWebView *)webView completion:(void (^)(BOOL ready))completion {
    NSString *check = @"(function(){return !!(window.__MeoTranslation && window.__MeoTranslation.clear);})()";
    [self evaluateJavaScript:check inWebView:webView completion:^(id value) {
        if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) {
            if (completion) {
                completion(YES);
            }
            return;
        }
        NSString *inject = [self pageTranslationScriptSource];
        [self evaluateJavaScript:inject inWebView:webView completion:^(id ignored) {
            (void)ignored;
            if (completion) {
                completion(YES);
            }
        }];
    }];
}

+ (nullable NSString *)jsonStringFromObject:(id)object {
    if (object == nil || ![NSJSONSerialization isValidJSONObject:object]) {
        return nil;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data || error) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Public

- (void)cancelTranslationForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    BrowserTranslationPipelineSession *session = [self.sessionsByWebView objectForKey:webView];
    if (session == nil || session.completed) {
        return;
    }
    session.cancelled = YES;
    [self finishSession:session success:NO message:nil];
}

- (void)clearPagePresentationInWebView:(WKWebView *)webView
                            completion:(void (^)(void))completion {
    if (webView == nil) {
        if (completion) {
            completion();
        }
        return;
    }
    [[self class] ensureBridgeInWebView:webView completion:^(BOOL ready) {
        (void)ready;
        [[self class] evaluateJavaScript:@"(function(){return window.__MeoTranslation&&window.__MeoTranslation.clear();})()"
                               inWebView:webView
                              completion:^(id value) {
            (void)value;
            if (completion) {
                completion();
            }
        }];
    }];
}

- (void)translateWebView:(WKWebView *)webView
  targetLocaleIdentifier:(NSString *)localeID
                    mode:(BrowserTranslationPresentationMode)mode
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

    BrowserTranslationPipelineSession *session = [[BrowserTranslationPipelineSession alloc] init];
    session.webView = webView;
    session.targetLocale = [[BrowserTextTranslationService sharedService] normalizedTargetLocaleIdentifier:localeID];
    session.mode = mode;
    session.collectedItems = [NSMutableArray array];
    session.completion = completion;
    session.retainedDelegate = self;
    [self.sessionsByWebView setObject:session forKey:webView];

    __weak typeof(self) weakSelf = self;
    __weak BrowserTranslationPipelineSession *weakSession = session;
    dispatch_block_t timeoutBlock = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        BrowserTranslationPipelineSession *strongSession = weakSession;
        if (!strongSelf || !strongSession || strongSession.completed) {
            return;
        }
        strongSession.cancelled = YES;
        [strongSelf finishSession:strongSession success:NO message:@"翻译超时，请重试"];
    });
    session.timeoutBlock = timeoutBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   timeoutBlock);

    ((void (*)(id, SEL, id))objc_msgSend)(webView, NSSelectorFromString(@"_setTextManipulationDelegate:"), self);

    Class confCls = NSClassFromString(@"_WKTextManipulationConfiguration");
    id configuration = confCls ? [confCls new] : nil;
    if (configuration && [configuration respondsToSelector:NSSelectorFromString(@"setIncludeSubframes:")]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, NSSelectorFromString(@"setIncludeSubframes:"), YES);
    }

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
                BrowserTranslationPipelineSession *current = [strongSelf.sessionsByWebView objectForKey:strongWebView];
                if (current == nil || current.completed || current.cancelled) {
                    return;
                }
                current.startFinished = YES;
                [strongSelf translateCollectedItemsForSession:current];
            });
        });
}

#pragma mark - _WKTextManipulationDelegate

- (void)_webView:(WKWebView *)webView didFindTextManipulationItems:(NSArray *)items {
    BrowserTranslationPipelineSession *session = [self.sessionsByWebView objectForKey:webView];
    if (session == nil || session.completed || session.cancelled || items.count == 0) {
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

- (void)translateCollectedItemsForSession:(BrowserTranslationPipelineSession *)session {
    if (session.cancelled || session.completed) {
        return;
    }
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
            if (!excluded && [content isKindOfClass:[NSString class]]
                && [[BrowserTextTranslationService sharedService] shouldTranslateText:content]) {
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

    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:jobs.count];
    for (NSDictionary *job in jobs) {
        [texts addObject:job[@"text"] ?: @""];
    }

    __weak typeof(self) weakSelf = self;
    [[BrowserTextTranslationService sharedService] translateTexts:texts
                                                     targetLocale:session.targetLocale
                                                      concurrency:6
                                                       completion:^(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        NSMutableDictionary<NSNumber *, NSString *> *translatedByJob = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < translatedOrEmpty.count; i++) {
            NSString *translated = translatedOrEmpty[i];
            if (translated.length > 0) {
                translatedByJob[@(i)] = translated;
            }
        }
        if (translatedByJob.count == 0) {
            [strongSelf finishSession:session success:NO message:@"翻译服务暂时不可用"];
            return;
        }
        if (session.mode == BrowserTranslationPresentationModeReplace) {
            [strongSelf applyReplaceTranslations:translatedByJob
                                            jobs:jobs
                                         session:session
                                   failureCount:failureCount];
        } else {
            [strongSelf applyJSPresentationWithTranslations:translatedByJob
                                                       jobs:jobs
                                                    session:session
                                              failureCount:failureCount];
        }
    }];
}

- (void)applyReplaceTranslations:(NSDictionary<NSNumber *, NSString *> *)translatedByJob
                            jobs:(NSArray<NSDictionary *> *)jobs
                         session:(BrowserTranslationPipelineSession *)session
                    failureCount:(NSUInteger)failureCount {
    if (session.cancelled || session.completed) {
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }

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
                if (!strongSelf || session.cancelled || session.completed) {
                    return;
                }
                BOOL ok = (errors == nil || errors.count == 0 || replacements.count > errors.count);
                NSString *message = nil;
                if (ok && (failureCount > 0 || (errors != nil && errors.count > 0))) {
                    message = @"部分段落未译出";
                } else if (!ok) {
                    message = @"部分内容未能替换";
                }
                [strongSelf finishSession:session success:ok message:message];
            });
        });
}

- (void)applyJSPresentationWithTranslations:(NSDictionary<NSNumber *, NSString *> *)translatedByJob
                                       jobs:(NSArray<NSDictionary *> *)jobs
                                    session:(BrowserTranslationPipelineSession *)session
                              failureCount:(NSUInteger)failureCount {
    if (session.cancelled || session.completed) {
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }

    // Bilingual / Hover：不调用 completeTextManipulation，保留原文。
    // 过滤域名/URL/短元数据，并按规范化 source 去重（Replace 路径不受影响）。
    BrowserTextTranslationService *service = [BrowserTextTranslationService sharedService];
    NSMutableArray<NSDictionary *> *units = [NSMutableArray array];
    NSMutableSet<NSString *> *seenSources = [NSMutableSet set];
    NSArray<NSNumber *> *sortedKeys = [[translatedByJob allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *jobIndex in sortedKeys) {
        NSDictionary *job = jobs[jobIndex.unsignedIntegerValue];
        NSString *source = job[@"text"] ?: @"";
        NSString *text = translatedByJob[jobIndex] ?: @"";
        if (source.length == 0 || text.length == 0) {
            continue;
        }
        if (![service isSuitableForPresentationTranslation:source]) {
            continue;
        }
        NSString *normalizedSource =
            [[source stringByReplacingOccurrencesOfString:@"\\s+"
                                               withString:@" "
                                                  options:NSRegularExpressionSearch
                                                    range:NSMakeRange(0, source.length)]
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (normalizedSource.length == 0 || [seenSources containsObject:normalizedSource]) {
            continue;
        }
        [seenSources addObject:normalizedSource];
        [units addObject:@{
            @"id": [NSString stringWithFormat:@"u%lu", (unsigned long)jobIndex.unsignedIntegerValue],
            @"source": source,
            @"text": text,
        }];
    }
    if (units.count == 0) {
        [self finishSession:session success:NO message:@"翻译结果为空"];
        return;
    }

    NSString *unitsJSON = [[self class] jsonStringFromObject:units];
    if (unitsJSON.length == 0) {
        [self finishSession:session success:NO message:@"翻译结果无效"];
        return;
    }

    NSString *method = (session.mode == BrowserTranslationPresentationModeHover)
        ? @"applyHover"
        : @"applyBilingual";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.%@){return {ok:false};}"
                    @"return window.__MeoTranslation.%@(%@);})()",
                    method, method, unitsJSON];

    __weak typeof(self) weakSelf = self;
    [[self class] ensureBridgeInWebView:webView completion:^(BOOL ready) {
        (void)ready;
        if (session.cancelled || session.completed) {
            return;
        }
        [[self class] evaluateJavaScript:js inWebView:webView completion:^(id value) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || session.cancelled || session.completed) {
                return;
            }
            NSInteger applied = 0;
            NSInteger total = (NSInteger)units.count;
            if ([value isKindOfClass:[NSDictionary class]]) {
                applied = [value[@"applied"] integerValue];
                if (value[@"total"] != nil) {
                    total = [value[@"total"] integerValue];
                }
            }
            BOOL ok = applied > 0;
            NSString *message = nil;
            if (ok && (applied < total || failureCount > 0)) {
                message = @"部分段落未译出";
            } else if (!ok) {
                message = @"未能在页面上应用译文";
            }
            [strongSelf finishSession:session success:ok message:message];
        }];
    }];
}

- (void)finishSession:(BrowserTranslationPipelineSession *)session
              success:(BOOL)success
              message:(NSString *)message {
    if (session.completed) {
        return;
    }
    session.completed = YES;
    if (session.timeoutBlock) {
        dispatch_block_cancel(session.timeoutBlock);
        session.timeoutBlock = nil;
    }
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

@end
