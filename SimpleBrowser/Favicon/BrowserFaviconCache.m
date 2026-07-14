#import "BrowserFaviconCache.h"
#import "BrowserFaviconUtil.h"
#import "BrowserAppInfo.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kIndexFileName = @"index.plist";
static NSString * const kBlobsDirName = @"blobs";
static NSString * const kEntryFileNameKey = @"fileName";
static NSString * const kEntrySourceURLKey = @"sourceURL";
static NSString * const kEntrySourceChannelKey = @"sourceChannel";
static NSString * const kEntryUpdatedAtKey = @"updatedAt";
static NSString * const kEntryByteSizeKey = @"byteSize";

static const NSUInteger kMaxPixelEdge = 180; // 覆盖常见 apple-touch-icon，Retina Launchpad 更清晰
static const NSUInteger kMemoryCacheLimit = 128;
static const NSUInteger kMaxDiskEntries = 500;

@interface BrowserFaviconCache ()
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *memoryCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *indexMap;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

@implementation BrowserFaviconCache

+ (instancetype)sharedCache {
    static BrowserFaviconCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[BrowserFaviconCache alloc] initPrivate];
    });
    return cache;
}

- (instancetype)init {
    return [self initPrivate];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = kMemoryCacheLimit;
        _ioQueue = dispatch_queue_create("com.meobrowser.favicon.cache", DISPATCH_QUEUE_SERIAL);
        _indexMap = [NSMutableDictionary dictionary];
        [self loadIndexUnlocked];
    }
    return self;
}

#pragma mark - Paths

+ (NSURL *)cacheDirectoryURL {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                    inDomains:NSUserDomainMask];
    NSURL *appSupport = urls.firstObject;
    NSString *appName = BrowserAppDisplayName.length > 0 ? BrowserAppDisplayName : @"MeoBrowser";
    return [[appSupport URLByAppendingPathComponent:appName isDirectory:YES]
            URLByAppendingPathComponent:@"Favicons" isDirectory:YES];
}

+ (NSURL *)blobsDirectoryURL {
    return [[self cacheDirectoryURL] URLByAppendingPathComponent:kBlobsDirName isDirectory:YES];
}

+ (NSURL *)indexFileURL {
    return [[self cacheDirectoryURL] URLByAppendingPathComponent:kIndexFileName];
}

+ (BOOL)ensureDirectoriesExist:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *cacheDir = [self cacheDirectoryURL];
    NSURL *blobsDir = [self blobsDirectoryURL];
    if (![fm createDirectoryAtURL:cacheDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    if (![fm createDirectoryAtURL:blobsDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    return YES;
}

#pragma mark - Host normalize

- (nullable NSString *)normalizedHost:(NSString *)host {
    NSString *trimmed = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    return trimmed.lowercaseString;
}

#pragma mark - Index IO

- (void)loadIndexUnlocked {
    NSURL *indexURL = [[self class] indexFileURL];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:indexURL];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        self.indexMap = [NSMutableDictionary dictionary];
        return;
    }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    [plist enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSDictionary class]]) {
            return;
        }
        map[key] = obj;
    }];
    self.indexMap = map;
}

- (BOOL)persistIndexUnlocked {
    NSError *error = nil;
    if (![[self class] ensureDirectoriesExist:&error]) {
        return NO;
    }
    NSURL *indexURL = [[self class] indexFileURL];
    return [self.indexMap writeToURL:indexURL atomically:YES];
}

#pragma mark - File naming

- (NSString *)blobFileNameForHost:(NSString *)host {
    const char *cStr = host.UTF8String ?: "";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:16];
    for (NSUInteger i = 0; i < 8; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [hex stringByAppendingString:@".png"];
}

- (NSURL *)blobURLForFileName:(NSString *)fileName {
    return [[[self class] blobsDirectoryURL] URLByAppendingPathComponent:fileName];
}

#pragma mark - LRU

- (void)evictIfNeededUnlocked {
    NSUInteger count = self.indexMap.count;
    if (count <= kMaxDiskEntries) {
        return;
    }
    NSArray<NSString *> *hosts = [self.indexMap keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSTimeInterval ua = [a[kEntryUpdatedAtKey] doubleValue];
        NSTimeInterval ub = [b[kEntryUpdatedAtKey] doubleValue];
        if (ua < ub) {
            return NSOrderedAscending;
        }
        if (ua > ub) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    NSUInteger overflow = count - kMaxDiskEntries;
    for (NSUInteger i = 0; i < overflow && i < hosts.count; i++) {
        [self removeHostUnlocked:hosts[i]];
    }
}

#pragma mark - Public

- (nullable NSImage *)imageForHost:(NSString *)host {
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        return nil;
    }
    return [self.memoryCache objectForKey:key];
}

- (void)loadImageForHost:(NSString *)host
              completion:(void (^)(NSImage * _Nullable image))completion {
    if (!completion) {
        return;
    }
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }

    NSImage *cached = [self.memoryCache objectForKey:key];
    if (cached != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached);
        });
        return;
    }

    dispatch_async(self.ioQueue, ^{
        NSImage *diskImage = [self loadDiskImageUnlockedForHost:key];
        if (diskImage != nil) {
            [self.memoryCache setObject:diskImage forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(diskImage);
        });
    });
}

- (nullable NSImage *)imageForHostLoadingFromDiskIfNeeded:(NSString *)host {
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        return nil;
    }
    NSImage *cached = [self.memoryCache objectForKey:key];
    if (cached != nil) {
        return cached;
    }
    __block NSImage *diskImage = nil;
    dispatch_sync(self.ioQueue, ^{
        diskImage = [self loadDiskImageUnlockedForHost:key];
    });
    if (diskImage != nil) {
        [self.memoryCache setObject:diskImage forKey:key];
    }
    return diskImage;
}

- (nullable NSImage *)loadDiskImageUnlockedForHost:(NSString *)key {
    NSDictionary *entry = self.indexMap[key];
    NSString *fileName = entry[kEntryFileNameKey];
    if (![fileName isKindOfClass:[NSString class]] || fileName.length == 0) {
        return nil;
    }
    NSURL *fileURL = [self blobURLForFileName:fileName];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:fileURL];
    if (image != nil && image.size.width > 0 && image.size.height > 0) {
        return image;
    }
    return nil;
}

- (nullable NSString *)sourceURLForHost:(NSString *)host {
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        return nil;
    }
    __block NSString *sourceURL = nil;
    dispatch_sync(self.ioQueue, ^{
        id value = self.indexMap[key][kEntrySourceURLKey];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            sourceURL = value;
        }
    });
    return sourceURL;
}

- (nullable NSString *)sourceChannelForHost:(NSString *)host {
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        return nil;
    }
    __block NSString *channel = nil;
    dispatch_sync(self.ioQueue, ^{
        id value = self.indexMap[key][kEntrySourceChannelKey];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            channel = value;
        }
    });
    return channel;
}

- (BOOL)storeImage:(NSImage *)image
           forHost:(NSString *)host
         sourceURL:(nullable NSString *)sourceURL
           channel:(nullable NSString *)channel {
    NSString *key = [self normalizedHost:host];
    if (key == nil || image == nil) {
        return NO;
    }

    NSData *pngData = BrowserFaviconPNGDataByScalingImage(image, kMaxPixelEdge);
    if (pngData.length == 0) {
        return NO;
    }
    NSImage *displayImage = BrowserFaviconImageFromData(pngData);
    if (displayImage == nil) {
        return NO;
    }

    NSString *fileName = [self blobFileNameForHost:key];
    __block BOOL ok = NO;
    dispatch_sync(self.ioQueue, ^{
        NSError *error = nil;
        if (![[self class] ensureDirectoriesExist:&error]) {
            return;
        }

        NSDictionary *oldEntry = self.indexMap[key];
        NSString *oldFileName = oldEntry[kEntryFileNameKey];
        NSURL *outURL = [self blobURLForFileName:fileName];
        [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
        if (![pngData writeToURL:outURL options:NSDataWritingAtomic error:&error]) {
            return;
        }

        if ([oldFileName isKindOfClass:[NSString class]] &&
            oldFileName.length > 0 &&
            ![oldFileName isEqualToString:fileName]) {
            NSURL *oldURL = [self blobURLForFileName:oldFileName];
            [[NSFileManager defaultManager] removeItemAtURL:oldURL error:nil];
        }

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[kEntryFileNameKey] = fileName;
        entry[kEntryUpdatedAtKey] = @([[NSDate date] timeIntervalSince1970]);
        entry[kEntryByteSizeKey] = @(pngData.length);
        if (sourceURL.length > 0) {
            entry[kEntrySourceURLKey] = sourceURL;
        }
        if (channel.length > 0) {
            entry[kEntrySourceChannelKey] = channel;
        }
        self.indexMap[key] = entry;
        [self evictIfNeededUnlocked];
        ok = [self persistIndexUnlocked];
    });

    if (ok) {
        [self.memoryCache setObject:displayImage forKey:key];
    }
    return ok;
}

- (void)removeHost:(NSString *)host {
    NSString *key = [self normalizedHost:host];
    if (key == nil) {
        return;
    }
    dispatch_sync(self.ioQueue, ^{
        [self removeHostUnlocked:key];
        [self persistIndexUnlocked];
    });
    [self.memoryCache removeObjectForKey:key];
}

- (void)removeHostUnlocked:(NSString *)key {
    NSDictionary *entry = self.indexMap[key];
    NSString *fileName = entry[kEntryFileNameKey];
    if ([fileName isKindOfClass:[NSString class]] && fileName.length > 0) {
        NSURL *fileURL = [self blobURLForFileName:fileName];
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    }
    [self.indexMap removeObjectForKey:key];
}

- (void)clearMemoryCache {
    [self.memoryCache removeAllObjects];
}

@end
