#import "BrowserTabUIDiagnostics.h"
#import "BrowserTab.h"
#import "BrowserRiskHostPolicy.h"

#import <QuartzCore/QuartzCore.h>
#import <os/log.h>
#import <stdatomic.h>
#import <stdio.h>
#import <sys/stat.h>

static NSString * const kMeoTabUIDiagnosticsKey = @"MeoBrowserTabUIDiagnostics";
static NSString * const kMeoTabUISlowMsKey = @"MeoBrowserTabUISlowMs";
static NSString * const kMeoTabUIHangMsKey = @"MeoBrowserTabUIHangMs";

static const NSTimeInterval kDefaultSlowMs = 50.0;
static const NSTimeInterval kDefaultHangMs = 120.0;
static const NSTimeInterval kHangPollInterval = 0.05;

static CFRunLoopObserverRef sHangObserver = NULL;
static dispatch_source_t sHangTimer = NULL;
static atomic_uint_fast64_t sLastMainTickNs = 0;
static atomic_bool sHangLogged = false;
static NSTimeInterval sLoggedHangMs = 0;
static FILE *sLogFile = NULL;
static dispatch_once_t sLogFileOnce;
static os_log_t sTabUILog;

static os_log_t MeoTabUIOSLog(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTabUILog = os_log_create("com.example.MeoBrowser", "TabUI");
    });
    return sTabUILog;
}

static void MeoTabUIEnsureLogFile(void) {
    dispatch_once(&sLogFileOnce, ^{
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MeoBrowser"];
        mkdir(dir.fileSystemRepresentation, 0755);
        NSString *path = [dir stringByAppendingPathComponent:@"tab-ui.log"];
        sLogFile = fopen(path.fileSystemRepresentation, "a");
        if (sLogFile) {
            setvbuf(sLogFile, NULL, _IOLBF, 0);
            fprintf(sLogFile, "\n==== MeoTabUI session %s ====\n",
                    [[NSDate date].description UTF8String] ?: "");
            fflush(sLogFile);
        }
    });
}

BOOL BrowserTabUIDiagnosticsEnabled(void) {
    // 未写过 key 时默认开（便于排查卡顿）；显式 NO 才关。
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kMeoTabUIDiagnosticsKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kMeoTabUIDiagnosticsKey];
}

NSTimeInterval BrowserTabUISlowThresholdMs(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kMeoTabUISlowMsKey];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        NSTimeInterval ms = [value doubleValue];
        if (ms >= 1.0) {
            return ms;
        }
    }
    return kDefaultSlowMs;
}

NSTimeInterval BrowserTabUIHangThresholdMs(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kMeoTabUIHangMsKey];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        NSTimeInterval ms = [value doubleValue];
        if (ms >= 20.0) {
            return ms;
        }
    }
    return kDefaultHangMs;
}

void BrowserTabUILog(NSString *format, ...) {
    if (!BrowserTabUIDiagnosticsEnabled() || format.length == 0) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 1) stderr / Console（从终端启动时直接可见）
    NSLog(@"[MeoTabUI] %@", message);
    // 2) unified logging（log stream 用 subsystem/category 过滤）
    os_log_with_type(MeoTabUIOSLog(), OS_LOG_TYPE_DEFAULT, "%{public}@", message);

    // 3) 文件：tail -f ~/Library/Logs/MeoBrowser/tab-ui.log
    MeoTabUIEnsureLogFile();
    if (sLogFile) {
        NSString *line = [NSString stringWithFormat:@"%@ [MeoTabUI] %@\n",
                          [NSDate date], message];
        fputs(line.UTF8String, sLogFile);
        fflush(sLogFile);
    }
}

NSTimeInterval BrowserTabUIMeasure(NSString *label, NS_NOESCAPE void (^block)(void)) {
    CFTimeInterval t0 = CACurrentMediaTime();
    if (block) {
        block();
    }
    NSTimeInterval ms = (CACurrentMediaTime() - t0) * 1000.0;
    if (!BrowserTabUIDiagnosticsEnabled()) {
        return ms;
    }
    NSTimeInterval slow = BrowserTabUISlowThresholdMs();
    if (ms >= slow) {
        BrowserTabUILog(@"SLOW %@ %.1fms (threshold %.0fms)", label, ms, slow);
    } else {
        BrowserTabUILog(@"%@ %.1fms", label, ms);
    }
    return ms;
}

void BrowserTabUILogInventory(NSArray<BrowserTab *> *tabs,
                              BrowserTab *selectedTab,
                              NSUInteger liveInWindow,
                              NSUInteger liveGlobal) {
    if (!BrowserTabUIDiagnosticsEnabled()) {
        return;
    }
    NSUInteger mediaHeavy = 0;
    NSUInteger audible = 0;
    NSUInteger protectedLive = 0;
    NSUInteger hibernated = 0;
    NSUInteger ntp = 0;
    NSMutableArray<NSString *> *liveBriefs = [NSMutableArray array];
    for (BrowserTab *tab in tabs) {
        if (tab.isNewTabPage) {
            ntp++;
        }
        if (tab.isHibernated) {
            hibernated++;
        }
        if (tab.mediaHeavy) {
            mediaHeavy++;
        }
        if (tab.isAudible) {
            audible++;
        }
        WKWebView *wv = tab.webView;
        if (wv == nil) {
            continue;
        }
        NSURL *url = wv.URL ?: tab.restorableURL;
        BOOL isProtected = [BrowserRiskHostPolicy URLIsHibernationProtected:url];
        if (isProtected) {
            protectedLive++;
        }
        NSString *host = url.host.length > 0 ? url.host : (tab.isNewTabPage ? @"ntp" : @"?");
        NSString *flags = [NSString stringWithFormat:@"%@%@%@%@",
                           (tab == selectedTab) ? @"*" : @"",
                           tab.mediaHeavy ? @"H" : @"",
                           tab.isAudible ? @"A" : @"",
                           isProtected ? @"P" : @""];
        [liveBriefs addObject:[NSString stringWithFormat:@"%@[%@]", host, flags]];
    }
    BrowserTabUILog(@"inventory tabs=%lu live=%lu/%lu mediaHeavy=%lu audible=%lu protectedLive=%lu hibernated=%lu ntp=%lu selected=%@ | %@",
                    (unsigned long)tabs.count,
                    (unsigned long)liveInWindow,
                    (unsigned long)liveGlobal,
                    (unsigned long)mediaHeavy,
                    (unsigned long)audible,
                    (unsigned long)protectedLive,
                    (unsigned long)hibernated,
                    (unsigned long)ntp,
                    selectedTab.title.length > 0 ? selectedTab.title : @"(nil)",
                    [liveBriefs componentsJoinedByString:@" "]);
}

static uint64_t MeoNowNs(void) {
    return (uint64_t)(CACurrentMediaTime() * 1e9);
}

static void MeoHangObserverCallback(CFRunLoopObserverRef observer,
                                    CFRunLoopActivity activity,
                                    void *info) {
    (void)observer;
    (void)activity;
    (void)info;
    atomic_store_explicit(&sLastMainTickNs, MeoNowNs(), memory_order_relaxed);
    if (atomic_exchange_explicit(&sHangLogged, false, memory_order_relaxed)) {
        NSTimeInterval hangMs = sLoggedHangMs;
        sLoggedHangMs = 0;
        BrowserTabUILog(@"HANG recovered (was %.0fms)", hangMs);
    }
}

void BrowserTabUIDiagnosticsStopHangWatchdog(void) {
    if (sHangTimer != NULL) {
        dispatch_source_cancel(sHangTimer);
        sHangTimer = NULL;
    }
    if (sHangObserver != NULL) {
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), sHangObserver, kCFRunLoopCommonModes);
        CFRelease(sHangObserver);
        sHangObserver = NULL;
    }
    atomic_store_explicit(&sHangLogged, false, memory_order_relaxed);
}

void BrowserTabUIDiagnosticsStartHangWatchdogIfNeeded(void) {
    if (!BrowserTabUIDiagnosticsEnabled()) {
        NSLog(@"[MeoTabUI] diagnostics OFF. Enable: defaults write com.example.MeoBrowser MeoBrowserTabUIDiagnostics -bool YES");
        return;
    }
    if (sHangObserver != NULL) {
        return;
    }

    MeoTabUIEnsureLogFile();
    atomic_store_explicit(&sLastMainTickNs, MeoNowNs(), memory_order_relaxed);

    CFRunLoopObserverContext ctx = {0, NULL, NULL, NULL, NULL};
    sHangObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                            kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting | kCFRunLoopBeforeSources | kCFRunLoopBeforeTimers,
                                            true,
                                            0,
                                            MeoHangObserverCallback,
                                            &ctx);
    CFRunLoopAddObserver(CFRunLoopGetMain(), sHangObserver, kCFRunLoopCommonModes);

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    sHangTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(sHangTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(kHangPollInterval * NSEC_PER_SEC),
                              (uint64_t)(0.01 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(sHangTimer, ^{
        uint64_t last = atomic_load_explicit(&sLastMainTickNs, memory_order_relaxed);
        if (last == 0) {
            return;
        }
        NSTimeInterval stalledMs = (MeoNowNs() - last) / 1e6;
        NSTimeInterval threshold = BrowserTabUIHangThresholdMs();
        if (stalledMs < threshold) {
            return;
        }
        static NSTimeInterval sLastReportedMs = 0;
        BOOL first = !atomic_load_explicit(&sHangLogged, memory_order_relaxed);
        if (!first && stalledMs < sLastReportedMs + 250.0) {
            return;
        }
        sLastReportedMs = stalledMs;
        sLoggedHangMs = stalledMs;
        atomic_store_explicit(&sHangLogged, true, memory_order_relaxed);
        // 卡顿时主线程可能堵死，文件/os_log 仍可从后台队列写出。
        NSString *msg = [NSString stringWithFormat:
                         @"HANG main-thread blocked ~%.0fms (threshold %.0fms)",
                         stalledMs, threshold];
        os_log_with_type(MeoTabUIOSLog(), OS_LOG_TYPE_ERROR, "%{public}@", msg);
        MeoTabUIEnsureLogFile();
        if (sLogFile) {
            fprintf(sLogFile, "%s [MeoTabUI] %s\n",
                    [[NSDate date].description UTF8String] ?: "",
                    msg.UTF8String);
            fflush(sLogFile);
        }
        NSLog(@"[MeoTabUI] %@", msg);
    });
    dispatch_resume(sHangTimer);

    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MeoBrowser/tab-ui.log"];
    BrowserTabUILog(@"hang watchdog started (hang≥%.0fms, slow≥%.0fms). log file: %@ — tail -f that path",
                    BrowserTabUIHangThresholdMs(),
                    BrowserTabUISlowThresholdMs(),
                    logPath);
}
