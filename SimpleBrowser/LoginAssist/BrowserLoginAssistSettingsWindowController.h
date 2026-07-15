#import <Cocoa/Cocoa.h>

@class LoginAssistController;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserLoginAssistSettingsWindowController : NSWindowController

@property (nonatomic, weak, nullable) LoginAssistController *pickerHost;

- (void)selectRecipeID:(NSString *)recipeID;
- (void)reloadRecipes;

@end

NS_ASSUME_NONNULL_END
