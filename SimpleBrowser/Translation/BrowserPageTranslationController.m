#import "BrowserPageTranslationController.h"
#import "BrowserTranslationPipeline.h"
#import "BrowserTab.h"
#import "BrowserTransientToast.h"
#import "BrowsingPreferences.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, BrowserPageTranslationMenuAction) {
    BrowserPageTranslationMenuActionTranslateChinese = 1,
    BrowserPageTranslationMenuActionTranslateBilingual,
    BrowserPageTranslationMenuActionTranslateHover,
    BrowserPageTranslationMenuActionTranslateLocale,
    BrowserPageTranslationMenuActionPreferredLanguagesSettings,
    BrowserPageTranslationMenuActionShowOriginal,
    BrowserPageTranslationMenuActionCancelTranslation,
};

@interface BrowserPageTranslationPendingRequest : NSObject
@property (nonatomic, assign) BrowserTranslationPresentationMode mode;
@property (nonatomic, copy) NSString *localeID;
@end

@implementation BrowserPageTranslationPendingRequest
@end

@interface BrowserPageTranslationPreferenceProvider : NSObject
@property (nonatomic, strong) id availability;
@end

@implementation BrowserPageTranslationPreferenceProvider

- (BOOL)isTranslationEnabled {
    return YES;
}

- (BOOL)isContinuedTranslationEnabled {
    return YES;
}

- (NSArray *)userPreferredTargetLocales {
    NSArray *locales = nil;
    if ([self.availability respondsToSelector:@selector(userPreferredTargetLocales)]) {
        locales = [self.availability userPreferredTargetLocales];
    }
    if (locales.count > 0) {
        return locales;
    }
    return [NSLocale preferredLanguages] ?: @[ @"zh-Hans" ];
}

- (void)isTranslationSupportedForCurrentRegionWithCompletionHandler:(void (^)(BOOL))handler {
    if (![self.availability respondsToSelector:@selector(isTranslationSupportedForCurrentRegionWithCompletionHandler:)]) {
        if (handler) {
            handler(NO);
        }
        return;
    }
    [self.availability isTranslationSupportedForCurrentRegionWithCompletionHandler:handler];
}

- (void)supportedLocalePairsWithCompletionHandler:(void (^)(NSArray *))handler {
    if (![self.availability respondsToSelector:@selector(supportedLocalePairsWithCompletionHandler:)]) {
        if (handler) {
            handler(@[]);
        }
        return;
    }
    [self.availability supportedLocalePairsWithCompletionHandler:handler];
}

@end

@interface BrowserPageTranslationController ()
@property (nonatomic, assign) BOOL runtimeLoaded;
@property (nonatomic, assign) BOOL safariEngineAvailable;
@property (nonatomic, assign) BOOL safariRegionSupported;
@property (nonatomic, assign) BOOL safariRegionChecked;
@property (nonatomic, strong) Class translationContextClass;
@property (nonatomic, strong) id sharedAvailability;
@property (nonatomic, strong) BrowserPageTranslationPreferenceProvider *preferenceProvider;
@property (nonatomic, strong) NSMapTable<WKWebView *, id> *contextsByWebView;
@property (nonatomic, strong) NSHashTable<WKWebView *> *inPageTranslatedWebViews;
@property (nonatomic, strong) NSHashTable<WKWebView *> *translatingWebViews;
@property (nonatomic, strong) NSMapTable<WKWebView *, NSNumber *> *presentationModeByWebView;
@property (nonatomic, strong) NSMapTable<WKWebView *, BrowserPageTranslationPendingRequest *> *pendingByWebView;
@property (nonatomic, weak) WKWebView *menuWebView;
@property (nonatomic, weak) BrowserTab *menuTab;
@end

@implementation BrowserPageTranslationController

- (instancetype)init {
    self = [super init];
    if (self) {
        _contextsByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                                   valueOptions:NSPointerFunctionsStrongMemory];
        _inPageTranslatedWebViews = [NSHashTable weakObjectsHashTable];
        _translatingWebViews = [NSHashTable weakObjectsHashTable];
        _presentationModeByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                                           valueOptions:NSPointerFunctionsStrongMemory];
        _pendingByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                                  valueOptions:NSPointerFunctionsStrongMemory];
        [self loadSafariTranslationRuntimeIfNeeded];
    }
    return self;
}

- (void)loadSafariTranslationRuntimeIfNeeded {
    if (self.runtimeLoaded) {
        return;
    }
    self.runtimeLoaded = YES;

    void *shared = dlopen("/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared", RTLD_LAZY);
    void *sharedUI = dlopen("/System/Library/PrivateFrameworks/SafariSharedUI.framework/SafariSharedUI", RTLD_LAZY);
    if (!shared || !sharedUI) {
        self.safariEngineAvailable = NO;
        return;
    }

    self.translationContextClass = NSClassFromString(@"WBSTranslationContext");
    Class availabilityClass = NSClassFromString(@"WBSTranslationAvailability");
    if (!self.translationContextClass || !availabilityClass) {
        self.safariEngineAvailable = NO;
        return;
    }

    SEL sharedSel = NSSelectorFromString(@"sharedAvailability");
    if (![availabilityClass respondsToSelector:sharedSel]) {
        self.safariEngineAvailable = NO;
        return;
    }
    self.sharedAvailability = ((id (*)(Class, SEL))objc_msgSend)(availabilityClass, sharedSel);
    self.preferenceProvider = [[BrowserPageTranslationPreferenceProvider alloc] init];
    self.preferenceProvider.availability = self.sharedAvailability;
    self.safariEngineAvailable = YES;
    self.safariRegionSupported = NO;
    self.safariRegionChecked = NO;
    __weak typeof(self) weakSelf = self;
    [self.preferenceProvider isTranslationSupportedForCurrentRegionWithCompletionHandler:^(BOOL ok) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.safariRegionSupported = ok;
        strongSelf.safariRegionChecked = YES;
    }];
}

- (BOOL)isAvailable {
    return YES;
}

#pragma mark - Context

- (nullable id)contextForWebView:(WKWebView *)webView createIfNeeded:(BOOL)create {
    if (webView == nil || !self.safariEngineAvailable || self.translationContextClass == Nil) {
        return nil;
    }
    id existing = [self.contextsByWebView objectForKey:webView];
    if (existing || !create) {
        return existing;
    }

    SEL factory = NSSelectorFromString(@"translationContextWithWebView:delegate:");
    if (![self.translationContextClass respondsToSelector:factory]) {
        return nil;
    }
    id ctx = ((id (*)(Class, SEL, id, id))objc_msgSend)(self.translationContextClass, factory, webView, self);
    if (ctx == nil) {
        return nil;
    }
    if ([ctx respondsToSelector:NSSelectorFromString(@"setPreferenceProvider:")]) {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setPreferenceProvider:"), self.preferenceProvider);
        } @catch (__unused NSException *exception) {
        }
    }
    @try {
        [ctx setValue:@YES forKey:@"consentedToFirstTimeAlert"];
    } @catch (__unused NSException *exception) {
    }
    objc_setAssociatedObject(ctx, @selector(contextForWebView:createIfNeeded:), webView, OBJC_ASSOCIATION_ASSIGN);
    [self.contextsByWebView setObject:ctx forKey:webView];
    return ctx;
}

- (nullable WKWebView *)webViewForTranslationContext:(id)ctx {
    if (ctx == nil) {
        return nil;
    }
    WKWebView *associated = objc_getAssociatedObject(ctx, @selector(contextForWebView:createIfNeeded:));
    if ([associated isKindOfClass:[WKWebView class]]) {
        return associated;
    }
    return self.menuWebView;
}

- (void)invalidateForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
    [self.contextsByWebView removeObjectForKey:webView];
    [self.inPageTranslatedWebViews removeObject:webView];
    [self.translatingWebViews removeObject:webView];
    [self.presentationModeByWebView removeObjectForKey:webView];
    [self.pendingByWebView removeObjectForKey:webView];
    [self notifyUIStateDidChange];
}

- (void)webViewDidCommitNavigation:(WKWebView *)webView URL:(NSURL *)url {
    if (webView == nil) {
        return;
    }
    BrowserPageTranslationPendingRequest *pending = [self.pendingByWebView objectForKey:webView];
    [self.pendingByWebView removeObjectForKey:webView];

    // 新文档：取消进行中的翻译，清除译文态（保留 pending 以便切换模式后续跑）。
    if ([self.translatingWebViews containsObject:webView]) {
        [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
        [self.translatingWebViews removeObject:webView];
        [BrowserTransientToast dismissPersistentMessageInWindow:self.hostWindow];
    }
    [self.inPageTranslatedWebViews removeObject:webView];
    [self.presentationModeByWebView removeObjectForKey:webView];
    [self notifyUIStateDidChange];

    id ctx = [self contextForWebView:webView createIfNeeded:YES];
    if (ctx != nil) {
        SEL sel = NSSelectorFromString(@"owningWebViewDidCommitNavigationWithURL:completionHandler:");
        if ([ctx respondsToSelector:sel]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(ctx, sel, url, ^{});
        }
    }

    if (pending != nil && pending.localeID.length > 0) {
        BrowserTab *tab = self.menuTab;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startTranslationForWebView:webView
                                         tab:tab
                          localeIdentifier:pending.localeID
                                      mode:pending.mode
                         allowSafariEngine:NO];
        });
    }
}

- (BOOL)isShowingTranslationForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return NO;
    }
    if ([self.inPageTranslatedWebViews containsObject:webView]) {
        return YES;
    }
    id ctx = [self contextForWebView:webView createIfNeeded:NO];
    if (ctx == nil) {
        return NO;
    }
    @try {
        return [[ctx valueForKey:@"hasStartedTranslating"] boolValue];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

- (BOOL)isTranslatingWebView:(WKWebView *)webView {
    if (webView == nil) {
        return NO;
    }
    return [self.translatingWebViews containsObject:webView]
        || [[BrowserTranslationPipeline sharedPipeline] isTranslatingWebView:webView];
}

- (BrowserPageTranslationUIState)uiStateForWebView:(WKWebView *)webView {
    if ([self isTranslatingWebView:webView]) {
        return BrowserPageTranslationUIStateTranslating;
    }
    if ([self isShowingTranslationForWebView:webView]) {
        return BrowserPageTranslationUIStateTranslated;
    }
    return BrowserPageTranslationUIStateIdle;
}

- (BrowserTranslationPresentationMode)presentationModeForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return BrowserTranslationPresentationModeReplace;
    }
    NSNumber *stored = [self.presentationModeByWebView objectForKey:webView];
    if (stored != nil) {
        return (BrowserTranslationPresentationMode)stored.integerValue;
    }
    return BrowserTranslationPresentationModeReplace;
}

- (void)notifyUIStateDidChange {
    if (self.uiStateDidChangeHandler) {
        self.uiStateDidChangeHandler();
    }
}

#pragma mark - Menu

- (void)showMenuFromButton:(NSButton *)button forWebView:(WKWebView *)webView tab:(BrowserTab *)tab {
    self.menuWebView = webView;
    self.menuTab = tab;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"翻译"];
    menu.autoenablesItems = NO;

    BOOL pageOK = [self canOperateWebView:webView tab:tab];
    BOOL translating = [self isTranslatingWebView:webView];
    BOOL showingTranslation = [self isShowingTranslationForWebView:webView];
    BOOL canStartTranslate = pageOK && !translating;

    if (translating) {
        NSMenuItem *busyItem = [[NSMenuItem alloc] initWithTitle:@"正在翻译…"
                                                          action:nil
                                                   keyEquivalent:@""];
        busyItem.enabled = NO;
        [menu addItem:busyItem];

        NSMenuItem *cancelItem = [[NSMenuItem alloc] initWithTitle:@"取消翻译"
                                                            action:@selector(handleTranslateMenuItem:)
                                                     keyEquivalent:@""];
        cancelItem.target = self;
        cancelItem.tag = BrowserPageTranslationMenuActionCancelTranslation;
        cancelItem.enabled = YES;
        [menu addItem:cancelItem];
    } else {
        NSMenuItem *zhItem = [[NSMenuItem alloc] initWithTitle:@"翻译成中文"
                                                        action:@selector(handleTranslateMenuItem:)
                                                 keyEquivalent:@""];
        zhItem.target = self;
        zhItem.tag = BrowserPageTranslationMenuActionTranslateChinese;
        zhItem.enabled = canStartTranslate;
        [menu addItem:zhItem];

        NSMenuItem *bilingualItem = [[NSMenuItem alloc] initWithTitle:@"双语对照（英 / 中）"
                                                               action:@selector(handleTranslateMenuItem:)
                                                        keyEquivalent:@""];
        bilingualItem.target = self;
        bilingualItem.tag = BrowserPageTranslationMenuActionTranslateBilingual;
        bilingualItem.enabled = canStartTranslate;
        [menu addItem:bilingualItem];

        NSMenuItem *hoverItem = [[NSMenuItem alloc] initWithTitle:@"即指即译"
                                                           action:@selector(handleTranslateMenuItem:)
                                                    keyEquivalent:@""];
        hoverItem.target = self;
        hoverItem.tag = BrowserPageTranslationMenuActionTranslateHover;
        hoverItem.enabled = canStartTranslate;
        [menu addItem:hoverItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenu *preferredMenu = [[NSMenu alloc] initWithTitle:@"首选语言"];
    preferredMenu.autoenablesItems = NO;
    NSArray<NSString *> *locales = [self preferredTargetLocaleIdentifiers];
    for (NSString *localeID in locales) {
        NSString *title = [self displayNameForLocaleIdentifier:localeID];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(handleTranslateMenuItem:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = BrowserPageTranslationMenuActionTranslateLocale;
        item.representedObject = localeID;
        item.enabled = canStartTranslate;
        [preferredMenu addItem:item];
    }
    if (locales.count > 0) {
        [preferredMenu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"语言与地区设置…"
                                                          action:@selector(handleTranslateMenuItem:)
                                                   keyEquivalent:@""];
    settingsItem.target = self;
    settingsItem.tag = BrowserPageTranslationMenuActionPreferredLanguagesSettings;
    settingsItem.enabled = YES;
    [preferredMenu addItem:settingsItem];

    NSMenuItem *preferredRoot = [[NSMenuItem alloc] initWithTitle:@"首选语言"
                                                           action:nil
                                                    keyEquivalent:@""];
    preferredRoot.submenu = preferredMenu;
    preferredRoot.enabled = YES;
    [menu addItem:preferredRoot];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *originalItem = [[NSMenuItem alloc] initWithTitle:@"显示原始网页"
                                                          action:@selector(handleTranslateMenuItem:)
                                                   keyEquivalent:@""];
    originalItem.target = self;
    originalItem.tag = BrowserPageTranslationMenuActionShowOriginal;
    // 翻译中也可点：取消并恢复原文；已翻译时可点。
    originalItem.enabled = pageOK && (translating || showingTranslation);
    [menu addItem:originalItem];

    NSRect bounds = button.bounds;
    NSPoint point = NSMakePoint(NSMinX(bounds), NSMaxY(bounds) + 2.0);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:button];
}

- (BOOL)canOperateWebView:(WKWebView *)webView tab:(BrowserTab *)tab {
    if (webView == nil || tab == nil || tab.isNewTabPage) {
        return NO;
    }
    NSURL *url = webView.URL ?: [tab currentOrRestorableURL];
    return [BrowsingPreferences isPersistableURL:url];
}

- (BOOL)canTranslateWebView:(WKWebView *)webView tab:(BrowserTab *)tab {
    return [self canOperateWebView:webView tab:tab] && ![self isTranslatingWebView:webView];
}

- (NSArray<NSString *> *)preferredTargetLocaleIdentifiers {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^append)(NSString *) = ^(NSString *raw) {
        if (raw.length == 0) {
            return;
        }
        NSString *normalized = [self normalizedLocaleIdentifier:raw];
        if (normalized.length == 0 || [seen containsObject:normalized]) {
            return;
        }
        [seen addObject:normalized];
        [result addObject:normalized];
    };

    if ([self.preferenceProvider respondsToSelector:@selector(userPreferredTargetLocales)]) {
        for (id obj in self.preferenceProvider.userPreferredTargetLocales) {
            if ([obj isKindOfClass:[NSString class]]) {
                append((NSString *)obj);
            }
        }
    }
    for (NSString *lang in [NSLocale preferredLanguages]) {
        append(lang);
    }
    append(@"zh-Hans");
    return result;
}

- (NSString *)normalizedLocaleIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return @"";
    }
    NSString *lower = identifier.lowercaseString;
    if ([lower hasPrefix:@"zh-hans"] || [lower isEqualToString:@"zh-cn"] || [lower isEqualToString:@"zh"]) {
        return @"zh-Hans";
    }
    if ([lower hasPrefix:@"zh-hant"] || [lower isEqualToString:@"zh-tw"] || [lower isEqualToString:@"zh-hk"]) {
        return @"zh-Hant";
    }
    NSArray<NSString *> *parts = [identifier componentsSeparatedByString:@"-"];
    if (parts.count == 0) {
        return identifier;
    }
    if (parts.count == 1) {
        return parts[0];
    }
    return [NSString stringWithFormat:@"%@-%@", parts[0], parts[1]];
}

- (NSString *)displayNameForLocaleIdentifier:(NSString *)identifier {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"zh-Hans"];
    NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:identifier];
    return name.length > 0 ? name : identifier;
}

- (void)handleTranslateMenuItem:(NSMenuItem *)sender {
    WKWebView *webView = self.menuWebView;
    BrowserTab *tab = self.menuTab;
    switch ((BrowserPageTranslationMenuAction)sender.tag) {
        case BrowserPageTranslationMenuActionTranslateChinese:
            [self translateWebView:webView
                               tab:tab
                localeIdentifier:@"zh-Hans"
                            mode:BrowserTranslationPresentationModeReplace];
            break;
        case BrowserPageTranslationMenuActionTranslateBilingual:
            [self translateWebView:webView
                               tab:tab
                localeIdentifier:@"zh-Hans"
                            mode:BrowserTranslationPresentationModeBilingual];
            break;
        case BrowserPageTranslationMenuActionTranslateHover:
            [self translateWebView:webView
                               tab:tab
                localeIdentifier:@"zh-Hans"
                            mode:BrowserTranslationPresentationModeHover];
            break;
        case BrowserPageTranslationMenuActionTranslateLocale: {
            NSString *localeID = [sender.representedObject isKindOfClass:[NSString class]]
                ? (NSString *)sender.representedObject
                : nil;
            if (localeID.length > 0) {
                [self translateWebView:webView
                                   tab:tab
                    localeIdentifier:localeID
                                mode:BrowserTranslationPresentationModeReplace];
            }
            break;
        }
        case BrowserPageTranslationMenuActionPreferredLanguagesSettings:
            [self openPreferredLanguagesSettings];
            break;
        case BrowserPageTranslationMenuActionShowOriginal:
            [self.pendingByWebView removeObjectForKey:webView];
            [self showOriginalForWebView:webView];
            break;
        case BrowserPageTranslationMenuActionCancelTranslation:
            [self cancelTranslationForWebView:webView];
            break;
    }
}

#pragma mark - Translate / Original

- (void)translateWebView:(WKWebView *)webView
                     tab:(BrowserTab *)tab
      localeIdentifier:(NSString *)localeID
                  mode:(BrowserTranslationPresentationMode)mode {
    if (![self canTranslateWebView:webView tab:tab] || localeID.length == 0) {
        return;
    }
    NSURL *pageURL = webView.URL ?: [tab currentOrRestorableURL];
    if (pageURL == nil) {
        return;
    }

    // 模式互斥：已翻译时先 reload，再在 commit 后按新模式启动。
    if ([self isShowingTranslationForWebView:webView]) {
        BrowserPageTranslationPendingRequest *pending = [[BrowserPageTranslationPendingRequest alloc] init];
        pending.mode = mode;
        pending.localeID = localeID;
        [self.pendingByWebView setObject:pending forKey:webView];
        [self showOriginalForWebView:webView];
        return;
    }

    BOOL allowSafari = (mode == BrowserTranslationPresentationModeReplace);
    [self startTranslationForWebView:webView
                                 tab:tab
                  localeIdentifier:localeID
                              mode:mode
                 allowSafariEngine:allowSafari];
}

- (void)startTranslationForWebView:(WKWebView *)webView
                               tab:(BrowserTab *)tab
                localeIdentifier:(NSString *)localeID
                            mode:(BrowserTranslationPresentationMode)mode
               allowSafariEngine:(BOOL)allowSafariEngine {
    (void)tab;
    if (webView == nil || localeID.length == 0 || [self isTranslatingWebView:webView]) {
        return;
    }

    [self.presentationModeByWebView setObject:@(mode) forKey:webView];
    [self beginTranslatingUIForWebView:webView];

    if (allowSafariEngine && mode == BrowserTranslationPresentationModeReplace) {
        BOOL trySafari = self.safariEngineAvailable
            && (!self.safariRegionChecked || self.safariRegionSupported);
        id ctx = trySafari ? [self contextForWebView:webView createIfNeeded:YES] : nil;
        if (ctx != nil && [ctx respondsToSelector:NSSelectorFromString(@"requestTranslatingWebpageToLocale:completionHandler:")]) {
            __weak typeof(self) weakSelf = self;
            __weak WKWebView *weakWebView = webView;
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                ctx,
                NSSelectorFromString(@"requestTranslatingWebpageToLocale:completionHandler:"),
                localeID,
                ^(BOOL success) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    WKWebView *strongWebView = weakWebView;
                    if (!strongSelf || !strongWebView) {
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (![strongSelf.translatingWebViews containsObject:strongWebView]) {
                            return; // 已被取消
                        }
                        if (success) {
                            [strongSelf.presentationModeByWebView setObject:@(BrowserTranslationPresentationModeReplace)
                                                                     forKey:strongWebView];
                            [strongSelf finishTranslatingUIForWebView:strongWebView
                                                              success:YES
                                                              message:nil];
                            return;
                        }
                        [strongSelf translateViaPipelineWebView:strongWebView
                                             localeIdentifier:localeID
                                                         mode:BrowserTranslationPresentationModeReplace];
                    });
                });
            return;
        }
    }

    [self translateViaPipelineWebView:webView localeIdentifier:localeID mode:mode];
}

- (void)beginTranslatingUIForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    [self.translatingWebViews addObject:webView];
    [BrowserTransientToast showPersistentMessage:@"正在翻译网页…" inWindow:self.hostWindow];
    [self notifyUIStateDidChange];
}

- (void)translateViaPipelineWebView:(WKWebView *)webView
                 localeIdentifier:(NSString *)localeID
                             mode:(BrowserTranslationPresentationMode)mode {
    if (webView == nil) {
        return;
    }
    if (![self.translatingWebViews containsObject:webView]) {
        [self beginTranslatingUIForWebView:webView];
    }
    [self.presentationModeByWebView setObject:@(mode) forKey:webView];
    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    [[BrowserTranslationPipeline sharedPipeline] translateWebView:webView
                                           targetLocaleIdentifier:localeID
                                                             mode:mode
                                                       completion:^(BOOL success, NSString *errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf) {
            return;
        }
        NSString *message = nil;
        if (success) {
            message = errorMessage; // 可能为「部分段落未译出」
        } else if (errorMessage.length > 0) {
            message = errorMessage;
        } else {
            message = @"已取消翻译";
        }
        [strongSelf finishTranslatingUIForWebView:strongWebView
                                          success:success
                                          message:message];
    }];
}

- (void)cancelTranslationForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }
    [self.pendingByWebView removeObjectForKey:webView];
    BOOL hadPipelineJob = [[BrowserTranslationPipeline sharedPipeline] isTranslatingWebView:webView];
    [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
    if (!hadPipelineJob) {
        // Safari 路径尚未进入页内翻译，或会话已结束：直接收尾 UI。
        [self finishTranslatingUIForWebView:webView success:NO message:@"已取消翻译"];
    }
}

- (void)finishTranslatingUIForWebView:(WKWebView *)webView
                              success:(BOOL)success
                              message:(NSString *)message {
    if (webView != nil) {
        [self.translatingWebViews removeObject:webView];
    }
    [BrowserTransientToast dismissPersistentMessageInWindow:self.hostWindow];

    if (success && webView != nil) {
        [self.inPageTranslatedWebViews addObject:webView];
        [self showToast:(message.length > 0 ? message : @"翻译完成")];
    } else {
        if (webView != nil && ![self.inPageTranslatedWebViews containsObject:webView]) {
            [self.presentationModeByWebView removeObjectForKey:webView];
        }
        if (message.length > 0) {
            [self showToast:message];
        }
    }
    [self notifyUIStateDidChange];
}

- (void)showOriginalForWebView:(WKWebView *)webView {
    if (webView == nil) {
        return;
    }

    if ([self isTranslatingWebView:webView]) {
        [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
        [self.translatingWebViews removeObject:webView];
        [BrowserTransientToast dismissPersistentMessageInWindow:self.hostWindow];
    }

    // 主动「显示原始网页」时清掉 pending（模式切换会先写入 pending 再调用本方法，勿清）。
    // 调用方若设置了 pending，保留之。

    id ctx = [self contextForWebView:webView createIfNeeded:NO];
    BOOL safariTranslated = NO;
    @try {
        safariTranslated = [[ctx valueForKey:@"hasStartedTranslating"] boolValue];
    } @catch (__unused NSException *exception) {
        safariTranslated = NO;
    }
    if (safariTranslated && [ctx respondsToSelector:NSSelectorFromString(@"reloadPageInOriginalLanguage")]) {
        [self.inPageTranslatedWebViews removeObject:webView];
        [self.presentationModeByWebView removeObjectForKey:webView];
        ((void (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"reloadPageInOriginalLanguage"));
        [self notifyUIStateDidChange];
        return;
    }

    [self.inPageTranslatedWebViews removeObject:webView];
    [self.presentationModeByWebView removeObjectForKey:webView];
    [self notifyUIStateDidChange];
    [webView reload];
}

- (void)openPreferredLanguagesSettings {
    NSArray<NSURL *> *candidates = @[
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Localization-Settings.extension"],
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.language"],
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Localization-Settings"],
    ];
    for (NSURL *url in candidates) {
        if (url != nil && [[NSWorkspace sharedWorkspace] openURL:url]) {
            return;
        }
    }
    [self showToast:@"请在「系统设置 › 语言与地区」中管理首选语言"];
}

#pragma mark - WBSTranslationContextDelegate (informal)

- (NSString *)safariApplicationVersionForTranslationContext:(id)ctx {
    (void)ctx;
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
}

- (BOOL)translationContextIsUsingPrivateBrowsing:(id)ctx {
    (void)ctx;
    return NO;
}

- (void)translationContext:(id)ctx urlForCurrentPageWithCompletionHandler:(void (^)(NSURL *))handler {
    WKWebView *webView = [self webViewForTranslationContext:ctx];
    if (handler) {
        handler(webView.URL);
    }
}

- (void)translationContextWillRequestTranslatingWebpage:(id)ctx {
    (void)ctx;
}

- (void)translationContextReloadPageInOriginalLanguage:(id)ctx {
    WKWebView *webView = [self webViewForTranslationContext:ctx];
    [webView reload];
}

- (void)translationContext:(id)ctx showFirstTimeConsentAlertWithCompletionHandler:(void (^)(BOOL))handler {
    (void)ctx;
    if (handler) {
        handler(YES);
    }
}

- (void)translationContext:(id)ctx showFeedbackConsentAlertWithCompletionHandler:(void (^)(BOOL))handler {
    (void)ctx;
    if (handler) {
        handler(NO);
    }
}

- (void)translationContext:(id)ctx showTranslationErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    (void)ctx;
    NSString *text = message.length > 0 ? message : (title.length > 0 ? title : @"翻译失败");
    [self showToast:text];
}

- (void)translationContext:(id)ctx shouldReportProgressInUnifiedField:(BOOL)flag {
    (void)ctx;
    (void)flag;
}

- (void)translationContextNeedsScrollHeightVisibilityUpdate:(id)ctx {
    (void)ctx;
}

#pragma mark - Toast

- (void)showToast:(NSString *)message {
    NSWindow *window = self.hostWindow;
    if (window == nil || message.length == 0) {
        return;
    }
    [BrowserTransientToast showMessage:message inWindow:window duration:2.4];
}

@end
