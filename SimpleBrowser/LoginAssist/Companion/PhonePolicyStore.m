#import "PhonePolicyStore.h"
#import "PhoneRuleClassifier.h"

static NSString * const kPhonePolicyStoreKey = @"MeoPhonePolicyEntriesV1";

@implementation PhonePolicyEntry
@end

@interface PhonePolicyStore ()
@property (nonatomic, strong) NSMutableArray<PhonePolicyEntry *> *entries;
@end

@implementation PhonePolicyStore

+ (instancetype)sharedStore {
    static PhonePolicyStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
        [store reload];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (void)reload {
    [self.entries removeAllObjects];
    NSArray *raw = [NSUserDefaults.standardUserDefaults arrayForKey:kPhonePolicyStoreKey];
    if (![raw isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = (NSDictionary *)item;
        PhonePolicyEntry *e = [[PhonePolicyEntry alloc] init];
        e.entryID = [d[@"id"] isKindOfClass:[NSString class]] ? d[@"id"] : [[NSUUID UUID] UUIDString];
        e.numberE164 = [d[@"numberE164"] isKindOfClass:[NSString class]] ? d[@"numberE164"] : @"";
        e.displayName = [d[@"displayName"] isKindOfClass:[NSString class]] ? d[@"displayName"] : @"";
        e.category = [d[@"category"] isKindOfClass:[NSString class]] ? d[@"category"] : @"unknown";
        e.notes = [d[@"notes"] isKindOfClass:[NSString class]] ? d[@"notes"] : @"";
        e.updatedAt = [d[@"updatedAt"] respondsToSelector:@selector(doubleValue)]
            ? [d[@"updatedAt"] doubleValue] : 0;
        [self.entries addObject:e];
    }
}

- (void)persist {
    NSMutableArray *arr = [NSMutableArray array];
    for (PhonePolicyEntry *e in self.entries) {
        [arr addObject:@{
            @"id": e.entryID ?: @"",
            @"numberE164": e.numberE164 ?: @"",
            @"displayName": e.displayName ?: @"",
            @"category": e.category ?: @"unknown",
            @"notes": e.notes ?: @"",
            @"updatedAt": @(e.updatedAt),
        }];
    }
    [NSUserDefaults.standardUserDefaults setObject:arr forKey:kPhonePolicyStoreKey];
}

- (NSArray<PhonePolicyEntry *> *)allEntries {
    return [self.entries copy];
}

- (NSString *)canonicalKeyForNumber:(NSString *)number {
    NSString *digits = [PhoneRuleClassifier normalizedDigits:number];
    if (digits.length == 11 && [digits hasPrefix:@"1"]) {
        return [@"+86" stringByAppendingString:digits];
    }
    if (digits.length > 0) {
        return [number hasPrefix:@"+"] ? [@"+" stringByAppendingString:digits] : digits;
    }
    return number ?: @"";
}

- (nullable PhonePolicyEntry *)entryForNumber:(NSString *)number {
    NSString *key = [self canonicalKeyForNumber:number];
    NSString *digits = [PhoneRuleClassifier normalizedDigits:number];
    for (PhonePolicyEntry *e in self.entries) {
        if ([e.numberE164 isEqualToString:key]) {
            return e;
        }
        NSString *ed = [PhoneRuleClassifier normalizedDigits:e.numberE164];
        if (digits.length > 0 && [ed isEqualToString:digits]) {
            return e;
        }
    }
    return nil;
}

- (void)upsertDisplayName:(NSString *)name
                 category:(NSString *)category
                forNumber:(NSString *)number {
    if (number.length == 0) {
        return;
    }
    NSString *key = [self canonicalKeyForNumber:number];
    PhonePolicyEntry *e = [self entryForNumber:number];
    if (!e) {
        e = [[PhonePolicyEntry alloc] init];
        e.entryID = [[NSUUID UUID] UUIDString];
        e.numberE164 = key;
        [self.entries insertObject:e atIndex:0];
    }
    e.displayName = name ?: @"";
    e.category = category.length > 0 ? category : @"personal";
    e.updatedAt = [NSDate date].timeIntervalSince1970;
    [self persist];
}

- (void)removeEntryID:(NSString *)entryID {
    if (entryID.length == 0) return;
    NSIndexSet *idx = [self.entries indexesOfObjectsPassingTest:^BOOL(PhonePolicyEntry *obj, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop;
        return [obj.entryID isEqualToString:entryID];
    }];
    [self.entries removeObjectsAtIndexes:idx];
    [self persist];
}

@end
