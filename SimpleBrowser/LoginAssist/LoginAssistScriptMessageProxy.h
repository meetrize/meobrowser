#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 弱转发 WKScriptMessageHandler，避免 UserContentController 强引用造成循环。
@interface LoginAssistScriptMessageProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak, nullable) id<WKScriptMessageHandler> target;
@end

NS_ASSUME_NONNULL_END
