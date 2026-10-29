#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AIAssistantMessage;

/// 对话面板：用户右侧气泡；助手左侧 Markdown 渲染（无气泡）。
@interface BrowserAIAssistantChatPanel : NSView

- (void)clear;
- (void)appendUserText:(NSString *)text;
/// 用户气泡 + 可选引用/附件图（data URL 字符串，兼容旧调用）
- (void)appendUserText:(NSString *)text imageDataURLs:(nullable NSArray<NSString *> *)imageDataURLs;
/// 用户气泡：文案 + uiAttachments（image/file，可点开系统默认应用）
- (void)appendUserText:(NSString *)text
         uiAttachments:(nullable NSArray<NSDictionary *> *)uiAttachments;
- (void)appendAssistantMarkdown:(NSString *)markdown;
- (void)appendSystemText:(NSString *)text;
/// 切换会话时整表重载
- (void)reloadMessages:(NSArray<AIAssistantMessage *> *)messages;

@end

NS_ASSUME_NONNULL_END
