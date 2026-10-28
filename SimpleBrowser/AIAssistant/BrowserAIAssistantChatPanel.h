#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 对话面板：用户右侧气泡；助手左侧 Markdown 渲染（无气泡）。
@interface BrowserAIAssistantChatPanel : NSView

- (void)clear;
- (void)appendUserText:(NSString *)text;
- (void)appendAssistantMarkdown:(NSString *)markdown;
- (void)appendSystemText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
