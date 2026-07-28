#import <Foundation/Foundation.h>

@class FormMemo;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const FormMemoStoreDidChangeNotification;

@interface FormMemoStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<FormMemo *> *)allMemos;
- (NSArray<FormMemo *> *)memosMatchingURL:(NSURL *)url;
- (nullable FormMemo *)defaultMemoMatchingURL:(NSURL *)url;
- (nullable FormMemo *)memoWithID:(NSString *)memoID;

- (BOOL)upsertMemo:(FormMemo *)memo error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteMemoWithID:(NSString *)memoID error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setDefaultMemoID:(NSString *)memoID error:(NSError * _Nullable * _Nullable)error;
/// 云同步写回：整表替换，保留各 memo.updatedAt，不强制刷新时间戳。
- (BOOL)replaceAllMemos:(NSArray<FormMemo *> *)memos error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
