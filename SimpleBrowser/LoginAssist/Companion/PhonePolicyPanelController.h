#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhonePolicyPanelController : NSWindowController

+ (instancetype)sharedController;
- (void)showPanel;

@end

NS_ASSUME_NONNULL_END
