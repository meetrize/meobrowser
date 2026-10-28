#import <AppKit/AppKit.h>

@class AIAssistantSession;

NS_ASSUME_NONNULL_BEGIN

/// 历史弹出面板内容：搜索 + 按时间分组列表 + 固定/删除
@interface AIAssistantHistoryPanel : NSView

@property (nonatomic, copy, nullable) void (^onSelectSession)(AIAssistantSession *session);
@property (nonatomic, copy, nullable) void (^onTogglePin)(AIAssistantSession *session);
@property (nonatomic, copy, nullable) void (^onDeleteSession)(AIAssistantSession *session);
/// reload / 搜索后高度变化时回调，供 Popover 设置 contentSize
@property (nonatomic, copy, nullable) void (^onPreferredSizeChanged)(NSSize size);

/// 固定宽 320；高度随列表自适应（有上限）
- (NSSize)preferredPopoverSize;

- (void)reload;
- (void)focusSearch;

@end

NS_ASSUME_NONNULL_END
