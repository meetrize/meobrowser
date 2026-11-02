#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 配方管理：列表 + 编辑提示词 / 菜单位置 / 新建导入导出
@interface AIPageContextRecipeEditorController : NSWindowController

+ (instancetype)sharedController;
- (void)showEditor;

@end

NS_ASSUME_NONNULL_END
