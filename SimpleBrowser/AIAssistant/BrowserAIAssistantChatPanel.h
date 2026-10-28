#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AIAssistantMessage;

/// 对话面板：用户右侧气泡；助手左侧 Markdown 渲染（无气泡）。
@interface BrowserAIAssistantChatPanel : NSView

- (void)clear;
- (void)appendUserText:(NSString *)text;
- (void)appendAssistantMarkdown:(NSString *)markdown;
- (void)appendSystemText:(NSString *)text;
/// 切换会话时整表重载
- (void)reloadMessages:(NSArray<AIAssistantMessage *> *)messages;

@end

NS_ASSUME_NONNULL_END
