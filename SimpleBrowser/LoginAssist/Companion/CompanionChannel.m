#import "CompanionChannel.h"
#import "CompanionBonjourServer.h"
#import "CompanionPairingStore.h"
#import "CompanionShortcutSync.h"
#import "CompanionSyncSettings.h"
#import "CompanionBrowseSyncStore.h"
#import "OTPInbox.h"
#import "PhoneNotificationPresenter.h"
#import "AppDelegate.h"
#import "BrowserWindowController.h"
#import <AppKit/AppKit.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

NSNotificationName const CompanionChannelStateDidChangeNotification = @"CompanionChannelStateDidChangeNotification";

@interface CompanionChannel () <CompanionBonjourServerDelegate>
@property (nonatomic, strong) CompanionBonjourServer *server;
@property (nonatomic, assign, readwrite) CompanionChannelState state;
@property (nonatomic, copy, readwrite, nullable) NSString *statusText;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
@property (nonatomic, copy, readwrite, nullable) NSString *lastConnectedDeviceId;
@property (nonatomic, assign, readwrite) BOOL usingTemporaryPort;
@property (nonatomic, strong) NSMutableSet<NSString *> *activeConnectionIDs;
@property (nonatomic, assign) BOOL intentionallyChangingPort;
@end

@implementation CompanionChannel

+ (instancetype)sharedChannel {
    static CompanionChannel *channel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        channel = [[self alloc] init];
    });
    return channel;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _server = [[CompanionBonjourServer alloc] init];
        _server.delegate = self;
        _activeConnectionIDs = [NSMutableSet set];
        _state = CompanionChannelStateStopped;
        _statusText = @"未启动";
    }
    return self;
}

- (void)start {
    if (self.state != CompanionChannelStateStopped) {
        return;
    }
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    NSInteger preferred = store.stickyListeningPort;
    NSError *error = nil;
    if (![self.server startWithPreferredPort:preferred error:&error]) {
        self.state = CompanionChannelStateStopped;
        self.statusText = error.localizedDescription ?: @"启动失败";
        [self postStateChange];
        return;
    }
    (void)[self ensurePairingCode];
    self.state = CompanionChannelStateAdvertising;
    if (store.authMode == CompanionAuthModeSecurityCode) {
        self.statusText = store.securityCode.length > 0
            ? @"等待手机连接（安全码模式）"
            : @"请先在设置中设定固定安全码";
    } else {
        self.statusText = @"等待手机连接（Bonjour）";
    }
    [self postStateChange];
}

- (void)stop {
    [self.server stop];
    [self.activeConnectionIDs removeAllObjects];
    self.state = CompanionChannelStateStopped;
    self.listeningPort = 0;
    self.usingTemporaryPort = NO;
    self.lastConnectedDeviceId = nil;
    self.statusText = @"已停止";
    [self postStateChange];
}

- (void)restartListeningClearingStickyPort:(BOOL)clearSticky {
    self.intentionallyChangingPort = YES;
    [self stop];
    if (clearSticky) {
        [CompanionPairingStore sharedStore].stickyListeningPort = 0;
    }
    [self start];
    // intentionallyChangingPort 在 didChangeListeningPort 里清除
}

- (NSString *)ensurePairingCode {
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    if (store.authMode == CompanionAuthModeSecurityCode) {
        return store.securityCode.length > 0 ? store.securityCode : @"";
    }
    if ([store isPendingPairingCodeValid:store.pendingPairingCode]) {
        return store.pendingPairingCode;
    }
    // 已有配对设备时不要自动刷码（否则设置页状态刷新会让配对码乱跳；重配请显式「刷新配对码」）。
    if (store.pairedDevices.count > 0) {
        return store.pendingPairingCode.length > 0 ? store.pendingPairingCode : @"------";
    }
    return [store refreshPendingPairingCode];
}

/// 用户主动刷新（注销或重新配对时用）。
- (NSString *)refreshPairingCodeForNewDevice {
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    if (store.authMode == CompanionAuthModeSecurityCode) {
        return store.securityCode ?: @"";
    }
    return [store refreshPendingPairingCode];
}

- (NSArray<NSString *> *)localLANIPv4Addresses {
    NSMutableArray<NSString *> *preferred = [NSMutableArray array];
    NSMutableArray<NSString *> *others = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) {
        return @[];
    }
    for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) {
            continue;
        }
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        char host[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
        if (!inet_ntop(AF_INET, &addr->sin_addr, host, sizeof(host))) {
            continue;
        }
        NSString *ip = [NSString stringWithUTF8String:host];
        if (ip.length == 0 || [ip hasPrefix:@"127."] || [ip hasPrefix:@"169.254."]) {
            continue;
        }
        NSString *name = ifa->ifa_name ? [NSString stringWithUTF8String:ifa->ifa_name] : @"";
        // macOS Wi‑Fi 多为 en0；有线/其他 en*
        if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
            [preferred addObject:ip];
        } else if ([name hasPrefix:@"en"] || [name hasPrefix:@"bridge"] || [name hasPrefix:@"wlan"]) {
            [others addObject:ip];
        } else {
            [others addObject:ip];
        }
    }
    freeifaddrs(interfaces);
    NSMutableArray<NSString *> *all = [preferred mutableCopy];
    for (NSString *ip in others) {
        if (![all containsObject:ip]) {
            [all addObject:ip];
        }
    }
    return [all copy];
}

- (NSString *)preferredLANEndpoint {
    NSArray<NSString *> *ips = [self localLANIPv4Addresses];
    if (ips.count == 0) {
        return self.listeningPort > 0
            ? [NSString stringWithFormat:@"端口 %ld（未检测到局域网 IPv4）", (long)self.listeningPort]
            : nil;
    }
    NSString *ip = ips.firstObject;
    if (self.listeningPort > 0) {
        return [NSString stringWithFormat:@"%@:%ld", ip, (long)self.listeningPort];
    }
    return ip;
}

- (void)postStateChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:CompanionChannelStateDidChangeNotification
                                                        object:self];
}

- (void)refreshConnectedState {
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    if (self.activeConnectionIDs.count > 0) {
        self.state = CompanionChannelStateConnected;
        NSString *device = self.lastConnectedDeviceId.length > 0 ? self.lastConnectedDeviceId : @"已配对设备";
        self.statusText = [NSString stringWithFormat:@"已连接 · %@", device];
    } else if (self.server.isRunning) {
        self.state = CompanionChannelStateAdvertising;
        NSUInteger paired = store.pairedDevices.count;
        if (self.usingTemporaryPort) {
            self.statusText = [NSString stringWithFormat:@"临时端口 %ld（固定端口被占用，请确认更换）",
                               (long)self.listeningPort];
        } else if (store.authMode == CompanionAuthModeSecurityCode) {
            self.statusText = store.securityCode.length > 0
                ? (paired > 0
                   ? [NSString stringWithFormat:@"等待连接（安全码 · 已配对 %lu 台）", (unsigned long)paired]
                   : @"等待手机连接（安全码模式）")
                : @"请先设定固定安全码";
        } else if (paired > 0) {
            self.statusText = [NSString stringWithFormat:@"等待连接（已配对 %lu 台）", (unsigned long)paired];
        } else {
            self.statusText = @"等待手机配对（Bonjour）";
        }
    } else {
        self.state = CompanionChannelStateStopped;
        self.statusText = @"未启动";
    }
    [self postStateChange];
}

#pragma mark - CompanionBonjourServerDelegate

- (void)bonjourServer:(CompanionBonjourServer *)server didChangeListeningPort:(NSInteger)port {
    (void)server;
    self.listeningPort = port;
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    NSInteger sticky = store.stickyListeningPort;

    if (sticky <= 0 || self.intentionallyChangingPort) {
        // 首次分配，或用户确认更换：固化为 sticky
        store.stickyListeningPort = port;
        self.usingTemporaryPort = NO;
        self.intentionallyChangingPort = NO;
    } else if (port == sticky) {
        self.usingTemporaryPort = NO;
        self.intentionallyChangingPort = NO;
    } else {
        // 固定端口被占用，临时落到其他端口；不自动改写 sticky
        self.usingTemporaryPort = YES;
        self.intentionallyChangingPort = NO;
        NSLog(@"[Companion] sticky port %ld busy, temporary port %ld (not auto-saved)",
              (long)sticky, (long)port);
    }
    [self refreshConnectedState];
}

- (void)bonjourServer:(CompanionBonjourServer *)server connectionDidClose:(NSString *)connectionID {
    (void)server;
    [self.activeConnectionIDs removeObject:connectionID];
    [self refreshConnectedState];
}

- (void)bonjourServer:(CompanionBonjourServer *)server
       didReceiveJSON:(NSDictionary *)json
     fromConnectionID:(NSString *)connectionID {
    NSString *type = json[@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        return;
    }
    if ([type isEqualToString:@"hello"]) {
        [self handleHello:json connectionID:connectionID server:server];
        return;
    }
    if ([type isEqualToString:@"otp"]) {
        [self handleOTP:json connectionID:connectionID server:server];
        return;
    }
    if ([type isEqualToString:@"phone_notification"]) {
        [self handlePhoneNotification:json connectionID:connectionID server:server];
        return;
    }
    if ([type isEqualToString:@"open_url"]) {
        [self handleOpenURL:json connectionID:connectionID server:server];
        return;
    }
    if ([type hasPrefix:@"sync_"]) {
        [self handleSyncMessage:json connectionID:connectionID server:server];
        return;
    }
    // 未知 type：安全忽略（向前兼容）。
}

- (void)handleSyncMessage:(NSDictionary *)json
             connectionID:(NSString *)connectionID
                   server:(CompanionBonjourServer *)server {
    NSString *deviceToken = json[@"deviceToken"];
    if (![deviceToken isKindOfClass:[NSString class]] ||
        ![[CompanionPairingStore sharedStore] validateDeviceToken:deviceToken deviceId:nil]) {
        [server sendJSON:@{@"v": @1, @"type": @"sync_error", @"message": @"unauthorized"}
          toConnectionID:connectionID];
        return;
    }
    CompanionSyncSettings *settings = [CompanionSyncSettings sharedSettings];
    if (!settings.syncEnabled) {
        [server sendJSON:@{
            @"v": @1,
            @"type": @"sync_error",
            @"message": @"sync disabled on Mac — enable in 登录助手",
        } toConnectionID:connectionID];
        return;
    }

    NSString *type = json[@"type"];
    if ([type isEqualToString:@"sync_hello"]) {
        [server sendJSON:@{
            @"v": @1,
            @"type": @"sync_hello",
            @"deviceToken": deviceToken,
            @"deviceId": [NSString stringWithFormat:@"mac-%@", NSHost.currentHost.localizedName ?: @"host"],
            @"supportedKinds": @[@"shortcut", @"history", @"bookmark"],
            @"epoch": @(settings.epoch),
        } toConnectionID:connectionID];
        return;
    }

    if ([type isEqualToString:@"sync_pull"]) {
        NSString *kind = json[@"kind"];
        long long epoch = [settings bumpEpoch];
        NSArray *records = nil;
        BOOL ok = NO;
        if ([kind isEqualToString:@"shortcut"] && settings.syncShortcuts) {
            records = [[CompanionShortcutSync sharedSync] exportShortcutRecords];
            ok = YES;
        } else if ([kind isEqualToString:@"history"] && settings.syncHistory) {
            records = [[CompanionBrowseSyncStore sharedStore] exportRecordsForKind:@"history"];
            ok = YES;
        } else if ([kind isEqualToString:@"bookmark"] && settings.syncBookmarks) {
            records = [[CompanionBrowseSyncStore sharedStore] exportRecordsForKind:@"bookmark"];
            ok = YES;
        }
        if (ok) {
            // 单帧上限 64KiB：分批推送，避免整包被 sendJSON 静默丢弃
            NSArray *all = records ?: @[];
            NSUInteger batchSize = 15;
            if (all.count == 0) {
                [server sendJSON:@{
                    @"v": @1,
                    @"type": @"sync_push",
                    @"deviceToken": deviceToken,
                    @"kind": kind ?: @"",
                    @"epoch": @(epoch),
                    @"records": @[],
                } toConnectionID:connectionID];
            } else {
                for (NSUInteger i = 0; i < all.count; i += batchSize) {
                    NSUInteger len = MIN(batchSize, all.count - i);
                    NSArray *slice = [all subarrayWithRange:NSMakeRange(i, len)];
                    NSDictionary *frame = @{
                        @"v": @1,
                        @"type": @"sync_push",
                        @"deviceToken": deviceToken,
                        @"kind": kind ?: @"",
                        @"epoch": @(epoch),
                        @"records": slice,
                    };
                    NSData *probe = [NSJSONSerialization dataWithJSONObject:frame options:0 error:nil];
                    if (probe.length > 60 * 1024 && slice.count > 1) {
                        // 单批仍过大：再拆成 1 条一条发
                        for (NSDictionary *one in slice) {
                            [server sendJSON:@{
                                @"v": @1,
                                @"type": @"sync_push",
                                @"deviceToken": deviceToken,
                                @"kind": kind ?: @"",
                                @"epoch": @(epoch),
                                @"records": @[one],
                            } toConnectionID:connectionID];
                        }
                    } else {
                        [server sendJSON:frame toConnectionID:connectionID];
                    }
                }
            }
        } else {
            [server sendJSON:@{
                @"v": @1,
                @"type": @"sync_error",
                @"message": [NSString stringWithFormat:@"kind %@ not enabled on Mac", kind ?: @"?"],
            } toConnectionID:connectionID];
        }
        return;
    }

    if ([type isEqualToString:@"sync_push"] || [type isEqualToString:@"sync_chunk"]) {
        NSString *kind = nil;
        NSArray *records = nil;
        if ([type isEqualToString:@"sync_chunk"]) {
            NSString *payloadStr = json[@"payload"];
            if (![payloadStr isKindOfClass:[NSString class]]) return;
            NSData *data = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![payload isKindOfClass:[NSDictionary class]]) return;
            kind = payload[@"kind"];
            records = payload[@"records"];
        } else {
            kind = json[@"kind"];
            records = json[@"records"];
        }
        BOOL applied = NO;
        if ([kind isEqualToString:@"shortcut"] && settings.syncShortcuts && [records isKindOfClass:[NSArray class]]) {
            [[CompanionShortcutSync sharedSync] mergeShortcutRecords:records];
            applied = YES;
        } else if ([kind isEqualToString:@"history"] && settings.syncHistory && [records isKindOfClass:[NSArray class]]) {
            [[CompanionBrowseSyncStore sharedStore] mergeRecords:records kind:@"history"];
            applied = YES;
        } else if ([kind isEqualToString:@"bookmark"] && settings.syncBookmarks && [records isKindOfClass:[NSArray class]]) {
            [[CompanionBrowseSyncStore sharedStore] mergeRecords:records kind:@"bookmark"];
            applied = YES;
        }
        if (applied) {
            settings.lastSyncAt = [NSDate date].timeIntervalSince1970;
            long long epoch = [json[@"epoch"] respondsToSelector:@selector(longLongValue)] ? [json[@"epoch"] longLongValue] : settings.epoch;
            [server sendJSON:@{
                @"v": @1,
                @"type": @"sync_ack",
                @"kind": kind ?: @"",
                @"appliedEpoch": @(epoch),
            } toConnectionID:connectionID];
        }
        return;
    }

    if ([type isEqualToString:@"sync_ack"] || [type isEqualToString:@"sync_error"]) {
        return;
    }
}

- (void)handlePhoneNotification:(NSDictionary *)json
                   connectionID:(NSString *)connectionID
                         server:(CompanionBonjourServer *)server {
    NSString *deviceToken = json[@"deviceToken"];
    NSString *payloadId = json[@"id"];
    NSString *packageName = json[@"packageName"];
    if (![deviceToken isKindOfClass:[NSString class]] ||
        ![payloadId isKindOfClass:[NSString class]] || payloadId.length == 0 ||
        ![packageName isKindOfClass:[NSString class]] || packageName.length == 0) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"invalid phone_notification"}
          toConnectionID:connectionID];
        return;
    }
    if (![[CompanionPairingStore sharedStore] validateDeviceToken:deviceToken deviceId:nil]) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"unauthorized"}
          toConnectionID:connectionID];
        return;
    }

    [self.activeConnectionIDs addObject:connectionID];
    // 无论是否展示，一律 ack，避免 Android 重试风暴
    [[PhoneNotificationPresenter sharedPresenter] presentFromPayload:json];
    [server sendJSON:@{
        @"v": @1,
        @"type": @"phone_notification_ok",
        @"id": payloadId,
    } toConnectionID:connectionID];
    [self refreshConnectedState];
}

- (void)handleHello:(NSDictionary *)json
       connectionID:(NSString *)connectionID
             server:(CompanionBonjourServer *)server {
    NSString *deviceId = json[@"deviceId"];
    if (![deviceId isKindOfClass:[NSString class]] || deviceId.length == 0) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"missing deviceId"} toConnectionID:connectionID];
        return;
    }
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
    NSString *deviceToken = json[@"deviceToken"];
    if ([deviceToken isKindOfClass:[NSString class]] && deviceToken.length > 0) {
        if ([store validateDeviceToken:deviceToken deviceId:deviceId]) {
            [self.activeConnectionIDs addObject:connectionID];
            self.lastConnectedDeviceId = deviceId;
            [server sendJSON:@{
                @"v": @1,
                @"type": @"hello_ok",
                @"deviceToken": deviceToken,
                @"hostName": NSHost.currentHost.localizedName ?: @"MeoBrowser",
            } toConnectionID:connectionID];
            [[PhoneNotificationPresenter sharedPresenter] requestAuthorizationIfNeeded];
            [self refreshConnectedState];
            return;
        }
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"invalid deviceToken"} toConnectionID:connectionID];
        return;
    }

    NSString *pairingToken = json[@"pairingToken"];
    if (![pairingToken isKindOfClass:[NSString class]]) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"missing pairingToken"} toConnectionID:connectionID];
        return;
    }
    if (store.authMode == CompanionAuthModeSecurityCode && store.securityCode.length == 0) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"security code not configured"} toConnectionID:connectionID];
        return;
    }
    NSError *error = nil;
    NSString *issued = [store issueDeviceTokenForDeviceId:deviceId pairingCode:pairingToken error:&error];
    if (!issued) {
        [server sendJSON:@{
            @"v": @1,
            @"type": @"error",
            @"message": error.localizedDescription ?: @"pairing failed",
        } toConnectionID:connectionID];
        return;
    }
    [self.activeConnectionIDs addObject:connectionID];
    self.lastConnectedDeviceId = deviceId;
    [server sendJSON:@{
        @"v": @1,
        @"type": @"hello_ok",
        @"deviceToken": issued,
        @"hostName": NSHost.currentHost.localizedName ?: @"MeoBrowser",
    } toConnectionID:connectionID];
    [[PhoneNotificationPresenter sharedPresenter] requestAuthorizationIfNeeded];
    [self refreshConnectedState];
}

- (void)handleOTP:(NSDictionary *)json
     connectionID:(NSString *)connectionID
           server:(CompanionBonjourServer *)server {
    NSString *deviceToken = json[@"deviceToken"];
    NSString *code = json[@"code"];
    if (![deviceToken isKindOfClass:[NSString class]] ||
        ![code isKindOfClass:[NSString class]]) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"invalid otp"} toConnectionID:connectionID];
        return;
    }
    if (![[CompanionPairingStore sharedStore] validateDeviceToken:deviceToken deviceId:nil]) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"unauthorized"} toConnectionID:connectionID];
        return;
    }
    NSTimeInterval ts = [json[@"ts"] doubleValue];
    if (ts <= 0) {
        ts = [NSDate date].timeIntervalSince1970;
    }
    NSError *error = nil;
    BOOL ok = [[OTPInbox sharedInbox] submitCode:code
                                          source:OTPInboxSourceCompanion
                                       timestamp:ts
                                           error:&error];
    if (!ok) {
        [server sendJSON:@{
            @"v": @1,
            @"type": @"error",
            @"message": error.localizedDescription ?: @"otp rejected",
        } toConnectionID:connectionID];
        return;
    }
    [self.activeConnectionIDs addObject:connectionID];
    [server sendJSON:@{@"v": @1, @"type": @"otp_ok"} toConnectionID:connectionID];
    [[PhoneNotificationPresenter sharedPresenter] presentOTPBannerIfNeededWithCode:code];
    [self refreshConnectedState];
}

- (void)handleOpenURL:(NSDictionary *)json
         connectionID:(NSString *)connectionID
               server:(CompanionBonjourServer *)server {
    NSString *deviceToken = json[@"deviceToken"];
    NSString *urlString = json[@"url"];
    if (![deviceToken isKindOfClass:[NSString class]] ||
        ![urlString isKindOfClass:[NSString class]] ||
        urlString.length == 0) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"invalid open_url"}
          toConnectionID:connectionID];
        return;
    }
    if (![[CompanionPairingStore sharedStore] validateDeviceToken:deviceToken deviceId:nil]) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"unauthorized"}
          toConnectionID:connectionID];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || url.scheme.length == 0) {
        [server sendJSON:@{@"v": @1, @"type": @"error", @"message": @"bad url"}
          toConnectionID:connectionID];
        return;
    }
    [self.activeConnectionIDs addObject:connectionID];
    [server sendJSON:@{@"v": @1, @"type": @"open_url_ok"} toConnectionID:connectionID];
    [self refreshConnectedState];
    dispatch_async(dispatch_get_main_queue(), ^{
        id delegate = NSApp.delegate;
        if (![delegate isKindOfClass:[AppDelegate class]]) {
            return;
        }
        AppDelegate *app = (AppDelegate *)delegate;
        BrowserWindowController *target = [app keyBrowserWindowController];
        if (target) {
            [target openURLsFromExternalSource:@[url]];
            [target.window makeKeyAndOrderFront:nil];
        } else {
            [app openURLInNewBrowserWindow:url];
        }
    });
}

@end
