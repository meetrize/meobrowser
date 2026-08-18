#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BrowserSettingsTabGeneral;
FOUNDATION_EXPORT NSString * const BrowserSettingsTabSync;
FOUNDATION_EXPORT NSString * const BrowserSettingsTabKeyboard;
FOUNDATION_EXPORT NSString * const BrowserSettingsTabPrivacy;
FOUNDATION_EXPORT NSString * const BrowserSettingsTabDeveloper;

@interface BrowserSettingsWindowController : NSWindowController

- (instancetype)init;
- (void)selectTabWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
