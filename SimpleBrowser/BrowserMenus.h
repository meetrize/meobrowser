#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserMenus : NSObject

+ (void)installTabMenuForTarget:(id)target;
+ (void)installSettingsMenuForTarget:(id)target;
+ (void)installDownloadMenuForTarget:(id)target;
+ (void)installViewMenuForTarget:(id)target;

@end

NS_ASSUME_NONNULL_END
