#import "PhoneAppIconCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

NSNotificationName const PhoneAppIconCacheDidChangeNotification = @"PhoneAppIconCacheDidChangeNotification";
NSString * const PhoneAppIconCachePackageNameKey = @"packageName";

static const NSUInteger kMaxPNGBytes = 12 * 1024;
static const NSInteger kMaxPixelEdge = 128;
static const CGFloat kIconPointSize = 28.0;

@interface PhoneAppIconCache ()
@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, copy) NSString *indexPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *index;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PhoneAppIconCache

+ (instancetype)sharedCache {
    static PhoneAppIconCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[self alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _index = [NSMutableDictionary dictionary];
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 64;
        _queue = dispatch_queue_create("com.meobrowser.phoneAppIconCache", DISPATCH_QUEUE_SERIAL);
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *root = paths.firstObject ?: NSTemporaryDirectory();
        _directoryPath = [[root stringByAppendingPathComponent:@"MeoBrowser"]
                          stringByAppendingPathComponent:@"PhoneAppIcons"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_directoryPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        _indexPath = [_directoryPath stringByAppendingPathComponent:@"index.json"];
        dispatch_sync(_queue, ^{
            [self loadIndexLocked];
        });
    }
    return self;
}

#pragma mark - Public

- (nullable NSImage *)imageForPackage:(NSString *)packageName {
    if (packageName.length == 0 || [packageName isEqualToString:@"otp"]) {
        return nil;
    }
    NSImage *mem = [self.memoryCache objectForKey:packageName];
    if (mem) {
        return mem;
    }
    __block NSImage *image = nil;
    dispatch_sync(self.queue, ^{
        NSDictionary *entry = self.index[packageName];
        NSString *file = entry[@"file"];
        if (![file isKindOfClass:[NSString class]] || file.length == 0) {
            return;
        }
        NSString *path = [self.directoryPath stringByAppendingPathComponent:file];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            return;
        }
        image = [[NSImage alloc] initWithData:data];
        if (image) {
            image.size = NSMakeSize(kIconPointSize, kIconPointSize);
        }
    });
    if (image) {
        [self.memoryCache setObject:image forKey:packageName];
    }
    return image;
}

- (nullable NSString *)hashForPackage:(NSString *)packageName {
    if (packageName.length == 0) {
        return nil;
    }
    __block NSString *hash = nil;
    dispatch_sync(self.queue, ^{
        id value = self.index[packageName][@"hash"];
        if ([value isKindOfClass:[NSString class]]) {
            hash = value;
        }
    });
    return hash;
}

- (BOOL)storePNGData:(NSData *)data
             package:(NSString *)packageName
            iconHash:(NSString *)iconHash
            appLabel:(NSString *)appLabel
               error:(NSError **)error {
    if (packageName.length == 0 || iconHash.length == 0 || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PhoneAppIconCache" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"invalid arguments"}];
        }
        return NO;
    }
    if (data.length > kMaxPNGBytes) {
        if (error) {
            *error = [NSError errorWithDomain:@"PhoneAppIconCache" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"png too large"}];
        }
        return NO;
    }
    NSImage *probe = [[NSImage alloc] initWithData:data];
    if (!probe) {
        if (error) {
            *error = [NSError errorWithDomain:@"PhoneAppIconCache" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"decode failed"}];
        }
        return NO;
    }
    NSSize px = probe.size;
    // Prefer pixel size from representations when available
    NSArray *reps = probe.representations;
    if (reps.count > 0) {
        NSImageRep *rep = reps.firstObject;
        px = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
    }
    if (px.width > kMaxPixelEdge || px.height > kMaxPixelEdge || px.width < 1 || px.height < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"PhoneAppIconCache" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"invalid dimensions"}];
        }
        return NO;
    }

    __block BOOL ok = NO;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSString *existingHash = self.index[packageName][@"hash"];
        if ([existingHash isKindOfClass:[NSString class]] && [existingHash isEqualToString:iconHash]) {
            ok = YES;
            return;
        }
        NSString *fileName = [[self sanitizePackage:packageName] stringByAppendingString:@".png"];
        NSString *path = [self.directoryPath stringByAppendingPathComponent:fileName];
        if (![data writeToFile:path options:NSDataWritingAtomic error:&localError]) {
            return;
        }
        self.index[packageName] = @{
            @"hash": iconHash,
            @"file": fileName,
            @"appLabel": appLabel ?: @"",
            @"updatedAt": @([NSDate date].timeIntervalSince1970),
        };
        [self persistIndexLocked];
        ok = YES;
    });
    if (!ok) {
        if (error && localError) {
            *error = localError;
        }
        return NO;
    }

    NSImage *display = [[NSImage alloc] initWithData:data];
    display.size = NSMakeSize(kIconPointSize, kIconPointSize);
    [self.memoryCache setObject:display forKey:packageName];

    os_log_info(OS_LOG_DEFAULT, "app icon stored pkg=%{public}@ hash=%{public}@ bytes=%lu",
                packageName, iconHash, (unsigned long)data.length);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PhoneAppIconCacheDidChangeNotification
                                                            object:self
                                                          userInfo:@{PhoneAppIconCachePackageNameKey: packageName}];
    });
    return YES;
}

- (NSArray<NSString *> *)packagesMissingFrom:(NSArray<NSString *> *)packages {
    __block NSMutableArray<NSString *> *missing = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        for (NSString *pkg in packages) {
            if (pkg.length == 0) continue;
            if (!self.index[pkg]) {
                [missing addObject:pkg];
            }
        }
    });
    return missing;
}

#pragma mark - Placeholders

+ (NSImage *)placeholderImageWithLabel:(NSString *)label package:(NSString *)packageName {
    NSString *seed = packageName.length > 0 ? packageName : (label ?: @"?");
    NSString *glyph = @"?";
    NSString *source = label.length > 0 ? label : seed;
    for (NSUInteger i = 0; i < source.length; i++) {
        unichar c = [source characterAtIndex:i];
        if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            glyph = [[source substringWithRange:NSMakeRange(i, 1)] uppercaseString];
            break;
        }
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(kIconPointSize, kIconPointSize)];
    [image lockFocus];
    NSColor *bg = [self colorForSeed:seed];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, kIconPointSize, kIconPointSize)
                                                         xRadius:6 yRadius:6];
    [bg setFill];
    [path fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize textSize = [glyph sizeWithAttributes:attrs];
    NSPoint p = NSMakePoint((kIconPointSize - textSize.width) / 2.0,
                            (kIconPointSize - textSize.height) / 2.0);
    [glyph drawAtPoint:p withAttributes:attrs];
    [image unlockFocus];
    return image;
}

+ (NSImage *)otpPlaceholderImage {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:16
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleMedium];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"lock.shield.fill"
                                    accessibilityDescription:nil];
        if (symbol) {
            NSImage *configured = [symbol imageWithSymbolConfiguration:config];
            NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(kIconPointSize, kIconPointSize)];
            [canvas lockFocus];
            [[NSColor colorWithCalibratedWhite:0.92 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, kIconPointSize, kIconPointSize)
                                             xRadius:6 yRadius:6] fill];
            NSSize sz = configured.size;
            NSPoint origin = NSMakePoint((kIconPointSize - sz.width) / 2.0,
                                         (kIconPointSize - sz.height) / 2.0);
            [configured drawAtPoint:origin fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
            [canvas unlockFocus];
            return canvas;
        }
    }
    return [self placeholderImageWithLabel:@"码" package:@"otp"];
}

+ (NSColor *)colorForSeed:(NSString *)seed {
    NSUInteger hash = seed.hash;
    CGFloat hue = ((hash % 360) / 360.0);
    return [NSColor colorWithCalibratedHue:hue saturation:0.45 brightness:0.72 alpha:1.0];
}

#pragma mark - Private

- (NSString *)sanitizePackage:(NSString *)packageName {
    NSMutableString *out = [NSMutableString stringWithCapacity:packageName.length];
    for (NSUInteger i = 0; i < packageName.length; i++) {
        unichar c = [packageName characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
            c == '.' || c == '_' || c == '-') {
            [out appendFormat:@"%C", c];
        } else {
            [out appendString:@"_"];
        }
    }
    if (out.length == 0) {
        return @"unknown";
    }
    return out;
}

- (void)loadIndexLocked {
    [self.index removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:self.indexPath];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *entries = json[@"entries"];
    if (![entries isKindOfClass:[NSDictionary class]]) return;
    [entries enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]]) {
            self.index[key] = obj;
        }
    }];
}

- (void)persistIndexLocked {
    NSDictionary *root = @{@"version": @1, @"entries": self.index};
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    [data writeToFile:self.indexPath options:NSDataWritingAtomic error:nil];
}

@end
