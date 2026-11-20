#import "BrowserPageTranslationController.h"
#import "BrowserAutoTranslatePreferences.h"
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
    BrowserPageTranslationMenuActionToggleAlwaysEnglish,
    BrowserPageTranslationMenuActionEnableSiteAlways,
    BrowserPageTranslationMenuActionDisableSiteAlways,
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
/// 每个 WebView 最近一次自动翻译的 URL 字符串，避免同次导航重复触发。
@property (nonatomic, strong) NSMapTable<WKWebView *, NSString *> *lastAutoTranslateURLByWebView;
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
        _lastAutoTranslateURLByWebView = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
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
    [self.lastAutoTranslateURLByWebView removeObjectForKey:webView];
    [self notifyUIStateDidChange];
}

- (void)webViewDidCommitNavigation:(WKWebView *)webView URL:(NSURL *)url {
    if (webView == nil) {
        return;
    }
    // 保留 pending：等 didFinish 再启动，避免 commit 时 DOM 仍空导致「未找到可翻译文本」。

    // 新文档：取消进行中的翻译，清除译文态；清除自动译去重键以便新页可触发。
    if ([self.translatingWebViews containsObject:webView]) {
        [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView];
        [self.translatingWebViews removeObject:webView];
        [BrowserTransientToast dismissPersistentMessageInWindow:self.hostWindow];
    }
    [self.inPageTranslatedWebViews removeObject:webView];
    [self.presentationModeByWebView removeObjectForKey:webView];
    [self.lastAutoTranslateURLByWebView removeObjectForKey:webView];
    [self notifyUIStateDidChange];

    id ctx = [self contextForWebView:webView createIfNeeded:YES];
    if (ctx != nil) {
        SEL sel = NSSelectorFromString(@"owningWebViewDidCommitNavigationWithURL:completionHandler:");
        if ([ctx respondsToSelector:sel]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(ctx, sel, url, ^{});
        }
    }
}

- (void)webViewDidFinishNavigation:(WKWebView *)webView URL:(NSURL *)url tab:(BrowserTab *)tab {
    if (webView == nil) {
        return;
    }
    BrowserPageTranslationPendingRequest *pending = [self.pendingByWebView objectForKey:webView];
    if (pending != nil && pending.localeID.length > 0) {
        [self.pendingByWebView removeObjectForKey:webView];
        __weak typeof(self) weakSelf = self;
        __weak WKWebView *weakWebView = webView;
        __weak BrowserTab *weakTab = tab;
        // 再让出一拍，等首屏脚本/异步正文落地。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            WKWebView *strongWebView = weakWebView;
            if (!self || !strongWebView) {
                return;
            }
            [self startTranslationForWebView:strongWebView
                                         tab:weakTab
                          localeIdentifier:pending.localeID
                                      mode:pending.mode
                         allowSafariEngine:NO];
        });
        return;
    }

    [self considerAutoTranslateForWebView:webView tab:tab URL:url];
}

- (void)detectPageLanguageInWebView:(WKWebView *)webView
                         completion:(void (^)(NSString * _Nullable language))completion {
    if (!webView || !completion) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    NSString *js =
        @"(function(){"
        @"var lang=(document.documentElement.lang||document.documentElement.getAttribute('xml:lang')||'').toLowerCase().trim();"
        @"if(lang){return lang.split(/[_-]/)[0];}"
        @"var t=((document.body&&document.body.innerText)||'').slice(0,2500);"
        @"var cjk=(t.match(/[\\u4e00-\\u9fff]/g)||[]).length;"
        @"var latin=(t.match(/[A-Za-z]/g)||[]).length;"
        @"if(cjk>latin*0.35){return 'zh';}"
        @"if(latin>50){return 'en';}"
        @"return '';"
        @"})()";
    [webView evaluateJavaScript:js completionHandler:^(id value, NSError *error) {
        (void)error;
        NSString *lang = [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
        completion(lang.length > 0 ? lang : nil);
    }];
}

- (void)considerAutoTranslateForWebView:(WKWebView *)webView tab:(BrowserTab *)tab URL:(NSURL *)url {
    if (![self canTranslateWebView:webView tab:tab]) {
        return;
    }
    NSURL *pageURL = url ?: webView.URL ?: [tab currentOrRestorableURL];
    if (![BrowsingPreferences isPersistableURL:pageURL]) {
        return;
    }
    NSString *urlKey = pageURL.absoluteString ?: @"";
    NSString *lastKey = [self.lastAutoTranslateURLByWebView objectForKey:webView];
    if (urlKey.length > 0 && [lastKey isEqualToString:urlKey]) {
        return;
    }

    BrowserAutoTranslatePreferences *prefs = BrowserAutoTranslatePreferences.sharedPreferences;
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:pageURL];
    // 本站已显式开启：无需等语言检测。
    BOOL hostEnabled = [prefs isHostExplicitlyEnabled:host];
    BOOL hostDisabled = [prefs isHostExplicitlyDisabled:host];
    if (hostDisabled) {
        return;
    }
    if (!hostEnabled && !prefs.alwaysTranslateEnglish) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    __weak BrowserTab *weakTab = tab;
    void (^startIfNeeded)(NSString *) = ^(NSString *language) {
        typeof(self) self = weakSelf;
        WKWebView *strongWebView = weakWebView;
        BrowserTab *strongTab = weakTab;
        if (!self || !strongWebView) {
            return;
        }
        if (![prefs shouldAutoTranslateURL:pageURL pageLanguage:language]) {
            return;
        }
        if ([self isTranslatingWebView:strongWebView] || [self isShowingTranslationForWebView:strongWebView]) {
            return;
        }
        if (urlKey.length > 0) {
            [self.lastAutoTranslateURLByWebView setObject:urlKey forKey:strongWebView];
        }
        [self translateWebView:strongWebView
                           tab:strongTab
            localeIdentifier:@"zh-Hans"
                        mode:BrowserTranslationPresentationModeReplace];
    };

    if (hostEnabled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            startIfNeeded(nil);
        });
        return;
    }

    [self detectPageLanguageInWebView:webView completion:^(NSString *language) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            startIfNeeded(language);
        });
    }];
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

    NSURL *pageURL = webView.URL ?: [tab currentOrRestorableURL];
    NSString *host = [BrowserAutoTranslatePreferences normalizedHostFromURL:pageURL];
    BrowserAutoTranslatePreferences *autoPrefs = BrowserAutoTranslatePreferences.sharedPreferences;

    NSMenuItem *alwaysEnglishItem = [[NSMenuItem alloc] initWithTitle:@"始终翻译英文网站"
                                                               action:@selector(handleTranslateMenuItem:)
                                                        keyEquivalent:@""];
    alwaysEnglishItem.target = self;
    alwaysEnglishItem.tag = BrowserPageTranslationMenuActionToggleAlwaysEnglish;
    alwaysEnglishItem.state = autoPrefs.alwaysTranslateEnglish ? NSControlStateValueOn : NSControlStateValueOff;
    alwaysEnglishItem.enabled = YES;
    [menu addItem:alwaysEnglishItem];

    if (host.length > 0 && pageOK) {
        BOOL siteOn = [autoPrefs isHostExplicitlyEnabled:host];
        NSString *siteTitle = siteOn
            ? [NSString stringWithFormat:@"取消默认翻译 %@", host]
            : [NSString stringWithFormat:@"默认翻译 %@", host];
        NSMenuItem *siteItem = [[NSMenuItem alloc] initWithTitle:siteTitle
                                                          action:@selector(handleTranslateMenuItem:)
                                                   keyEquivalent:@""];
        siteItem.target = self;
        siteItem.tag = siteOn ? BrowserPageTranslationMenuActionDisableSiteAlways
                              : BrowserPageTranslationMenuActionEnableSiteAlways;
        siteItem.representedObject = pageURL;
        siteItem.state = siteOn ? NSControlStateValueOn : NSControlStateValueOff;
        siteItem.enabled = YES;
        [menu addItem:siteItem];
    }

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
        case BrowserPageTranslationMenuActionToggleAlwaysEnglish: {
            BrowserAutoTranslatePreferences *prefs = BrowserAutoTranslatePreferences.sharedPreferences;
            prefs.alwaysTranslateEnglish = !prefs.alwaysTranslateEnglish;
            if (prefs.alwaysTranslateEnglish && [self canTranslateWebView:webView tab:tab]) {
                [self considerAutoTranslateForWebView:webView
                                                   tab:tab
                                                   URL:(webView.URL ?: [tab currentOrRestorableURL])];
            }
            break;
        }
        case BrowserPageTranslationMenuActionEnableSiteAlways: {
            NSURL *siteURL = [sender.representedObject isKindOfClass:[NSURL class]]
                ? (NSURL *)sender.representedObject
                : (webView.URL ?: [tab currentOrRestorableURL]);
            [[BrowserAutoTranslatePreferences sharedPreferences] enableAutoTranslateForURL:siteURL];
            if ([self canTranslateWebView:webView tab:tab]) {
                [self translateWebView:webView
                                   tab:tab
                    localeIdentifier:@"zh-Hans"
                                mode:BrowserTranslationPresentationModeReplace];
            }
            break;
        }
        case BrowserPageTranslationMenuActionDisableSiteAlways: {
            NSURL *siteURL = [sender.representedObject isKindOfClass:[NSURL class]]
                ? (NSURL *)sender.representedObject
                : (webView.URL ?: [tab currentOrRestorableURL]);
            [[BrowserAutoTranslatePreferences sharedPreferences] disableAutoTranslateForURL:siteURL];
            break;
        }
    }
}

#pragma mark - Translate / Original

- (BOOL)isSafariTranslatedWebView:(WKWebView *)webView {
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

    // 已翻译：同模式再点 → 续译未完成段落；换模式 → 对照/悬停可就地清注入再译。
    // 替换模式或 Safari 译文必须 reload 才能恢复原文。
    if ([self isShowingTranslationForWebView:webView]) {
        BOOL safariTranslated = [self isSafariTranslatedWebView:webView];
        NSNumber *currentModeNum = [self.presentationModeByWebView objectForKey:webView];
        BrowserTranslationPresentationMode currentMode =
            currentModeNum ? (BrowserTranslationPresentationMode)currentModeNum.integerValue
                           : BrowserTranslationPresentationModeReplace;
        // 对照/悬停：同模式再点 → 续译未完成段落（不 clear）。
        BOOL sameJSMode =
            !safariTranslated
            && mode == currentMode
            && mode != BrowserTranslationPresentationModeReplace
            && currentMode != BrowserTranslationPresentationModeReplace;
        if (sameJSMode) {
            [self startTranslationForWebView:webView
                                         tab:tab
                          localeIdentifier:localeID
                                      mode:mode
                         allowSafariEngine:NO
                         resumeIncomplete:YES];
            return;
        }

        BOOL canRetranslateInPlace =
            !safariTranslated
            && mode != BrowserTranslationPresentationModeReplace
            && currentMode != BrowserTranslationPresentationModeReplace;

        if (canRetranslateInPlace) {
            __weak typeof(self) weakSelf = self;
            __weak WKWebView *weakWebView = webView;
            [[BrowserTranslationPipeline sharedPipeline] clearPagePresentationInWebView:webView completion:^{
                typeof(self) self = weakSelf;
                WKWebView *strongWebView = weakWebView;
                if (!self || !strongWebView) {
                    return;
                }
                [self.inPageTranslatedWebViews removeObject:strongWebView];
                [self.presentationModeByWebView removeObjectForKey:strongWebView];
                [self notifyUIStateDidChange];
                [self startTranslationForWebView:strongWebView
                                             tab:tab
                              localeIdentifier:localeID
                                          mode:mode
                             allowSafariEngine:NO
                             resumeIncomplete:NO];
            }];
            return;
        }

        // 替换模式：WK TextManipulation 在已替换 DOM 上常抽不到词，再点会误报「未找到可翻译文本」。
        // 因此同模式再点改为恢复原文后整页重译（pending）。
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
                 allowSafariEngine:allowSafari
                 resumeIncomplete:NO];
}

- (void)startTranslationForWebView:(WKWebView *)webView
                               tab:(BrowserTab *)tab
                localeIdentifier:(NSString *)localeID
                            mode:(BrowserTranslationPresentationMode)mode
               allowSafariEngine:(BOOL)allowSafariEngine {
    [self startTranslationForWebView:webView
                                 tab:tab
                  localeIdentifier:localeID
                              mode:mode
                 allowSafariEngine:allowSafariEngine
                 resumeIncomplete:NO];
}

- (void)startTranslationForWebView:(WKWebView *)webView
                               tab:(BrowserTab *)tab
                localeIdentifier:(NSString *)localeID
                            mode:(BrowserTranslationPresentationMode)mode
               allowSafariEngine:(BOOL)allowSafariEngine
               resumeIncomplete:(BOOL)resumeIncomplete {
    (void)tab;
    if (webView == nil || localeID.length == 0 || [self isTranslatingWebView:webView]) {
        return;
    }

    [self.presentationModeByWebView setObject:@(mode) forKey:webView];
    [self beginTranslatingUIForWebView:webView];

    if (!resumeIncomplete && allowSafariEngine && mode == BrowserTranslationPresentationModeReplace) {
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
                                                         mode:BrowserTranslationPresentationModeReplace
                                            resumeIncomplete:NO];
                    });
                });
            return;
        }
    }

    [self translateViaPipelineWebView:webView
                   localeIdentifier:localeID
                               mode:mode
                  resumeIncomplete:resumeIncomplete];
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
    [self translateViaPipelineWebView:webView
                   localeIdentifier:localeID
                               mode:mode
                  resumeIncomplete:NO];
}

- (void)translateViaPipelineWebView:(WKWebView *)webView
                 localeIdentifier:(NSString *)localeID
                             mode:(BrowserTranslationPresentationMode)mode
                resumeIncomplete:(BOOL)resumeIncomplete {
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
                                                resumeIncomplete:resumeIncomplete
                                                       completion:^(BOOL success, NSString *errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf) {
            return;
        }
        NSString *message = nil;
        if (success) {
            message = errorMessage; // 可能为限流提示 / 「部分段落未译出」
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
    [[BrowserTranslationPipeline sharedPipeline] cancelTranslationForWebView:webView
                                                             cancelMessage:@"已取消翻译，可再次点击继续"];
    if (!hadPipelineJob) {
        // Safari 路径尚未进入页内翻译，或会话已结束：直接收尾 UI。
        [self finishTranslatingUIForWebView:webView success:NO message:@"已取消翻译，可再次点击继续"];
    }
}

- (void)finishTranslatingUIForWebView:(WKWebView *)webView
                              success:(BOOL)success
                              message:(NSString *)message {
    if (webView != nil) {
        [self.translatingWebViews removeObject:webView];
    }
    [BrowserTransientToast dismissPersistentMessageInWindow:self.hostWindow];

    // 超时/限流等中断时页面上往往已有部分译文：仍记为「已翻译」，便于对照/悬停续译。
    BOOL keepPartial = !success && message.length > 0
        && ([message containsString:@"超时"]
            || [message containsString:@"限流"]
            || [message containsString:@"繁忙"]
            || [message containsString:@"继续"]
            || [message containsString:@"部分"]
            || [message containsString:@"未译"]);
    if ((success || keepPartial) && webView != nil) {
        [self.inPageTranslatedWebViews addObject:webView];
        NSString *toast = message.length > 0 ? message : @"翻译完成";
        if (keepPartial && ![toast containsString:@"继续"]) {
            toast = [toast stringByAppendingString:@"，可再次点击翻译继续"];
        }
        [self showToast:toast];
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
    // 含「继续」/限流等中断说明时多显示一会儿，方便用户看到。
    BOOL longer = [message containsString:@"继续"]
        || [message containsString:@"限流"]
        || [message containsString:@"繁忙"]
        || [message containsString:@"不可用"];
    [BrowserTransientToast showMessage:message inWindow:window duration:longer ? 4.2 : 2.4];
}

@end
