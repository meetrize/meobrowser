#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserScraperFeedServiceStateDidChangeNotification;

@interface BrowserScraperFeedService : NSObject

@property (class, readonly, strong) BrowserScraperFeedService *sharedService;

@property (nonatomic, assign, readonly, getter=isListening) BOOL listening;
@property (nonatomic, assign, readonly) NSInteger listeningPort;

- (BOOL)startServer:(NSError *_Nullable *_Nullable)error;
- (void)stopServer;

/// 当前本机 base，如 http://127.0.0.1:3922
- (NSString *)baseURLString;
/// 某策略的订阅 URL；服务未开时仍按 prefs.port 拼装（便于侧栏展示）。
- (NSString *)feedURLStringForRecipeID:(NSString *)recipeID;

@end

NS_ASSUME_NONNULL_END
