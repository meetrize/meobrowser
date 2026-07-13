#import <Cocoa/Cocoa.h>

@class SBTextField;
@class BrowserAddressBarAutocompleteController;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserAddressBarAutocompleteControllerDelegate <NSObject>
- (void)autocompleteController:(BrowserAddressBarAutocompleteController *)controller
                       openURL:(NSURL *)url;
- (void)autocompleteController:(BrowserAddressBarAutocompleteController *)controller
            openURLInNewTab:(NSURL *)url;
- (NSWindow *)windowForAutocompleteController:(BrowserAddressBarAutocompleteController *)controller;
@end

/// 地址栏快捷方式补全：查询、面板、键盘/鼠标导航。
@interface BrowserAddressBarAutocompleteController : NSObject

@property (nonatomic, weak, nullable) id<BrowserAddressBarAutocompleteControllerDelegate> delegate;
@property (nonatomic, weak, nullable) SBTextField *addressField;

- (instancetype)initWithAddressField:(SBTextField *)addressField;

- (void)install;
- (void)uninstall;

- (BOOL)isPanelVisible;

/// 处理地址栏特殊键；返回 YES 表示已消费。
- (BOOL)handleCommandBySelector:(SEL)commandSelector textView:(NSTextView *)textView;

/// 面板可见且有匹配时，Enter 应打开选中项而非走搜索引擎。
- (BOOL)shouldOpenSelectedShortcutOnEnter;

- (void)openSelectedShortcut;
- (void)dismissPanel;
- (void)refreshMatchesIfNeeded;

@end

NS_ASSUME_NONNULL_END
