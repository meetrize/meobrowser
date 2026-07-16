#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CompanionBonjourServer;

@protocol CompanionBonjourServerDelegate <NSObject>
- (void)bonjourServer:(CompanionBonjourServer *)server didReceiveJSON:(NSDictionary *)json fromConnectionID:(NSString *)connectionID;
- (void)bonjourServer:(CompanionBonjourServer *)server connectionDidClose:(NSString *)connectionID;
- (void)bonjourServer:(CompanionBonjourServer *)server didChangeListeningPort:(NSInteger)port;
@end

/// 发布 `_meologin._tcp` 并接受长度前缀 JSON 连接。
@interface CompanionBonjourServer : NSObject

@property (nonatomic, weak, nullable) id<CompanionBonjourServerDelegate> delegate;
@property (nonatomic, assign, readonly) NSInteger listeningPort;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;
- (void)stop;
- (void)sendJSON:(NSDictionary *)json toConnectionID:(NSString *)connectionID;

@end

NS_ASSUME_NONNULL_END
