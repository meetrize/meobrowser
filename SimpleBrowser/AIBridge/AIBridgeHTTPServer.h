#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIBridgeHTTPRespondBlock)(NSInteger statusCode, NSString *contentType, NSData *body);

typedef void (^AIBridgeHTTPRequestHandler)(NSString *method,
                                           NSString *path,
                                           NSDictionary<NSString *, NSString *> *headers,
                                           NSData *_Nullable body,
                                           AIBridgeHTTPRespondBlock respond);

@interface AIBridgeHTTPServer : NSObject

@property (nonatomic, copy, nullable) AIBridgeHTTPRequestHandler requestHandler;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign, readonly) NSInteger listeningPort;

/// 绑定 0.0.0.0（本机 + 局域网可达）
- (BOOL)startOnPort:(NSInteger)port error:(NSError *_Nullable *_Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
