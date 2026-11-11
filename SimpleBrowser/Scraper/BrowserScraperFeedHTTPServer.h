#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BrowserScraperFeedHTTPRespondBlock)(NSInteger statusCode, NSString *contentType, NSData *body);

typedef void (^BrowserScraperFeedHTTPRequestHandler)(NSString *method,
                                                     NSString *path,
                                                     NSDictionary<NSString *, NSString *> *headers,
                                                     NSData *_Nullable body,
                                                     BrowserScraperFeedHTTPRespondBlock respond);

@interface BrowserScraperFeedHTTPServer : NSObject

@property (nonatomic, copy, nullable) BrowserScraperFeedHTTPRequestHandler requestHandler;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign, readonly) NSInteger listeningPort;

/// 仅绑定 127.0.0.1
- (BOOL)startOnPort:(NSInteger)port error:(NSError *_Nullable *_Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
