#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const LoginAssistPreferencesDidChangeNotification;

@interface LoginAssistPreferences : NSObject

+ (BOOL)inlineAssistEnabled;
+ (void)setInlineAssistEnabled:(BOOL)enabled;

+ (BOOL)promptSaveOnSuccess;
+ (void)setPromptSaveOnSuccess:(BOOL)enabled;

+ (BOOL)shouldSuppressSavePromptForHost:(NSString *)host;
+ (void)setSuppressSavePrompt:(BOOL)suppress forHost:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
