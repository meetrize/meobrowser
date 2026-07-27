#import <Cocoa/Cocoa.h>

@class FormMemo;
@class FormMemoField;
@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

@class AssistSidebarMemoEditor;

@protocol AssistSidebarMemoEditorDelegate <NSObject>
- (nullable NSURL *)memoEditorCurrentURL:(AssistSidebarMemoEditor *)editor;
- (nullable WKWebView *)memoEditorWebViewForPicking:(AssistSidebarMemoEditor *)editor;
- (void)memoEditor:(AssistSidebarMemoEditor *)editor didSaveMemo:(FormMemo *)memo;
- (void)memoEditor:(AssistSidebarMemoEditor *)editor didDeleteMemoID:(NSString *)memoID;
- (void)memoEditorDidCancelNew:(AssistSidebarMemoEditor *)editor;
@end

/// 助手侧栏内嵌的站点备忘编辑器（SB-1）。
@interface AssistSidebarMemoEditor : NSObject

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<AssistSidebarMemoEditorDelegate> delegate;
@property (nonatomic, copy, readonly, nullable) NSString *editingMemoID;

- (void)loadMemo:(nullable FormMemo *)memo;
- (void)beginNewMemoPrefillingFromCurrentURL;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
