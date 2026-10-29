#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AIAssistantSessionConnection) {
    AIAssistantSessionConnectionReady = 0,
    AIAssistantSessionConnectionOpening,
    AIAssistantSessionConnectionDetached, // 网页已关
    AIAssistantSessionConnectionNeedLogin,
    AIAssistantSessionConnectionError,
};

@interface AIAssistantMessage : NSObject
@property (nonatomic, copy) NSString *role; // user | assistant | system
/// 发给模型的全文（含引用上下文）
@property (nonatomic, copy) NSString *content;
/// 对话气泡展示文案；空则回退 content
@property (nonatomic, copy, nullable) NSString *displayContent;
/// 用户气泡内联图（data:image/...;base64,...），仅展示用（兼容旧会话）
@property (nonatomic, copy, nullable) NSArray<NSString *> *imageDataURLs;
/// 气泡附件：[{kind:image|file, name?, path?, preview?, icon?}]；path 供系统打开
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *uiAttachments;
@property (nonatomic, assign) NSTimeInterval createdAt;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)messageFromDictionary:(NSDictionary *)dict;
+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content;
@end

@interface AIAssistantSession : NSObject
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *providerId;
@property (nonatomic, copy, nullable) NSString *bindingId;
@property (nonatomic, copy, nullable) NSString *modelId;
@property (nonatomic, strong) NSMutableArray<AIAssistantMessage *> *messages;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, assign) AIAssistantSessionConnection connection;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)sessionFromDictionary:(NSDictionary *)dict;
- (NSString *)previewText;
@end

NS_ASSUME_NONNULL_END
