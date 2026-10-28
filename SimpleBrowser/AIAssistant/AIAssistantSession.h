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
@property (nonatomic, copy) NSString *content;
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
@property (nonatomic, assign) AIAssistantSessionConnection connection;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)sessionFromDictionary:(NSDictionary *)dict;
- (NSString *)previewText;
@end

NS_ASSUME_NONNULL_END
