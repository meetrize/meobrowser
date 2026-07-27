#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class LoginRecipe;
@class AssistSidebarRecipeEditor;

NS_ASSUME_NONNULL_BEGIN

@protocol AssistSidebarRecipeEditorDelegate <NSObject>
- (nullable NSURL *)recipeEditorCurrentURL:(AssistSidebarRecipeEditor *)editor;
- (nullable WKWebView *)recipeEditorWebViewForPicking:(AssistSidebarRecipeEditor *)editor;
- (void)recipeEditor:(AssistSidebarRecipeEditor *)editor didSaveRecipe:(LoginRecipe *)recipe;
- (void)recipeEditor:(AssistSidebarRecipeEditor *)editor didDeleteRecipeID:(NSString *)recipeID;
- (void)recipeEditorDidCancelNew:(AssistSidebarRecipeEditor *)editor;
@end

/// 助手侧栏内嵌的登录配置编辑器（SB-2）。
@interface AssistSidebarRecipeEditor : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<AssistSidebarRecipeEditorDelegate> delegate;
@property (nonatomic, copy, readonly, nullable) NSString *editingRecipeID;

- (void)loadRecipe:(nullable LoginRecipe *)recipe;
- (void)beginNewRecipePrefillingFromCurrentURL;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
