#import "BrowserTabAudioController.h"
#import "BrowserTab.h"

#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSTimeInterval kBrowserTabAudioPollInterval = 0.75;
static const NSInteger kBrowserTabAudioFalseStreakToClear = 2;
/// _WKMediaAudioMuted
static const NSUInteger kBrowserTabMediaAudioMuted = 1U << 0;

@interface BrowserTabAudioController ()
@property (nonatomic, copy, nullable) NSArray<BrowserTab *> * (^tabProvider)(void);
@property (nonatomic, strong, nullable) NSTimer *pollTimer;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSNumber *> *falseAudibleStreakByTabID;
@property (nonatomic, assign) NSInteger pollGeneration;
@end

@implementation BrowserTabAudioController

- (instancetype)init {
    self = [super init];
    if (self) {
        _falseAudibleStreakByTabID = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

- (void)startMonitoringWithTabProvider:(NSArray<BrowserTab *> * (^)(void))tabProvider {
    self.tabProvider = [tabProvider copy];
    if (self.pollTimer != nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer timerWithTimeInterval:kBrowserTabAudioPollInterval
                                            repeats:YES
                                              block:^(NSTimer *timer) {
                                                  (void)timer;
                                                  [weakSelf pollAllTabs];
                                              }];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    [self pollAllTabs];
}

- (void)stopMonitoring {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    self.tabProvider = nil;
    [self.falseAudibleStreakByTabID removeAllObjects];
}

#pragma mark - Public mute API

- (void)toggleMuteForTab:(BrowserTab *)tab {
    if (tab == nil) {
        return;
    }
    tab.isPageMutedByUser = !tab.isPageMutedByUser;
    [self applyMuteStateForTab:tab];
    if (self.audibleStateDidChangeHandler) {
        self.audibleStateDidChangeHandler();
    }
}

- (void)clearUserMuteForTabAfterNavigation:(BrowserTab *)tab {
    if (tab == nil || !tab.isPageMutedByUser) {
        return;
    }
    tab.isPageMutedByUser = NO;
    [self applyMuteStateForTab:tab];
    if (self.audibleStateDidChangeHandler) {
        self.audibleStateDidChangeHandler();
    }
}

- (void)applyMuteStateForTab:(BrowserTab *)tab {
    WKWebView *webView = tab.webView;
    if (webView == nil) {
        return;
    }
    BOOL muted = tab.isPageMutedByUser;
    if ([self trySetPageMuted:muted onWebView:webView]) {
        return;
    }
    [self applyJavaScriptMute:muted onWebView:webView];
}

#pragma mark - Polling

- (void)pollAllTabs {
    NSArray<BrowserTab *> * (^provider)(void) = self.tabProvider;
    if (provider == nil) {
        return;
    }
    NSArray<BrowserTab *> *tabs = provider();
    if (tabs.count == 0) {
        return;
    }

    self.pollGeneration += 1;
    NSInteger generation = self.pollGeneration;
    NSMutableSet<NSUUID *> *liveIDs = [NSMutableSet setWithCapacity:tabs.count];

    for (BrowserTab *tab in tabs) {
        [liveIDs addObject:tab.tabID];
        WKWebView *webView = tab.webView;
        if (webView == nil || tab.isNewTabPage || tab.isHibernated) {
            [self applyAudible:NO forTab:tab];
            continue;
        }
        [self sampleAudibleForTab:tab webView:webView generation:generation];
    }

    NSArray<NSUUID *> *stale = [self.falseAudibleStreakByTabID.allKeys filteredArrayUsingPredicate:
                                [NSPredicate predicateWithBlock:^BOOL(NSUUID *tabID, NSDictionary *bindings) {
                                    (void)bindings;
                                    return ![liveIDs containsObject:tabID];
                                }]];
    for (NSUUID *tabID in stale) {
        [self.falseAudibleStreakByTabID removeObjectForKey:tabID];
    }
}

- (void)sampleAudibleForTab:(BrowserTab *)tab
                    webView:(WKWebView *)webView
                 generation:(NSInteger)generation {
    BOOL spiAudible = NO;
    BOOL hasSPI = [self readIsPlayingAudio:&spiAudible fromWebView:webView];
    if (hasSPI) {
        [self noteAudibleSample:spiAudible forTab:tab];
        return;
    }

    if (@available(macOS 12.0, *)) {
        __weak typeof(self) weakSelf = self;
        __weak BrowserTab *weakTab = tab;
        [webView requestMediaPlaybackStateWithCompletionHandler:^(WKMediaPlaybackState state) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            BrowserTab *strongTab = weakTab;
            if (!strongSelf || !strongTab) {
                return;
            }
            if (generation != strongSelf.pollGeneration) {
                return;
            }
            BOOL playing = (state == WKMediaPlaybackStatePlaying);
            [strongSelf noteAudibleSample:playing forTab:strongTab];
        }];
        return;
    }

    [self noteAudibleSample:NO forTab:tab];
}

- (void)noteAudibleSample:(BOOL)audible forTab:(BrowserTab *)tab {
    NSUUID *tabID = tab.tabID;
    if (audible) {
        self.falseAudibleStreakByTabID[tabID] = @0;
        [self applyAudible:YES forTab:tab];
        return;
    }

    NSInteger streak = self.falseAudibleStreakByTabID[tabID].integerValue + 1;
    self.falseAudibleStreakByTabID[tabID] = @(streak);
    if (streak >= kBrowserTabAudioFalseStreakToClear) {
        [self applyAudible:NO forTab:tab];
    }
}

- (void)applyAudible:(BOOL)audible forTab:(BrowserTab *)tab {
    if (tab.isAudible == audible) {
        return;
    }
    tab.isAudible = audible;
    if (audible) {
        tab.mediaHeavy = YES;
    }
    if (self.audibleStateDidChangeHandler) {
        self.audibleStateDidChangeHandler();
    }
}

#pragma mark - WebKit SPI / JS

- (BOOL)readIsPlayingAudio:(BOOL *)outAudible fromWebView:(WKWebView *)webView {
    SEL selector = NSSelectorFromString(@"_isPlayingAudio");
    if (![webView respondsToSelector:selector]) {
        return NO;
    }
    BOOL playing = ((BOOL (*)(id, SEL))objc_msgSend)(webView, selector);
    if (outAudible) {
        *outAudible = playing;
    }
    return YES;
}

- (BOOL)trySetPageMuted:(BOOL)muted onWebView:(WKWebView *)webView {
    SEL selector = NSSelectorFromString(@"_setPageMuted:");
    if (![webView respondsToSelector:selector]) {
        return NO;
    }
    NSUInteger state = muted ? kBrowserTabMediaAudioMuted : 0;
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(webView, selector, state);
    return YES;
}

- (void)applyJavaScriptMute:(BOOL)muted onWebView:(WKWebView *)webView {
    NSString *mutedLiteral = muted ? @"true" : @"false";
    NSString *script = [NSString stringWithFormat:
                        @"(function(){"
                         "var m=%@;"
                         "try{"
                         "  document.querySelectorAll('video,audio').forEach(function(el){"
                         "    try{ el.muted=m; }catch(e){}"
                         "  });"
                         "}catch(e){}"
                         "try{"
                         "  if(window.__meoAudioContexts){"
                         "    window.__meoAudioContexts.forEach(function(c){"
                         "      try{ m ? c.suspend() : c.resume(); }catch(e){}"
                         "    });"
                         "  }"
                         "}catch(e){}"
                         "})();",
                        mutedLiteral];
    [webView evaluateJavaScript:script completionHandler:nil];
}

@end
