#import <AppKit/AppKit.h>

@class AIAssistantSession;

NS_ASSUME_NONNULL_BEGIN

/// 历史弹出面板内容：搜索 + 按时间分组列表 + 固定/删除
@interface AIAssistantHistoryPanel : NSView

@property (nonatomic, copy, nullable) void (^onSelectSession)(AIAssistantSession *session);
@property (nonatomic, copy, nullable) void (^onTogglePin)(AIAssistantSession *session);
@property (nonatomic, copy, nullable) void (^onDeleteSession)(AIAssistantSession *session);

- (void)reload;
- (void)focusSearch;

@end

NS_ASSUME_NONNULL_END
