#import "CompanionBonjourServer.h"
#import <Network/Network.h>

@interface CompanionBonjourConnection : NSObject
@property (nonatomic, copy) NSString *connectionID;
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableData *buffer;
@end

@implementation CompanionBonjourConnection
@end

@interface CompanionBonjourServer ()
@property (nonatomic, strong, nullable) nw_listener_t listener;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CompanionBonjourConnection *> *connections;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@end

@implementation CompanionBonjourServer

- (instancetype)init {
    self = [super init];
    if (self) {
        _connections = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) {
        return YES;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                               NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_include_peer_to_peer(parameters, true);

    nw_listener_t listener = nw_listener_create(parameters);
    if (!listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"CompanionBonjourServer"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法创建监听器"}];
        }
        return NO;
    }

    nw_listener_set_queue(listener, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;

    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t nwError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (state == nw_listener_state_ready) {
            NSInteger port = (NSInteger)nw_listener_get_port(listener);
            strongSelf.listeningPort = port;
            strongSelf.running = YES;
            id<CompanionBonjourServerDelegate> delegate = strongSelf.delegate;
            if ([delegate respondsToSelector:@selector(bonjourServer:didChangeListeningPort:)]) {
                [delegate bonjourServer:strongSelf didChangeListeningPort:port];
            }
            NSLog(@"[Companion] listening on port %ld (_meologin._tcp)", (long)port);
        } else if (state == nw_listener_state_failed) {
            NSLog(@"[Companion] listener failed: %@", nwError);
            strongSelf.running = NO;
        } else if (state == nw_listener_state_cancelled) {
            strongSelf.running = NO;
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        [weakSelf acceptConnection:connection];
    });

    // Bonjour 服务名
    nw_advertise_descriptor_t advertise =
        nw_advertise_descriptor_create_bonjour_service("MeoBrowser", "_meologin._tcp", NULL);
    nw_listener_set_advertise_descriptor(listener, advertise);

    self.listener = listener;
    nw_listener_start(listener);
    return YES;
}

- (void)stop {
    for (CompanionBonjourConnection *conn in self.connections.allValues) {
        nw_connection_cancel(conn.connection);
    }
    [self.connections removeAllObjects];
    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = nil;
    }
    self.running = NO;
    self.listeningPort = 0;
}

- (void)acceptConnection:(nw_connection_t)connection {
    NSString *connectionID = [[NSUUID UUID] UUIDString];
    CompanionBonjourConnection *wrapper = [[CompanionBonjourConnection alloc] init];
    wrapper.connectionID = connectionID;
    wrapper.connection = connection;
    wrapper.buffer = [NSMutableData data];
    self.connections[connectionID] = wrapper;

    nw_connection_set_queue(connection, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        (void)error;
        if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            [weakSelf removeConnectionID:connectionID];
        }
    });
    nw_connection_start(connection);
    [self receiveMoreOnConnection:wrapper];
}

- (void)removeConnectionID:(NSString *)connectionID {
    CompanionBonjourConnection *conn = self.connections[connectionID];
    if (!conn) {
        return;
    }
    [self.connections removeObjectForKey:connectionID];
    id<CompanionBonjourServerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(bonjourServer:connectionDidClose:)]) {
        [delegate bonjourServer:self connectionDidClose:connectionID];
    }
}

- (void)receiveMoreOnConnection:(CompanionBonjourConnection *)wrapper {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive(wrapper.connection, 1, 64 * 1024,
                          ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t error) {
        (void)context;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            [strongSelf removeConnectionID:wrapper.connectionID];
            return;
        }
        if (content) {
            NSMutableData *chunk = [NSMutableData data];
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                (void)region;
                (void)offset;
                [chunk appendBytes:buffer length:size];
                return true;
            });
            [wrapper.buffer appendData:chunk];
            [strongSelf consumeBufferOnConnection:wrapper];
        }
        if (isComplete) {
            [strongSelf removeConnectionID:wrapper.connectionID];
            return;
        }
        [strongSelf receiveMoreOnConnection:wrapper];
    });
}

- (void)consumeBufferOnConnection:(CompanionBonjourConnection *)wrapper {
    while (wrapper.buffer.length >= 4) {
        uint32_t lengthBE = 0;
        [wrapper.buffer getBytes:&lengthBE length:4];
        uint32_t length = CFSwapInt32BigToHost(lengthBE);
        if (length == 0 || length > 64 * 1024) {
            NSLog(@"[Companion] invalid frame length %u", length);
            nw_connection_cancel(wrapper.connection);
            [self removeConnectionID:wrapper.connectionID];
            return;
        }
        if (wrapper.buffer.length < 4 + length) {
            return;
        }
        NSData *payload = [wrapper.buffer subdataWithRange:NSMakeRange(4, length)];
        [wrapper.buffer replaceBytesInRange:NSMakeRange(0, 4 + length) withBytes:NULL length:0];

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id<CompanionBonjourServerDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(bonjourServer:didReceiveJSON:fromConnectionID:)]) {
            [delegate bonjourServer:self didReceiveJSON:json fromConnectionID:wrapper.connectionID];
        }
    }
}

- (void)sendJSON:(NSDictionary *)json toConnectionID:(NSString *)connectionID {
    CompanionBonjourConnection *wrapper = self.connections[connectionID];
    if (!wrapper) {
        return;
    }
    NSData *payload = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    if (!payload || payload.length > 64 * 1024) {
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
    nw_connection_send(wrapper.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        if (error) {
            NSLog(@"[Companion] send failed");
        }
    });
}

@end
