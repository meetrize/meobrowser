#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhonePolicyEntry : NSObject
@property (nonatomic, copy) NSString *entryID;
@property (nonatomic, copy) NSString *numberE164;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *notes;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@end

/// Mac 本地号码备注策略库（UserDefaults JSON）。
@interface PhonePolicyStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<PhonePolicyEntry *> *)allEntries;
- (nullable PhonePolicyEntry *)entryForNumber:(nullable NSString *)number;
- (void)upsertDisplayName:(NSString *)name
                 category:(NSString *)category
                forNumber:(NSString *)number;
- (void)removeEntryID:(NSString *)entryID;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
