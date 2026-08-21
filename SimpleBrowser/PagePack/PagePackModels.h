#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PagePackFileKind) {
    PagePackFileKindCSS = 0,
    PagePackFileKindJS = 1,
};

typedef NS_ENUM(NSInteger, PagePackRunAt) {
    PagePackRunAtDocumentStart = 0,
    PagePackRunAtDocumentEnd = 1,
    PagePackRunAtDocumentIdle = 2,
};

@interface PagePackFile : NSObject <NSCopying>

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) PagePackFileKind kind;
@property (nonatomic, assign) PagePackRunAt runAt;
@property (nonatomic, assign) BOOL mainFrameOnly;

+ (nullable instancetype)fileWithName:(NSString *)name kind:(PagePackFileKind)kind;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fileWithDictionary:(NSDictionary *)dictionary;

+ (BOOL)isValidFileName:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)kindForFileName:(NSString *)name outKind:(nullable PagePackFileKind *)outKind;

@end

@interface PagePack : NSObject <NSCopying>

@property (nonatomic, copy) NSString *packID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *packDescription;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy, nullable) NSString *sourceURL;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSArray<NSString *> *matches;
@property (nonatomic, copy) NSArray<NSString *> *excludes;
@property (nonatomic, copy) NSArray<PagePackFile *> *files;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;

+ (instancetype)packWithName:(NSString *)name matches:(NSArray<NSString *> *)matches;

- (nullable PagePackFile *)fileNamed:(NSString *)name;
- (NSString *)matchSummary;
- (BOOL)hasDangerousMatch;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)packWithDictionary:(NSDictionary *)dictionary;

@end

FOUNDATION_EXPORT NSErrorDomain const PagePackErrorDomain;

typedef NS_ENUM(NSInteger, PagePackErrorCode) {
    PagePackErrorInvalidArgument = 1,
    PagePackErrorNotFound = 2,
    PagePackErrorIO = 3,
    PagePackErrorDuplicate = 4,
};

NS_ASSUME_NONNULL_END
