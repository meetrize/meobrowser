#import "BrowserScraperFeedHTTPServer.h"
#import <Network/Network.h>

@interface BrowserScraperFeedHTTPConnection : NSObject
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) BOOL headersParsed;
@property (nonatomic, assign) NSInteger contentLength;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) BOOL responded;
@end

@implementation BrowserScraperFeedHTTPConnection
@end

@interface BrowserScraperFeedHTTPServer ()
@property (nonatomic, strong, nullable) nw_listener_t listener;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite) NSInteger listeningPort;
@property (nonatomic, strong) NSMutableArray<BrowserScraperFeedHTTPConnection *> *connections;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation BrowserScraperFeedHTTPServer

- (instancetype)init {
    self = [super init];
    if (self) {
        _connections = [NSMutableArray array];
        _queue = dispatch_queue_create("meo.scraper.feed.http", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)startOnPort:(NSInteger)port error:(NSError **)error {
    if (self.running) {
        return YES;
    }
    if (port < 1 || port > 65535) {
        port = 3922;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                               NW_PARAMETERS_DEFAULT_CONFIGURATION);
    NSString *portString = [NSString stringWithFormat:@"%ld", (long)port];
    nw_endpoint_t local = nw_endpoint_create_host("127.0.0.1", portString.UTF8String);
    nw_parameters_set_local_endpoint(parameters, local);

    nw_listener_t listener = nw_listener_create(parameters);
    if (!listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"BrowserScraperFeedHTTPServer" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"无法创建 127.0.0.1 监听器"}];
        }
        return NO;
    }

    nw_listener_set_queue(listener, self.queue);
    __weak typeof(self) weakSelf = self;
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t nwError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (state == nw_listener_state_ready) {
            strongSelf.listeningPort = (NSInteger)nw_listener_get_port(listener);
            strongSelf.running = YES;
            NSLog(@"[ScraperFeed] listening on 127.0.0.1:%ld", (long)strongSelf.listeningPort);
        } else if (state == nw_listener_state_failed) {
            NSLog(@"[ScraperFeed] listener failed: %@", nwError);
            strongSelf.running = NO;
        } else if (state == nw_listener_state_cancelled) {
            strongSelf.running = NO;
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        [weakSelf acceptConnection:connection];
    });

    self.listener = listener;
    nw_listener_start(listener);
    return YES;
}

- (void)stop {
    nw_listener_t listener = self.listener;
    self.listener = nil;
    if (listener) {
        nw_listener_cancel(listener);
    }
    for (BrowserScraperFeedHTTPConnection *c in self.connections.copy) {
        if (c.connection) {
            nw_connection_cancel(c.connection);
        }
    }
    [self.connections removeAllObjects];
    self.running = NO;
    self.listeningPort = 0;
}

- (void)acceptConnection:(nw_connection_t)connection {
    BrowserScraperFeedHTTPConnection *conn = [[BrowserScraperFeedHTTPConnection alloc] init];
    conn.connection = connection;
    conn.buffer = [NSMutableData data];
    conn.headers = [NSMutableDictionary dictionary];
    conn.contentLength = -1;
    [self.connections addObject:conn];

    nw_connection_set_queue(connection, self.queue);
    __weak typeof(self) weakSelf = self;
    __weak BrowserScraperFeedHTTPConnection *weakConn = conn;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        (void)error;
        if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            [weakSelf dropConnection:weakConn];
        }
    });
    nw_connection_start(connection);
    [self receiveMore:conn];
}

- (void)dropConnection:(BrowserScraperFeedHTTPConnection *)conn {
    if (!conn) {
        return;
    }
    [self.connections removeObject:conn];
}

- (void)receiveMore:(BrowserScraperFeedHTTPConnection *)conn {
    if (!conn.connection || conn.responded) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    __weak BrowserScraperFeedHTTPConnection *weakConn = conn;
    nw_connection_receive(conn.connection, 1, 64 * 1024,
                          ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t error) {
        (void)context;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong BrowserScraperFeedHTTPConnection *strongConn = weakConn;
        if (!strongSelf || !strongConn) {
            return;
        }
        if (error) {
            [strongSelf dropConnection:strongConn];
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
            [strongConn.buffer appendData:chunk];
            [strongSelf tryParseConnection:strongConn];
        }
        if (isComplete) {
            if (!strongConn.responded) {
                [strongSelf respondOn:strongConn status:400 contentType:@"text/plain; charset=utf-8"
                                 body:[@"incomplete request" dataUsingEncoding:NSUTF8StringEncoding]];
            }
            return;
        }
        if (!strongConn.responded) {
            [strongSelf receiveMore:strongConn];
        }
    });
}

- (void)tryParseConnection:(BrowserScraperFeedHTTPConnection *)conn {
    if (conn.responded) {
        return;
    }
    if (!conn.headersParsed) {
        NSData *buf = conn.buffer;
        NSRange range = [buf rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                                 options:0
                                   range:NSMakeRange(0, buf.length)];
        if (range.location == NSNotFound) {
            if (buf.length > 1024 * 1024) {
                [self respondOn:conn status:413 contentType:@"text/plain; charset=utf-8"
                           body:[@"headers too large" dataUsingEncoding:NSUTF8StringEncoding]];
            }
            return;
        }
        NSData *headerData = [buf subdataWithRange:NSMakeRange(0, range.location)];
        NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
        NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
        if (lines.count == 0) {
            [self respondOn:conn status:400 contentType:@"text/plain; charset=utf-8"
                       body:[@"bad request" dataUsingEncoding:NSUTF8StringEncoding]];
            return;
        }
        NSArray<NSString *> *req = [lines[0] componentsSeparatedByString:@" "];
        if (req.count < 2) {
            [self respondOn:conn status:400 contentType:@"text/plain; charset=utf-8"
                       body:[@"bad request line" dataUsingEncoding:NSUTF8StringEncoding]];
            return;
        }
        conn.method = req[0];
        conn.path = req[1];
        for (NSUInteger i = 1; i < lines.count; i++) {
            NSString *line = lines[i];
            NSRange colon = [line rangeOfString:@":"];
            if (colon.location == NSNotFound) {
                continue;
            }
            NSString *key = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
            NSString *val = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            conn.headers[key] = val;
        }
        NSString *cl = conn.headers[@"content-length"];
        conn.contentLength = cl ? cl.integerValue : 0;
        NSUInteger bodyStart = range.location + range.length;
        if (bodyStart < buf.length) {
            conn.buffer = [[buf subdataWithRange:NSMakeRange(bodyStart, buf.length - bodyStart)] mutableCopy];
        } else {
            conn.buffer = [NSMutableData data];
        }
        conn.headersParsed = YES;
    }

    if ((NSInteger)conn.buffer.length < conn.contentLength) {
        return;
    }
    NSData *body = conn.contentLength > 0
        ? [conn.buffer subdataWithRange:NSMakeRange(0, (NSUInteger)conn.contentLength)]
        : [NSData data];

    BrowserScraperFeedHTTPRequestHandler handler = self.requestHandler;
    if (!handler) {
        [self respondOn:conn status:503 contentType:@"text/plain; charset=utf-8"
                   body:[@"no handler" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak BrowserScraperFeedHTTPConnection *weakConn = conn;
    handler(conn.method, conn.path, [conn.headers copy], body, ^(NSInteger statusCode, NSString *contentType, NSData *respBody) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong BrowserScraperFeedHTTPConnection *strongConn = weakConn;
        if (!strongSelf || !strongConn) {
            return;
        }
        dispatch_async(strongSelf.queue, ^{
            [strongSelf respondOn:strongConn status:statusCode contentType:contentType body:respBody ?: [NSData data]];
        });
    });
}

- (void)respondOn:(BrowserScraperFeedHTTPConnection *)conn
           status:(NSInteger)status
      contentType:(NSString *)contentType
             body:(NSData *)body {
    if (conn.responded || !conn.connection) {
        return;
    }
    conn.responded = YES;
    NSString *reason = @"OK";
    if (status == 400) reason = @"Bad Request";
    else if (status == 401) reason = @"Unauthorized";
    else if (status == 404) reason = @"Not Found";
    else if (status == 409) reason = @"Conflict";
    else if (status == 413) reason = @"Payload Too Large";
    else if (status == 429) reason = @"Too Many Requests";
    else if (status == 503) reason = @"Service Unavailable";
    else if (status == 504) reason = @"Gateway Timeout";
    else if (status >= 500) reason = @"Error";

    NSMutableString *header = [NSMutableString string];
    [header appendFormat:@"HTTP/1.1 %ld %@\r\n", (long)status, reason];
    [header appendFormat:@"Content-Type: %@\r\n", contentType.length ? contentType : @"application/json"];
    [header appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    [header appendString:@"Connection: close\r\n"];
    [header appendString:@"Access-Control-Allow-Origin: *\r\n"];
    [header appendString:@"\r\n"];

    NSMutableData *packet = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    if (body.length) {
        [packet appendData:body];
    }

    dispatch_data_t dd = dispatch_data_create(packet.bytes, packet.length, self.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    __weak typeof(self) weakSelf = self;
    __weak BrowserScraperFeedHTTPConnection *weakConn = conn;
    nw_connection_send(conn.connection, dd, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                       ^(nw_error_t error) {
        (void)error;
        __strong BrowserScraperFeedHTTPConnection *strongConn = weakConn;
        if (strongConn.connection) {
            nw_connection_cancel(strongConn.connection);
        }
        [weakSelf dropConnection:strongConn];
    });
}

@end
