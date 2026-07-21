#import <Cocoa/Cocoa.h>

@class LoginAssistController;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserLoginAssistSettingsWindowController : NSWindowController

@property (nonatomic, weak, nullable) LoginAssistController *pickerHost;

- (void)selectRecipeID:(NSString *)recipeID;
- (void)reloadRecipes;
/// 滚到互联状态卡片并短暂强调（工具栏「互联」入口）。
- (void)revealCompanionSection;

@end

NS_ASSUME_NONNULL_END
