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
    // Always read from the bundle so rebuilds pick up the latest page-translation.js
    // without requiring a process restart to clear a dispatch_once cache.
    NSString *path = [[NSBundle mainBundle] pathForResource:@"page-translation" ofType:@"js"];
    if (path.length > 0) {
        NSError *error = nil;
        NSString *fileSource = [NSString stringWithContentsOfFile:path
                                                         encoding:NSUTF8StringEncoding
                                                            error:&error];
        if (error == nil && fileSource.length > 0) {
            return fileSource;
        }
    }
    return @"(function(){window.__MeoTranslation=window.__MeoTranslation||{"
           @"clear:function(){return{ok:true}},"
           @"collectCandidates:function(){return{ok:false,candidates:[],total:0}},"
           @"applyBilingualById:function(){return{ok:false,applied:0,total:0}},"
           @"applyHoverById:function(){return{ok:false,applied:0,total:0}},"
           @"applyBilingual:function(){return{ok:false,applied:0,total:0}},"
           @"applyHover:function(){return{ok:false,applied:0,total:0}}};})();";
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
    // Require collectCandidates so older injected bridges are upgraded.
    NSString *check =
        @"(function(){return !!(window.__MeoTranslation && "
        @"typeof window.__MeoTranslation.collectCandidates==='function');})()";
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

- (BrowserTranslationPipelineSession *)beginSessionForWebView:(WKWebView *)webView
                                       targetLocaleIdentifier:(NSString *)localeID
                                                         mode:(BrowserTranslationPresentationMode)mode
                                                   completion:(void (^)(BOOL, NSString * _Nullable))completion {
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
    return session;
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

    BOOL presentationMode = (mode != BrowserTranslationPresentationModeReplace);
    if (!presentationMode) {
        if (![webView respondsToSelector:NSSelectorFromString(@"_setTextManipulationDelegate:")]
            || ![webView respondsToSelector:NSSelectorFromString(@"_startTextManipulationsWithConfiguration:completion:")]
            || ![webView respondsToSelector:NSSelectorFromString(@"_completeTextManipulationForItems:completion:")]) {
            if (completion) {
                completion(NO, @"当前系统不支持页内翻译");
            }
            return;
        }
        [self startReplaceTranslationForWebView:webView
                         targetLocaleIdentifier:localeID
                                     completion:completion];
        return;
    }

    BrowserTranslationPipelineSession *session =
        [self beginSessionForWebView:webView
              targetLocaleIdentifier:localeID
                                mode:mode
                          completion:completion];
    [self startJSPresentationTranslationForSession:session];
}

- (void)startReplaceTranslationForWebView:(WKWebView *)webView
                   targetLocaleIdentifier:(NSString *)localeID
                               completion:(void (^)(BOOL, NSString * _Nullable))completion {
    (void)[self beginSessionForWebView:webView
                targetLocaleIdentifier:localeID
                                  mode:BrowserTranslationPresentationModeReplace
                            completion:completion];

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
                BrowserTranslationPipelineSession *current = [strongSelf.sessionsByWebView objectForKey:strongWebView];
                if (current == nil || current.completed || current.cancelled) {
                    return;
                }
                current.startFinished = YES;
                [strongSelf translateCollectedItemsForSession:current];
            });
        });
}

- (void)startJSPresentationTranslationForSession:(BrowserTranslationPipelineSession *)session {
    if (session.cancelled || session.completed) {
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[self class] ensureBridgeInWebView:webView completion:^(BOOL ready) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        if (!ready) {
            [strongSelf finishSession:session success:NO message:@"无法注入翻译脚本"];
            return;
        }
        NSString *collectJS =
            @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.collectCandidates)"
            @"{return{ok:false,candidates:[],total:0};}"
            @"return window.__MeoTranslation.collectCandidates();})()";
        [[strongSelf class] evaluateJavaScript:collectJS inWebView:webView completion:^(id value) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf || session.cancelled || session.completed) {
                return;
            }
            [innerSelf continueJSPresentationWithCollectResult:value session:session];
        }];
    }];
}

- (void)continueJSPresentationWithCollectResult:(id)value
                                        session:(BrowserTranslationPipelineSession *)session {
    if (session.cancelled || session.completed) {
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }

    NSArray *rawCandidates = nil;
    if ([value isKindOfClass:[NSDictionary class]]) {
        rawCandidates = value[@"candidates"];
    }
    if (![rawCandidates isKindOfClass:[NSArray class]] || rawCandidates.count == 0) {
        [self finishSession:session success:NO message:@"未找到可翻译文本"];
        return;
    }

    BrowserTextTranslationService *service = [BrowserTextTranslationService sharedService];
    NSMutableArray<NSDictionary *> *jobs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenSources = [NSMutableSet set];
    for (id entry in rawCandidates) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *candidateId = [entry[@"id"] isKindOfClass:[NSString class]] ? entry[@"id"] : nil;
        NSString *source = [entry[@"source"] isKindOfClass:[NSString class]] ? entry[@"source"] : nil;
        if (candidateId.length == 0 || source.length == 0) {
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
        [jobs addObject:@{
            @"id": candidateId,
            @"text": source,
        }];
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
        NSMutableArray<NSDictionary *> *units = [NSMutableArray array];
        for (NSUInteger i = 0; i < jobs.count && i < translatedOrEmpty.count; i++) {
            NSString *translated = translatedOrEmpty[i];
            if (translated.length == 0) {
                continue;
            }
            NSDictionary *job = jobs[i];
            [units addObject:@{
                @"id": job[@"id"] ?: @"",
                @"source": job[@"text"] ?: @"",
                @"text": translated,
            }];
        }
        if (units.count == 0) {
            [strongSelf finishSession:session success:NO message:@"翻译服务暂时不可用"];
            return;
        }
        [strongSelf applyJSPresentationByIdWithUnits:units
                                             session:session
                                       failureCount:failureCount];
    }];
}

- (void)applyJSPresentationByIdWithUnits:(NSArray<NSDictionary *> *)units
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

    NSString *unitsJSON = [[self class] jsonStringFromObject:units];
    if (unitsJSON.length == 0) {
        [self finishSession:session success:NO message:@"翻译结果无效"];
        return;
    }

    NSString *method = (session.mode == BrowserTranslationPresentationModeHover)
        ? @"applyHoverById"
        : @"applyBilingualById";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.%@){return {ok:false};}"
                    @"return window.__MeoTranslation.%@(%@);})()",
                    method, method, unitsJSON];

    __weak typeof(self) weakSelf = self;
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
        BOOL ok = YES;
        NSString *message = nil;
        if (applied == 0) {
            ok = NO;
            message = @"未能在页面上应用译文";
        } else if (applied <= 2 && total >= 10) {
            ok = NO;
            message = @"未能定位正文译文";
        } else if (applied < total || failureCount > 0) {
            message = @"部分段落未译出";
        }
        [strongSelf finishSession:session success:ok message:message];
    }];
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

#pragma mark - Translate pipeline (Replace / TextManipulation)

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

    BrowserTextTranslationService *translateService = [BrowserTextTranslationService sharedService];
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
            if (excluded || ![content isKindOfClass:[NSString class]]) {
                index += 1;
                continue;
            }
            if ([translateService shouldTranslateText:content]) {
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
        [strongSelf applyReplaceTranslations:translatedByJob
                                        jobs:jobs
                                     session:session
                               failureCount:failureCount];
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
