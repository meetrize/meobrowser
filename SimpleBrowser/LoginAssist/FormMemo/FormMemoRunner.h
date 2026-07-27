#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@class FormMemoField;

NS_ASSUME_NONNULL_BEGIN

@interface FormMemoFillFailure : NSObject
@property (nonatomic, copy) NSString *fieldID;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *reason;
@end

@interface FormMemoFillResult : NSObject
@property (nonatomic, assign) NSUInteger successCount;
@property (nonatomic, assign) NSUInteger attemptedCount;
@property (nonatomic, copy) NSArray<FormMemoFillFailure *> *failures;
@property (nonatomic, readonly) BOOL allSucceeded;
@property (nonatomic, readonly) BOOL anySucceeded;
- (NSString *)summaryMessage;
@end

typedef void (^FormMemoRunnerCompletion)(FormMemoFillResult *result);

@interface FormMemoRunner : NSObject

/// 按顺序填入字段；只填不交。字段失败不阻断后续。
+ (void)fillFields:(NSArray<FormMemoField *> *)fields
         inWebView:(WKWebView *)webView
       waitTimeout:(NSInteger)timeoutMs
        completion:(FormMemoRunnerCompletion)completion;

+ (void)cancelAll;

@end

NS_ASSUME_NONNULL_END
