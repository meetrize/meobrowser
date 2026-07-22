#import "CompanionPhoneDiscovery.h"
#import <Network/Network.h>

@interface CompanionPhoneDiscovery ()
@property (nonatomic, strong, nullable) nw_browser_t browser;
@property (nonatomic, copy) NSSet<NSString *> *allowedDeviceIds;
@property (nonatomic, copy) NSString *hostName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastInviteAtByDeviceId;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingInviteDeviceIds;
@property (nonatomic, assign, readwrite, getter=isBrowsing) BOOL browsing;
/// deviceId → nw_endpoint_t（browse 结果缓存）
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *endpointsByDeviceId;
@end

@implementation CompanionPhoneDiscovery

static const NSTimeInterval kInviteCooldownSeconds = 8.0;

- (instancetype)init {
    self = [super init];
    if (self) {
        _allowedDeviceIds = [NSSet set];
        _hostName = @"MeoBrowser";
        _lastInviteAtByDeviceId = [NSMutableDictionary dictionary];
        _pendingInviteDeviceIds = [NSMutableSet set];
        _endpointsByDeviceId = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)startWithAllowedDeviceIds:(NSSet<NSString *> *)allowedDeviceIds
                         hostName:(NSString *)hostName {
    self.allowedDeviceIds = allowedDeviceIds ?: [NSSet set];
    self.hostName = hostName.length > 0 ? hostName : NSHost.currentHost.localizedName ?: @"MeoBrowser";
    if (self.allowedDeviceIds.count == 0) {
        [self stop];
        return;
    }
    if (self.browser) {
        // 更新白名单后，对已缓存 endpoint 再尝试一轮
        [self inviteNow];
        return;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                               NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_include_peer_to_peer(parameters, true);
    nw_browser_t browser = nw_browser_create(nw_browse_descriptor_create_bonjour_service("_meocompanion._tcp", NULL),
                                             parameters);
    if (!browser) {
        NSLog(@"[CompanionInvite] failed to create nw_browser");
        return;
    }

    __weak typeof(self) weakSelf = self;
    nw_browser_set_queue(browser, dispatch_get_main_queue());
    nw_browser_set_browse_results_changed_handler(browser, ^(nw_browse_result_t old_result,
                                                             nw_browse_result_t new_result,
                                                             bool batch_complete) {
        (void)batch_complete;
        nw_browse_result_change_t changes = nw_browse_result_get_changes(old_result, new_result);
        if (changes & nw_browse_result_change_result_removed) {
            [weakSelf handleBrowseRemoved:old_result];
            return;
        }
        if (changes & (nw_browse_result_change_result_added |
                       nw_browse_result_change_txt_record_changed |
                       nw_browse_result_change_identical |
                       nw_browse_result_change_interface_added)) {
            if (new_result) {
                [weakSelf handleBrowseResult:new_result];
            }
        }
    });
    nw_browser_set_state_changed_handler(browser, ^(nw_browser_state_t state, nw_error_t error) {
        if (state == nw_browser_state_failed) {
            NSLog(@"[CompanionInvite] browser failed: %@", error);
        } else if (state == nw_browser_state_ready) {
            NSLog(@"[CompanionInvite] browsing _meocompanion._tcp for %lu device(s)",
                  (unsigned long)weakSelf.allowedDeviceIds.count);
        }
    });

    self.browser = browser;
    self.browsing = YES;
    nw_browser_start(browser);
}

- (void)stop {
    if (self.browser) {
        nw_browser_cancel(self.browser);
        self.browser = nil;
    }
    self.browsing = NO;
    [self.endpointsByDeviceId removeAllObjects];
    [self.pendingInviteDeviceIds removeAllObjects];
}

- (void)inviteNow {
    NSArray<NSString *> *ids = self.endpointsByDeviceId.allKeys;
    for (NSString *deviceId in ids) {
        [self maybeInviteDeviceId:deviceId force:YES];
    }
}

#pragma mark - Browse

- (void)handleBrowseRemoved:(nw_browse_result_t)result {
    if (!result) {
        return;
    }
    nw_endpoint_t endpoint = nw_browse_result_copy_endpoint(result);
    if (!endpoint) {
        return;
    }
    NSString *deviceId = [self deviceIdFromBrowseResult:result endpoint:endpoint];
    if (deviceId.length > 0) {
        [self.endpointsByDeviceId removeObjectForKey:deviceId];
    }
}

- (void)handleBrowseResult:(nw_browse_result_t)result {
    if (!result) {
        return;
    }
    nw_endpoint_t endpoint = nw_browse_result_copy_endpoint(result);
    if (!endpoint) {
        return;
    }

    NSString *deviceId = [self deviceIdFromBrowseResult:result endpoint:endpoint];
    if (deviceId.length == 0) {
        return;
    }
    if (![self.allowedDeviceIds containsObject:deviceId]) {
        NSLog(@"[CompanionInvite] skip unpaired deviceId=%@", deviceId);
        return;
    }

    self.endpointsByDeviceId[deviceId] = endpoint;
    [self maybeInviteDeviceId:deviceId force:NO];
}

- (nullable NSString *)deviceIdFromBrowseResult:(nw_browse_result_t)result
                                      endpoint:(nw_endpoint_t)endpoint {
    // 1) 服务名 MeoC-<uuid>
    if (nw_endpoint_get_type(endpoint) == nw_endpoint_type_bonjour_service) {
        const char *name = nw_endpoint_get_bonjour_service_name(endpoint);
        if (name) {
            NSString *serviceName = [NSString stringWithUTF8String:name];
            NSString *prefix = @"MeoC-";
            if ([serviceName hasPrefix:prefix] && serviceName.length > prefix.length) {
                return [serviceName substringFromIndex:prefix.length];
            }
        }
    }

    // 2) TXT deviceId（若系统提供）
    if (@available(macOS 10.15, *)) {
        nw_txt_record_t txt = nw_browse_result_copy_txt_record_object(result);
        if (txt) {
            __block NSString *found = nil;
            nw_txt_record_access_key(txt, "deviceId",
                                     ^bool(const char *key,
                                           const nw_txt_record_find_key_t findResult,
                                           const uint8_t *value,
                                           const size_t value_len) {
                (void)key;
                if (findResult == nw_txt_record_find_key_non_empty_value &&
                    value && value_len > 0) {
                    found = [[NSString alloc] initWithBytes:value
                                                     length:value_len
                                                   encoding:NSUTF8StringEncoding];
                }
                return true;
            });
            if (found.length > 0) {
                return found;
            }
        }
    }
    return nil;
}

- (void)maybeInviteDeviceId:(NSString *)deviceId force:(BOOL)force {
    if (deviceId.length == 0) {
        return;
    }
    if (![self.allowedDeviceIds containsObject:deviceId]) {
        return;
    }
    if ([self.pendingInviteDeviceIds containsObject:deviceId]) {
        return;
    }
    NSNumber *last = self.lastInviteAtByDeviceId[deviceId];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!force && last && (now - last.doubleValue) < kInviteCooldownSeconds) {
        return;
    }

    id endpointObj = self.endpointsByDeviceId[deviceId];
    if (!endpointObj) {
        return;
    }
    nw_endpoint_t endpoint = (nw_endpoint_t)endpointObj;
    [self.pendingInviteDeviceIds addObject:deviceId];
    self.lastInviteAtByDeviceId[deviceId] = @(now);
    [self sendInviteToEndpoint:endpoint deviceId:deviceId];
}

- (void)sendInviteToEndpoint:(nw_endpoint_t)endpoint deviceId:(NSString *)deviceId {
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                               NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_include_peer_to_peer(parameters, true);
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    if (!connection) {
        [self.pendingInviteDeviceIds removeObject:deviceId];
        return;
    }

    __weak typeof(self) weakSelf = self;
    nw_connection_set_queue(connection, dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (state == nw_connection_state_ready) {
            [strongSelf writeInviteOnConnection:connection deviceId:deviceId];
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            [strongSelf.pendingInviteDeviceIds removeObject:deviceId];
            if (state == nw_connection_state_failed) {
                NSLog(@"[CompanionInvite] connect failed deviceId=%@ err=%@", deviceId, error);
            }
        }
    });
    nw_connection_start(connection);
    NSLog(@"[CompanionInvite] inviting deviceId=%@", deviceId);
}

- (void)writeInviteOnConnection:(nw_connection_t)connection deviceId:(NSString *)deviceId {
    NSDictionary *json = @{
        @"v": @1,
        @"type": @"invite",
        @"from": @"mac",
        @"hostName": self.hostName ?: @"MeoBrowser",
        @"nonce": [[NSUUID UUID] UUIDString],
        @"deviceId": deviceId ?: @""
    };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    if (!payload || payload.length > 64 * 1024) {
        nw_connection_cancel(connection);
        [self.pendingInviteDeviceIds removeObject:deviceId];
        return;
    }
    uint32_t lengthBE = CFSwapInt32HostToBig((uint32_t)payload.length);
    NSMutableData *frame = [NSMutableData dataWithBytes:&lengthBE length:4];
    [frame appendData:payload];
    NSData *frameCopy = [frame copy];
    dispatch_data_t data = dispatch_data_create(frameCopy.bytes,
                                                frameCopy.length,
                                                dispatch_get_main_queue(),
                                                ^{ (void)frameCopy; });

    __weak typeof(self) weakSelf = self;
    nw_connection_send(connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            NSLog(@"[CompanionInvite] send failed deviceId=%@", deviceId);
        } else {
            NSLog(@"[CompanionInvite] invite sent deviceId=%@", deviceId);
        }
        // 短连接：发完即关
        nw_connection_cancel(connection);
        [strongSelf.pendingInviteDeviceIds removeObject:deviceId];
    });
}

@end
