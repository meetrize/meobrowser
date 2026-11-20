#import "BrowserTranslationPipeline.h"
#import "BrowserTextTranslationService.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface BrowserTranslationPipelineSession : NSObject
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) NSString *targetLocale;
@property (nonatomic, assign) BrowserTranslationPresentationMode mode;
@property (nonatomic, assign) BOOL resumeIncomplete;
@property (nonatomic, assign) BOOL collectHitCap;
@property (nonatomic, assign) NSInteger progressiveAppliedCount;
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
    // bridgeVersion>=2 才支持 resume；旧桥必须强制重注。
    NSString *check =
        @"(function(){var t=window.__MeoTranslation;return !!(t && "
        @"typeof t.collectCandidates==='function' && (t.bridgeVersion|0)>=2);})()";
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
    [self cancelTranslationForWebView:webView cancelMessage:@"已取消翻译"];
}

- (void)cancelTranslationForWebView:(WKWebView *)webView
                      cancelMessage:(NSString *)cancelMessage {
    if (webView == nil) {
        return;
    }
    BrowserTranslationPipelineSession *session = [self.sessionsByWebView objectForKey:webView];
    if (session == nil || session.completed) {
        return;
    }
    session.cancelled = YES;
    [self finishSession:session success:NO message:(cancelMessage.length > 0 ? cancelMessage : @"已取消翻译")];
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
                                            resumeIncomplete:(BOOL)resumeIncomplete
                                                   completion:(void (^)(BOOL, NSString * _Nullable))completion {
    BrowserTranslationPipelineSession *session = [[BrowserTranslationPipelineSession alloc] init];
    session.webView = webView;
    session.targetLocale = [[BrowserTextTranslationService sharedService] normalizedTargetLocaleIdentifier:localeID];
    session.mode = mode;
    session.resumeIncomplete = resumeIncomplete;
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
        BOOL hadPartial = strongSession.progressiveAppliedCount > 0;
        NSString *msg = hadPartial
            ? [NSString stringWithFormat:@"翻译超时（已译 %ld 段），可再次点击翻译继续",
                                         (long)strongSession.progressiveAppliedCount]
            : @"翻译超时，请重试";
        // 已有部分上屏时以 success=YES 收尾，便于控制器保留「已翻译」态并续译。
        [strongSelf finishSession:strongSession success:hadPartial message:msg];
    });
    session.timeoutBlock = timeoutBlock;
    // 大页 + Index 限流时 60s 不够；放宽到 3 分钟。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   timeoutBlock);
    return session;
}

- (void)translateWebView:(WKWebView *)webView
  targetLocaleIdentifier:(NSString *)localeID
                    mode:(BrowserTranslationPresentationMode)mode
              completion:(void (^)(BOOL, NSString * _Nullable))completion {
    [self translateWebView:webView
    targetLocaleIdentifier:localeID
                      mode:mode
         resumeIncomplete:NO
                completion:completion];
}

- (void)translateWebView:(WKWebView *)webView
  targetLocaleIdentifier:(NSString *)localeID
                    mode:(BrowserTranslationPresentationMode)mode
       resumeIncomplete:(BOOL)resumeIncomplete
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
                              resumeIncomplete:resumeIncomplete
                                     completion:completion];
        return;
    }

    BrowserTranslationPipelineSession *session =
        [self beginSessionForWebView:webView
              targetLocaleIdentifier:localeID
                                mode:mode
                   resumeIncomplete:resumeIncomplete
                          completion:completion];
    [self startJSPresentationTranslationForSession:session];
}

- (void)startReplaceTranslationForWebView:(WKWebView *)webView
                   targetLocaleIdentifier:(NSString *)localeID
                        resumeIncomplete:(BOOL)resumeIncomplete
                               completion:(void (^)(BOOL, NSString * _Nullable))completion {
    (void)[self beginSessionForWebView:webView
                targetLocaleIdentifier:localeID
                                  mode:BrowserTranslationPresentationModeReplace
                     resumeIncomplete:resumeIncomplete
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
    [self collectJSPresentationCandidatesForSession:session attempt:0];
}

- (void)collectJSPresentationCandidatesForSession:(BrowserTranslationPipelineSession *)session
                                          attempt:(NSUInteger)attempt {
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
        NSString *collectJS = session.resumeIncomplete
            ? @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.collectCandidates)"
              @"{return{ok:false,candidates:[],total:0};}"
              @"return window.__MeoTranslation.collectCandidates({resume:true});})()"
            : @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.collectCandidates)"
              @"{return{ok:false,candidates:[],total:0};}"
              @"return window.__MeoTranslation.collectCandidates();})()";
        [[strongSelf class] evaluateJavaScript:collectJS inWebView:webView completion:^(id value) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf || session.cancelled || session.completed) {
                return;
            }
            [innerSelf continueJSPresentationWithCollectResult:value
                                                       session:session
                                                       attempt:attempt];
        }];
    }];
}

- (void)continueJSPresentationWithCollectResult:(id)value
                                        session:(BrowserTranslationPipelineSession *)session
                                        attempt:(NSUInteger)attempt {
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
        if ([value[@"capped"] respondsToSelector:@selector(boolValue)]) {
            session.collectHitCap = [value[@"capped"] boolValue];
        }
    }
    if (![rawCandidates isKindOfClass:[NSArray class]] || rawCandidates.count == 0) {
        if (session.resumeIncomplete) {
            [self finishSession:session success:YES message:@"没有剩余未译段落"];
            return;
        }
        // reload / SPA 首屏未就绪时重试几次，避免误报「未找到可翻译文本」。
        if (attempt < 6) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || session.cancelled || session.completed) {
                    return;
                }
                [self collectJSPresentationCandidatesForSession:session attempt:attempt + 1];
            });
            return;
        }
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
        if (session.resumeIncomplete) {
            [self finishSession:session success:YES message:@"没有剩余未译段落"];
            return;
        }
        if (attempt < 6) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || session.cancelled || session.completed) {
                    return;
                }
                [self collectJSPresentationCandidatesForSession:session attempt:attempt + 1];
            });
            return;
        }
        [self finishSession:session success:NO message:@"未找到可翻译文本"];
        return;
    }

    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:jobs.count];
    for (NSDictionary *job in jobs) {
        [texts addObject:job[@"text"] ?: @""];
    }

    NSMutableSet<NSString *> *appliedIds = [NSMutableSet set];
    __block NSInteger progressiveApplied = 0;
    __weak typeof(self) weakSelf = self;
    // Index-Translate：有限并发；progress 逐步上屏。
    [[BrowserTextTranslationService sharedService] translateTexts:texts
                                                     targetLocale:session.targetLocale
                                                      concurrency:8
                                                        progress:^(NSArray<NSString *> *partialOrEmpty) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        NSMutableArray<NSDictionary *> *units = [NSMutableArray array];
        for (NSUInteger i = 0; i < jobs.count && i < partialOrEmpty.count; i++) {
            NSString *translated = partialOrEmpty[i];
            if (translated.length == 0) {
                continue;
            }
            NSDictionary *job = jobs[i];
            NSString *candidateId = job[@"id"] ?: @"";
            if (candidateId.length == 0 || [appliedIds containsObject:candidateId]) {
                continue;
            }
            [appliedIds addObject:candidateId];
            [units addObject:@{
                @"id": candidateId,
                @"source": job[@"text"] ?: @"",
                @"text": translated,
            }];
        }
        if (units.count == 0) {
            return;
        }
        [strongSelf applyJSPresentationByIdWithUnits:units
                                             session:session
                                          completion:^(NSInteger applied, NSInteger total) {
            (void)total;
            progressiveApplied += applied;
            session.progressiveAppliedCount = progressiveApplied;
        }];
    }
                                                      completion:^(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount, NSError *batchError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        // 收尾：补上 progress 未覆盖的（极少），并结束会话。
        NSMutableArray<NSDictionary *> *units = [NSMutableArray array];
        NSUInteger successCount = 0;
        for (NSUInteger i = 0; i < jobs.count && i < translatedOrEmpty.count; i++) {
            NSString *translated = translatedOrEmpty[i];
            if (translated.length == 0) {
                continue;
            }
            successCount += 1;
            NSDictionary *job = jobs[i];
            NSString *candidateId = job[@"id"] ?: @"";
            if (candidateId.length == 0 || [appliedIds containsObject:candidateId]) {
                continue;
            }
            [appliedIds addObject:candidateId];
            [units addObject:@{
                @"id": candidateId,
                @"source": job[@"text"] ?: @"",
                @"text": translated,
            }];
        }
        void (^finishWithApplied)(NSInteger) = ^(NSInteger appliedNow) {
            NSInteger applied = progressiveApplied + appliedNow;
            session.progressiveAppliedCount = applied;
            BOOL ok = YES;
            NSString *message = nil;
            NSString *reason =
                [BrowserTextTranslationService userFacingSummaryForBatchError:batchError];
            if (successCount == 0 || applied == 0) {
                ok = NO;
                if (session.resumeIncomplete && reason.length > 0) {
                    message = [NSString stringWithFormat:@"%@，未能继续翻译", reason];
                } else {
                    message = reason.length > 0 ? reason : @"翻译服务暂时不可用";
                }
            } else if (applied <= 2 && (NSInteger)jobs.count >= 10 && !session.resumeIncomplete) {
                ok = NO;
                message = @"未能定位正文译文";
            } else if (failureCount > 0) {
                ok = YES;
                if (reason.length > 0) {
                    message = [NSString stringWithFormat:@"%@，已译 %ld 段，可再次点击翻译继续",
                               reason, (long)applied];
                } else {
                    message = [NSString stringWithFormat:@"部分段落未译出（已译 %ld 段），可再次点击翻译继续",
                               (long)applied];
                }
            } else if (session.collectHitCap) {
                ok = YES;
                message = [NSString stringWithFormat:@"本批已译 %ld 段，页面还有更多，可再次点击翻译继续",
                           (long)applied];
            }
            [strongSelf finishSession:session success:ok message:message];
        };
        if (units.count == 0) {
            finishWithApplied(0);
            return;
        }
        [strongSelf applyJSPresentationByIdWithUnits:units
                                             session:session
                                          completion:^(NSInteger applied, NSInteger total) {
            (void)total;
            finishWithApplied(applied);
        }];
    }];
}

- (void)applyJSPresentationByIdWithUnits:(NSArray<NSDictionary *> *)units
                                 session:(BrowserTranslationPipelineSession *)session
                              completion:(void (^)(NSInteger applied, NSInteger total))completion {
    if (session.cancelled || session.completed) {
        if (completion) {
            completion(0, (NSInteger)units.count);
        }
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        if (completion) {
            completion(0, (NSInteger)units.count);
        }
        return;
    }

    NSString *unitsJSON = [[self class] jsonStringFromObject:units];
    if (unitsJSON.length == 0) {
        if (completion) {
            completion(0, (NSInteger)units.count);
        }
        return;
    }

    NSString *method = (session.mode == BrowserTranslationPresentationModeHover)
        ? @"applyHoverById"
        : @"applyBilingualById";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){if(!window.__MeoTranslation||!window.__MeoTranslation.%@){return {ok:false};}"
                    @"return window.__MeoTranslation.%@(%@);})()",
                    method, method, unitsJSON];

    [[self class] evaluateJavaScript:js inWebView:webView completion:^(id value) {
        if (session.cancelled || session.completed) {
            if (completion) {
                completion(0, (NSInteger)units.count);
            }
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
        if (completion) {
            completion(applied, total);
        }
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
    [self translateCollectedItemsForSession:session attempt:0];
}

- (void)translateCollectedItemsForSession:(BrowserTranslationPipelineSession *)session
                                  attempt:(NSUInteger)attempt {
    if (session.cancelled || session.completed) {
        return;
    }
    WKWebView *webView = session.webView;
    if (webView == nil) {
        [self finishSession:session success:NO message:@"页面已关闭"];
        return;
    }
    if (session.collectedItems.count == 0) {
        if (attempt < 5) {
            __weak typeof(self) weakSelf = self;
            __weak WKWebView *weakWebView = webView;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                WKWebView *strongWebView = weakWebView;
                if (!self || !strongWebView || session.cancelled || session.completed) {
                    return;
                }
                // 重新跑 TextManipulation 抽取（DOM 可能刚就绪）。
                session.collectedItems = [NSMutableArray array];
                session.startFinished = NO;
                Class confCls = NSClassFromString(@"_WKTextManipulationConfiguration");
                id configuration = confCls ? [confCls new] : nil;
                if (configuration && [configuration respondsToSelector:NSSelectorFromString(@"setIncludeSubframes:")]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, NSSelectorFromString(@"setIncludeSubframes:"), YES);
                }
                ((void (*)(id, SEL, id))objc_msgSend)(strongWebView, NSSelectorFromString(@"_setTextManipulationDelegate:"), self);
                ((void (*)(id, SEL, id, id))objc_msgSend)(
                    strongWebView,
                    NSSelectorFromString(@"_startTextManipulationsWithConfiguration:completion:"),
                    configuration,
                    ^{
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (session.cancelled || session.completed) {
                                return;
                            }
                            session.startFinished = YES;
                            [self translateCollectedItemsForSession:session attempt:attempt + 1];
                        });
                    });
            });
            return;
        }
        NSString *emptyMsg = session.resumeIncomplete
            ? @"没有剩余未译段落，可先显示原文后再重新翻译"
            : @"未找到可翻译文本，请先显示原文后再试";
        [self finishSession:session success:NO message:emptyMsg];
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
                // 续译：跳过已像中文的 token，避免把已译段落再送一遍。
                if (session.resumeIncomplete
                    && [translateService looksAlreadyChineseTranslated:content]) {
                    index += 1;
                    continue;
                }
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
        NSString *emptyMsg = session.resumeIncomplete ? @"没有剩余未译段落" : @"未找到可翻译文本";
        [self finishSession:session success:session.resumeIncomplete message:emptyMsg];
        return;
    }

    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:jobs.count];
    for (NSDictionary *job in jobs) {
        [texts addObject:job[@"text"] ?: @""];
    }

    // item → 该 item 下全部待译 job 下标（指针键，与 jobs 中同一对象）。
    NSMapTable *jobIndexesByItem = [NSMapTable strongToStrongObjectsMapTable];
    for (NSUInteger i = 0; i < jobs.count; i++) {
        id item = jobs[i][@"item"];
        if (item == nil) {
            continue;
        }
        NSMutableArray<NSNumber *> *indexes = [jobIndexesByItem objectForKey:item];
        if (indexes == nil) {
            indexes = [NSMutableArray array];
            [jobIndexesByItem setObject:indexes forKey:item];
        }
        [indexes addObject:@(i)];
    }

    NSMutableDictionary<NSNumber *, NSString *> *accumulated = [NSMutableDictionary dictionary];
    NSMutableSet *appliedItems = [NSMutableSet set];
    __block NSUInteger lastFailureCount = 0;
    __block NSError *lastBatchError = nil;
    __block BOOL finalApplyStarted = NO;
    __weak typeof(self) weakSelf = self;

    void (^applyReadyReplaceItems)(BOOL) = ^(BOOL isFinal) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed || finalApplyStarted) {
            return;
        }

        NSMutableDictionary<NSNumber *, NSString *> *readyJobs = [NSMutableDictionary dictionary];
        NSMutableArray *newlyReadyItems = [NSMutableArray array];
        for (id item in jobIndexesByItem.keyEnumerator) {
            if ([appliedItems containsObject:item]) {
                continue;
            }
            NSArray<NSNumber *> *indexes = [jobIndexesByItem objectForKey:item];
            BOOL allReady = YES;
            for (NSNumber *idx in indexes) {
                if ([accumulated[idx] length] == 0) {
                    allReady = NO;
                    break;
                }
            }
            if (!allReady) {
                continue;
            }
            for (NSNumber *idx in indexes) {
                readyJobs[idx] = accumulated[idx];
            }
            [newlyReadyItems addObject:item];
        }

        if (!isFinal) {
            if (readyJobs.count == 0) {
                return;
            }
            [appliedItems addObjectsFromArray:newlyReadyItems];
            [strongSelf applyReplaceTranslations:readyJobs
                                            jobs:jobs
                                         session:session
                                    failureCount:lastFailureCount
                                         isFinal:NO];
            return;
        }

        // 收尾：未成套的 item 也尽量替换已译 token，并与本轮 ready 合并一次提交。
        NSMutableDictionary<NSNumber *, NSString *> *finalJobs = [readyJobs mutableCopy] ?: [NSMutableDictionary dictionary];
        [appliedItems addObjectsFromArray:newlyReadyItems];
        [accumulated enumerateKeysAndObjectsUsingBlock:^(NSNumber *idx, NSString *text, BOOL *stop) {
            (void)stop;
            if (text.length == 0 || idx.unsignedIntegerValue >= jobs.count) {
                return;
            }
            id item = jobs[idx.unsignedIntegerValue][@"item"];
            if (item == nil || [appliedItems containsObject:item]) {
                return;
            }
            finalJobs[idx] = text;
            [appliedItems addObject:item];
        }];

        finalApplyStarted = YES;
        if (finalJobs.count > 0) {
            [strongSelf applyReplaceTranslations:finalJobs
                                            jobs:jobs
                                         session:session
                                    failureCount:lastFailureCount
                                         isFinal:YES];
            return;
        }
        if (appliedItems.count == 0 && accumulated.count == 0) {
            [strongSelf finishSession:session success:NO message:@"翻译服务暂时不可用"];
            return;
        }
        // 全部已在 progress 阶段替换完。
        BOOL ok = accumulated.count > 0;
        NSString *reason = [BrowserTextTranslationService userFacingSummaryForBatchError:lastBatchError];
        NSString *message = nil;
        if (!ok) {
            message = reason.length > 0 ? reason : @"翻译结果为空";
        } else if (lastFailureCount > 0) {
            if (reason.length > 0) {
                message = [NSString stringWithFormat:@"%@，已译部分内容，可再次点击翻译继续", reason];
            } else {
                message = @"部分段落未译出，可再次点击翻译继续";
            }
        }
        [strongSelf finishSession:session success:ok message:message];
    };

    [[BrowserTextTranslationService sharedService] translateTexts:texts
                                                     targetLocale:session.targetLocale
                                                      concurrency:8
                                                        progress:^(NSArray<NSString *> *partialOrEmpty) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        for (NSUInteger i = 0; i < partialOrEmpty.count; i++) {
            NSString *translated = partialOrEmpty[i];
            if (translated.length > 0) {
                accumulated[@(i)] = translated;
            }
        }
        applyReadyReplaceItems(NO);
    }
                                                      completion:^(NSArray<NSString *> *translatedOrEmpty, NSUInteger failureCount, NSError *batchError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || session.cancelled || session.completed) {
            return;
        }
        lastFailureCount = failureCount;
        lastBatchError = batchError;
        for (NSUInteger i = 0; i < translatedOrEmpty.count; i++) {
            NSString *translated = translatedOrEmpty[i];
            if (translated.length > 0) {
                accumulated[@(i)] = translated;
            }
        }
        applyReadyReplaceItems(YES);
    }];
}

- (void)applyReplaceTranslations:(NSDictionary<NSNumber *, NSString *> *)translatedByJob
                            jobs:(NSArray<NSDictionary *> *)jobs
                         session:(BrowserTranslationPipelineSession *)session
                    failureCount:(NSUInteger)failureCount
                         isFinal:(BOOL)isFinal {
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
        if (jobIndex.unsignedIntegerValue >= jobs.count) {
            return;
        }
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
        if (isFinal) {
            [self finishSession:session success:NO message:@"当前系统不支持页内翻译"];
        }
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
        if (isFinal) {
            [self finishSession:session success:NO message:@"翻译结果为空"];
        }
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
                if (!isFinal) {
                    if (errors == nil || errors.count < replacements.count) {
                        session.progressiveAppliedCount +=
                            (NSInteger)MAX((NSInteger)replacements.count - (NSInteger)(errors.count ?: 0), 0);
                    }
                    return;
                }
                BOOL ok = (errors == nil || errors.count == 0 || replacements.count > errors.count);
                NSString *message = nil;
                if (ok && (failureCount > 0 || (errors != nil && errors.count > 0))) {
                    message = @"部分段落未译出，可再次点击翻译继续";
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
