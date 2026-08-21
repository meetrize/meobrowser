#import <Foundation/Foundation.h>

@class PagePack;
@class PagePackFile;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const PagePackStoreDidChangeNotification;

@interface PagePackStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<PagePack *> *)allPacks;
- (nullable PagePack *)packWithID:(NSString *)packID;
- (NSArray<PagePack *> *)packsMatchingURL:(nullable NSURL *)url;
- (NSArray<PagePack *> *)enabledPacksMatchingURL:(nullable NSURL *)url;

- (BOOL)upsertPack:(PagePack *)pack error:(NSError *_Nullable *_Nullable)error;
- (BOOL)setPack:(NSString *)packID enabled:(BOOL)enabled error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deletePackWithID:(NSString *)packID error:(NSError *_Nullable *_Nullable)error;

- (nullable NSString *)contentOfFile:(NSString *)fileName inPack:(NSString *)packID error:(NSError *_Nullable *_Nullable)error;
- (BOOL)writeContent:(NSString *)content
            fileName:(NSString *)fileName
              inPack:(NSString *)packID
               error:(NSError *_Nullable *_Nullable)error;

- (BOOL)addFile:(PagePackFile *)file
         toPack:(NSString *)packID
  initialContent:(nullable NSString *)content
          error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeFileNamed:(NSString *)fileName
                 inPack:(NSString *)packID
                  error:(NSError *_Nullable *_Nullable)error;

/// 新建默认 Pack（当前 URL 的 match + 空 style.css），写入磁盘。
- (nullable PagePack *)createPackForURL:(nullable NSURL *)url
                                   name:(nullable NSString *)name
                                  error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
