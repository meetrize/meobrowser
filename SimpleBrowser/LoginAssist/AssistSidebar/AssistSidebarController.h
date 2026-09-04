#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AssistSidebarController;
@class LoginRecipe;
@class FormMemo;

typedef NS_ENUM(NSInteger, AssistSidebarScope) {
    AssistSidebarScopeMatched = 0,
    AssistSidebarScopeAll = 1,
};

typedef NS_ENUM(NSInteger, AssistSidebarTypeFilter) {
    AssistSidebarTypeFilterAll = 0,
    AssistSidebarTypeFilterRecipes = 1,
    AssistSidebarTypeFilterMemos = 2,
};

@protocol AssistSidebarControllerDelegate <NSObject>
- (void)assistSidebarDidRequestClose:(AssistSidebarController *)controller;
- (void)assistSidebar:(AssistSidebarController *)controller didChangeWidth:(CGFloat)width;
- (nullable NSURL *)assistSidebarCurrentURL:(AssistSidebarController *)controller;
- (nullable WKWebView *)assistSidebarWebViewForPicking:(AssistSidebarController *)controller;
- (void)assistSidebar:(AssistSidebarController *)controller runRecipe:(LoginRecipe *)recipe fillOnly:(BOOL)fillOnly;
- (void)assistSidebar:(AssistSidebarController *)controller runMemo:(FormMemo *)memo;
- (void)assistSidebarDidRequestAdvancedSettings:(AssistSidebarController *)controller
                                   preferMemos:(BOOL)preferMemos;
@end

/// 登录助手 / 站点备忘管理侧栏（SB-2：列表 + Memo/Recipe CRUD）。
@interface AssistSidebarController : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<AssistSidebarControllerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL visible;
@property (nonatomic, assign) AssistSidebarScope scope;
@property (nonatomic, assign) AssistSidebarTypeFilter typeFilter;

- (void)setVisible:(BOOL)visible animated:(BOOL)animated;
/// 按当前页 URL 同步列表与默认详情（标签切换 / 导航完成）。
- (void)syncToCurrentURL;
/// 同 URL 下刷新列表（Store/过滤），保留未保存编辑。
- (void)reloadList;
- (void)revealRecipeID:(nullable NSString *)recipeID;
- (void)revealMemoID:(nullable NSString *)memoID;
- (void)beginNewMemo;
- (void)beginNewRecipe;

@end

NS_ASSUME_NONNULL_END
