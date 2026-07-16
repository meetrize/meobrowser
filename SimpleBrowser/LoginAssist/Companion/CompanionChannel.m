#import "CompanionChannel.h"
#import "CompanionBonjourServer.h"
#import "CompanionPairingStore.h"
#import "OTPInbox.h"
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
@property (nonatomic, strong) NSMutableSet<NSString *> *activeConnectionIDs;
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
    NSError *error = nil;
    if (![self.server startWithError:&error]) {
        self.state = CompanionChannelStateStopped;
        self.statusText = error.localizedDescription ?: @"启动失败";
        [self postStateChange];
        return;
    }
    (void)[self ensurePairingCode];
    self.state = CompanionChannelStateAdvertising;
    self.statusText = @"等待手机连接（Bonjour）";
    [self postStateChange];
}

- (void)stop {
    [self.server stop];
    [self.activeConnectionIDs removeAllObjects];
    self.state = CompanionChannelStateStopped;
    self.listeningPort = 0;
    self.lastConnectedDeviceId = nil;
    self.statusText = @"已停止";
    [self postStateChange];
}

- (NSString *)ensurePairingCode {
    CompanionPairingStore *store = [CompanionPairingStore sharedStore];
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
    return [[CompanionPairingStore sharedStore] refreshPendingPairingCode];
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
    if (self.activeConnectionIDs.count > 0) {
        self.state = CompanionChannelStateConnected;
        NSString *device = self.lastConnectedDeviceId.length > 0 ? self.lastConnectedDeviceId : @"已配对设备";
        self.statusText = [NSString stringWithFormat:@"已连接 · %@", device];
    } else if (self.server.isRunning) {
        self.state = CompanionChannelStateAdvertising;
        NSUInteger paired = [CompanionPairingStore sharedStore].pairedDevices.count;
        if (paired > 0) {
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
    [self refreshConnectedState];
}

@end
