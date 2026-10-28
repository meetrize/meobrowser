#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AIAssistantCitationKind) {
    AIAssistantCitationKindText = 0,  /// 选中文本
    AIAssistantCitationKindURL,       /// 网页地址
    AIAssistantCitationKindImage,     /// 在线图片
    AIAssistantCitationKindFile,      /// 在线文件
    AIAssistantCitationKindLink,      /// 其他链接
};

@interface AIAssistantCitation : NSObject

@property (nonatomic, copy, readonly) NSString *citationId;
@property (nonatomic, assign, readonly) AIAssistantCitationKind kind;
@property (nonatomic, copy, readonly) NSString *title;
/// 文本正文，或 URL 字符串
@property (nonatomic, copy, readonly) NSString *body;
@property (nonatomic, copy, readonly, nullable) NSURL *url;
/// 划词引用的来源页标题（可选）
@property (nonatomic, copy, readonly, nullable) NSString *sourcePageTitle;
@property (nonatomic, strong, nullable) NSImage *previewImage;

+ (instancetype)textCitation:(NSString *)text;
/// 划词引用：正文 + 来源页 URL（发送给模型时一并作为上下文）
+ (instancetype)textCitation:(NSString *)text
                   sourceURL:(nullable NSURL *)sourceURL
                   pageTitle:(nullable NSString *)pageTitle;
+ (instancetype)URLCitationWithURL:(NSURL *)url title:(nullable NSString *)title;
+ (instancetype)imageCitationWithURL:(NSURL *)url title:(nullable NSString *)title;
+ (instancetype)fileCitationWithURL:(NSURL *)url title:(nullable NSString *)title;
+ (instancetype)linkCitationWithURL:(NSURL *)url title:(nullable NSString *)title;

/// 根据 URL 扩展名与 DOM 提示推断类型（hint: text|image|file|link|url）
+ (instancetype)citationWithURLString:(NSString *)urlString
                                title:(nullable NSString *)title
                                 hint:(nullable NSString *)hint;

- (NSString *)kindDisplayName;
- (NSString *)chipLabel;
/// 拼进发给 Bridge 的用户消息
- (NSString *)promptBlock;

@end

NS_ASSUME_NONNULL_END
