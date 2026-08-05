#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserHistoryEntry : NSObject <NSCopying>

@property (nonatomic, copy) NSString *entryID;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *title;
/// Unix 秒。
@property (nonatomic, assign) NSTimeInterval visitTime;
@property (nonatomic, assign) NSInteger visitCount;
/// Unix 秒。
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign, getter=isDeleted) BOOL deleted;

+ (instancetype)entryWithURL:(NSString *)url
                       title:(NSString *)title
                    deviceId:(NSString *)deviceId;

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

@property (nonatomic, readonly, copy) NSString *displayHost;

@end

NS_ASSUME_NONNULL_END
