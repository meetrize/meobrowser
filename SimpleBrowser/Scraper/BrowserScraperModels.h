#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserScraperMode) {
    BrowserScraperModeScalar = 0,
    BrowserScraperModeTable = 1,
};

typedef NS_ENUM(NSInteger, BrowserScraperFieldKind) {
    BrowserScraperFieldKindText = 0,
    BrowserScraperFieldKindHref = 1,
    BrowserScraperFieldKindSrc = 2,
    BrowserScraperFieldKindAttribute = 3,
    BrowserScraperFieldKindHTML = 4,
};

typedef NS_ENUM(NSInteger, BrowserScraperPaginationType) {
    BrowserScraperPaginationTypeNone = 0,
    BrowserScraperPaginationTypeNextButton = 1,
    BrowserScraperPaginationTypePageNumbers = 2,
    BrowserScraperPaginationTypeLoadMore = 3,
    BrowserScraperPaginationTypeInfiniteScroll = 4,
};

typedef NS_ENUM(NSInteger, BrowserScraperSessionMode) {
    BrowserScraperSessionReuseProfile = 0,
    BrowserScraperSessionEphemeral = 1,
};

typedef NS_ENUM(NSInteger, BrowserScraperSinkType) {
    BrowserScraperSinkTypeXLSX = 0,
    BrowserScraperSinkTypeCSV = 1,
    BrowserScraperSinkTypeJSON = 2,
    BrowserScraperSinkTypeMySQL = 3,
};

typedef NS_ENUM(NSInteger, BrowserScraperMySQLWriteMode) {
    BrowserScraperMySQLWriteModeAppend = 0,
    BrowserScraperMySQLWriteModeReplace = 1,
    BrowserScraperMySQLWriteModeUpsert = 2,
};

@interface BrowserScraperField : NSObject <NSCopying>
@property (nonatomic, copy) NSString *fieldID;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BrowserScraperFieldKind kind;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy, nullable) NSString *attribute;
+ (instancetype)fieldWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
+ (NSString *)stringFromKind:(BrowserScraperFieldKind)kind;
+ (BrowserScraperFieldKind)kindFromString:(NSString *)string;
@end

@interface BrowserScraperPagination : NSObject <NSCopying>
@property (nonatomic, assign) BrowserScraperPaginationType type;
@property (nonatomic, copy) NSString *selector;
@property (nonatomic, assign) NSInteger maxPages;
@property (nonatomic, assign) NSInteger maxRows;
@property (nonatomic, assign) NSInteger pageDelayMs;
@property (nonatomic, copy) NSString *waitForSelector;
@property (nonatomic, assign) NSInteger waitTimeoutMs;
@property (nonatomic, assign) NSInteger scrollStepPx;
@property (nonatomic, assign) NSInteger scrollSettleMs;
+ (instancetype)defaultPagination;
+ (instancetype)paginationWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
+ (NSString *)stringFromType:(BrowserScraperPaginationType)type;
+ (BrowserScraperPaginationType)typeFromString:(NSString *)string;
@end

@interface BrowserScraperMySQLConfig : NSObject <NSCopying>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *database;
@property (nonatomic, copy) NSString *user;
@property (nonatomic, copy) NSString *passwordKeychainAccount;
@property (nonatomic, copy) NSString *table;
@property (nonatomic, assign) BrowserScraperMySQLWriteMode writeMode;
@property (nonatomic, copy) NSArray<NSString *> *upsertKeys;
+ (instancetype)configWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface BrowserScraperSink : NSObject <NSCopying>
@property (nonatomic, assign) BrowserScraperSinkType type;
@property (nonatomic, copy, nullable) NSString *filePath;
@property (nonatomic, strong, nullable) BrowserScraperMySQLConfig *mysql;
+ (instancetype)sinkWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface BrowserScraperSchedule : NSObject <NSCopying>
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger intervalMinutes;
@property (nonatomic, strong, nullable) NSDate *startAt;
@property (nonatomic, strong, nullable) NSDate *endAt;
@property (nonatomic, copy, nullable) NSString *launchAgentLabel;
+ (instancetype)defaultSchedule;
+ (instancetype)scheduleWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface BrowserScraperMatch : NSObject <NSCopying>
@property (nonatomic, copy) NSArray<NSString *> *hosts;
@property (nonatomic, copy, nullable) NSString *urlContains;
+ (instancetype)matchWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)matchesURL:(NSURL *)url;
@end

@interface BrowserScraperRecipe : NSObject <NSCopying>
@property (nonatomic, copy) NSString *recipeID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, strong) BrowserScraperMatch *match;
@property (nonatomic, copy, nullable) NSString *startURL;
@property (nonatomic, assign) BrowserScraperMode mode;
@property (nonatomic, copy) NSString *containerPath;
@property (nonatomic, copy) NSString *rowPath;
@property (nonatomic, copy) NSArray<BrowserScraperField *> *fields;
@property (nonatomic, strong) BrowserScraperPagination *pagination;
@property (nonatomic, copy) NSArray<NSString *> *dedupeKeyFieldIds;
@property (nonatomic, assign) BOOL dropEmptyRows;
@property (nonatomic, assign) BOOL absoluteURLs;
@property (nonatomic, assign) BrowserScraperSessionMode session;
@property (nonatomic, strong) BrowserScraperSchedule *schedule;
@property (nonatomic, strong) BrowserScraperSink *sink;
+ (instancetype)blankRecipeNamed:(NSString *)name;
+ (instancetype)recipeWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
+ (NSString *)stringFromMode:(BrowserScraperMode)mode;
+ (BrowserScraperMode)modeFromString:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
