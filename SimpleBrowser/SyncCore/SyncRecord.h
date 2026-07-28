#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SyncRecord : NSObject <NSCopying>

@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) long long updatedAt;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign) BOOL deleted;
@property (nonatomic, assign) NSInteger schemaVersion;
@property (nonatomic, copy) NSDictionary *payload;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)recordWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
