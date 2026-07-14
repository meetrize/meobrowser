#import "BrowserWallpaperStore.h"
#import "BrowserAppInfo.h"
#import <ImageIO/ImageIO.h>

NSString * const BrowserWallpaperDidChangeNotification = @"BrowserWallpaperDidChangeNotification";
NSString * const BrowserWallpaperChangeReasonKey = @"reason";

static NSString * const kEnabledDefaultsKey = @"launchpadWallpaperEnabled";
static NSString * const kScrimDefaultsKey = @"launchpadWallpaperScrimAlpha";
static NSString * const kDisplayFileName = @"display.jpg";
static NSString * const kMetaFileName = @"meta.plist";
static NSString * const kMetaEnabledKey = @"enabled";
static NSString * const kMetaSourceFileNameKey = @"sourceFileName";
static NSString * const kMetaDisplayMaxPixelSizeKey = @"displayMaxPixelSize";
static NSString * const kMetaScrimAlphaKey = @"scrimAlpha";
static NSString * const kMetaContentModeKey = @"contentMode";
static NSString * const kMetaUpdatedAtKey = @"updatedAt";

static const CGFloat kDefaultScrimAlpha = 0.30;
static const CGFloat kMinScrimAlpha = 0.0;
static const CGFloat kMaxScrimAlpha = 0.70;
static const NSUInteger kAbsoluteMaxPixelEdge = 3840;
static const CGFloat kJPEGQuality = 0.85;
/// 压暗后有效亮度低于此值 → 白字；否则黑字。
static const CGFloat kShortcutTitleLuminanceThreshold = 0.50;
static const NSInteger kLuminanceSampleSide = 32;

static NSString * const kWallpaperErrorDomain = @"BrowserWallpaperStore";

@interface BrowserWallpaperStore ()
@property (nonatomic, assign) BOOL enabledFlag;
@property (nonatomic, assign) CGFloat scrimAlpha;
@property (nonatomic, copy, nullable) NSString *sourceFileName;
@property (nonatomic, strong, nullable) NSImage *displayImage;
@property (nonatomic, assign) NSInteger acquireCount;
@property (nonatomic, assign) NSInteger displayLoadGeneration;
@property (nonatomic, strong) dispatch_queue_t importQueue;
@property (nonatomic, assign) CGFloat cachedImageLuminance;
@property (nonatomic, assign) BOOL hasCachedImageLuminance;
@end

/// 将壁纸缩到小图后求平均相对亮度（0～1）。失败时返回 0.5。
static CGFloat BrowserWallpaperAverageLuminance(NSImage *image) {
    if (image == nil) {
        return 0.5;
    }
    const NSInteger side = kLuminanceSampleSide;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (space == NULL) {
        space = CGColorSpaceCreateDeviceRGB();
    }
    CGContextRef ctx = CGBitmapContextCreate(NULL,
                                             (size_t)side,
                                             (size_t)side,
                                             8,
                                             0,
                                             space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (ctx == NULL) {
        return 0.5;
    }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextClearRect(ctx, CGRectMake(0, 0, side, side));
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext setCurrentContext:nsCtx];
    [image drawInRect:NSMakeRect(0, 0, side, side)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0
       respectFlipped:YES
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationMedium)}];
    [NSGraphicsContext setCurrentContext:previous];

    UInt8 *bytes = CGBitmapContextGetData(ctx);
    if (bytes == NULL) {
        CGContextRelease(ctx);
        return 0.5;
    }
    NSInteger bytesPerRow = (NSInteger)CGBitmapContextGetBytesPerRow(ctx);
    double sum = 0;
    NSInteger count = side * side;
    for (NSInteger y = 0; y < side; y++) {
        const UInt8 *row = bytes + y * bytesPerRow;
        for (NSInteger x = 0; x < side; x++) {
            const UInt8 *p = row + x * 4;
            CGFloat r = p[0] / 255.0;
            CGFloat g = p[1] / 255.0;
            CGFloat b = p[2] / 255.0;
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }
    }
    CGContextRelease(ctx);
    return (CGFloat)(sum / (double)count);
}

@implementation BrowserWallpaperStore

+ (instancetype)sharedStore {
    static BrowserWallpaperStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[BrowserWallpaperStore alloc] initPrivate];
    });
    return store;
}

- (instancetype)init {
    return [self initPrivate];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _importQueue = dispatch_queue_create("com.meobrowser.wallpaper.import", DISPATCH_QUEUE_SERIAL);
        _scrimAlpha = kDefaultScrimAlpha;
        _enabledFlag = YES;
        [self loadMetaFromDisk];
    }
    return self;
}

#pragma mark - Paths

+ (NSURL *)wallpaperDirectoryURL {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                    inDomains:NSUserDomainMask];
    NSURL *appSupport = urls.firstObject;
    NSString *appName = BrowserAppDisplayName.length > 0 ? BrowserAppDisplayName : @"MeoBrowser";
    return [[appSupport URLByAppendingPathComponent:appName isDirectory:YES]
            URLByAppendingPathComponent:@"LaunchpadWallpaper" isDirectory:YES];
}

+ (NSURL *)displayFileURL {
    return [[self wallpaperDirectoryURL] URLByAppendingPathComponent:kDisplayFileName];
}

+ (NSURL *)metaFileURL {
    return [[self wallpaperDirectoryURL] URLByAppendingPathComponent:kMetaFileName];
}

+ (BOOL)ensureDirectoryExists:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *dir = [self wallpaperDirectoryURL];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:dir.path isDirectory:&isDir] && isDir) {
        return YES;
    }
    return [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:error];
}

+ (NSUInteger)maxScreenPixelEdge {
    __block NSUInteger maxEdge = 1920;
    void (^compute)(void) = ^{
        NSUInteger edge = 0;
        for (NSScreen *screen in NSScreen.screens) {
            NSSize size = screen.frame.size;
            CGFloat scale = screen.backingScaleFactor;
            NSUInteger w = (NSUInteger)ceil(size.width * scale);
            NSUInteger h = (NSUInteger)ceil(size.height * scale);
            edge = MAX(edge, MAX(w, h));
        }
        if (edge == 0) {
            edge = 1920;
        }
        maxEdge = MIN(edge, kAbsoluteMaxPixelEdge);
    };
    if ([NSThread isMainThread]) {
        compute();
    } else {
        dispatch_sync(dispatch_get_main_queue(), compute);
    }
    return maxEdge;
}

#pragma mark - State

- (BOOL)hasDisplayFile {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[self class] displayFileURL].path];
}

- (BOOL)isWallpaperEnabled {
    return self.enabledFlag && self.hasDisplayFile;
}

- (NSColor *)shortcutTitleColor {
    BOOL showWallpaper = self.isWallpaperEnabled && self.displayImage != nil && self.hasCachedImageLuminance;
    if (!showWallpaper) {
        return [NSColor labelColor];
    }
    // 黑半透明 scrim 叠在图上：有效亮度 ≈ L * (1 - α)
    CGFloat effective = self.cachedImageLuminance * (1.0 - self.scrimAlpha);
    if (effective < kShortcutTitleLuminanceThreshold) {
        return [NSColor whiteColor];
    }
    return [NSColor blackColor];
}

- (void)updateCachedLuminanceFromDisplayImage {
    if (self.displayImage == nil) {
        self.hasCachedImageLuminance = NO;
        self.cachedImageLuminance = 0.5;
        return;
    }
    self.cachedImageLuminance = BrowserWallpaperAverageLuminance(self.displayImage);
    self.hasCachedImageLuminance = YES;
}

- (void)loadMetaFromDisk {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kEnabledDefaultsKey] != nil) {
        _enabledFlag = [defaults boolForKey:kEnabledDefaultsKey];
    }
    if ([defaults objectForKey:kScrimDefaultsKey] != nil) {
        _scrimAlpha = [self clampScrim:[defaults doubleForKey:kScrimDefaultsKey]];
    }

    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfURL:[[self class] metaFileURL]];
    if (![meta isKindOfClass:[NSDictionary class]]) {
        return;
    }
    if (meta[kMetaEnabledKey] != nil && [defaults objectForKey:kEnabledDefaultsKey] == nil) {
        _enabledFlag = [meta[kMetaEnabledKey] boolValue];
    }
    if (meta[kMetaScrimAlphaKey] != nil && [defaults objectForKey:kScrimDefaultsKey] == nil) {
        _scrimAlpha = [self clampScrim:[meta[kMetaScrimAlphaKey] doubleValue]];
    }
    id name = meta[kMetaSourceFileNameKey];
    if ([name isKindOfClass:[NSString class]]) {
        _sourceFileName = [name copy];
    }
}

- (CGFloat)clampScrim:(CGFloat)alpha {
    return MAX(kMinScrimAlpha, MIN(kMaxScrimAlpha, alpha));
}

- (void)persistMetaWithMaxPixelSize:(NSUInteger)maxPixelSize {
    NSError *error = nil;
    if (![[self class] ensureDirectoryExists:&error]) {
        NSLog(@"[Wallpaper] ensure directory failed: %@", error);
        return;
    }
    NSDictionary *meta = @{
        kMetaEnabledKey: @(self.enabledFlag),
        kMetaSourceFileNameKey: self.sourceFileName ?: @"",
        kMetaDisplayMaxPixelSizeKey: @(maxPixelSize),
        kMetaScrimAlphaKey: @(self.scrimAlpha),
        kMetaContentModeKey: @"aspectFill",
        kMetaUpdatedAtKey: [NSDate date],
    };
    [meta writeToURL:[[self class] metaFileURL] atomically:YES];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.enabledFlag forKey:kEnabledDefaultsKey];
    [defaults setDouble:self.scrimAlpha forKey:kScrimDefaultsKey];
}

- (void)postChangeReason:(NSString *)reason {
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserWallpaperDidChangeNotification
                                                        object:self
                                                      userInfo:@{BrowserWallpaperChangeReasonKey: reason}];
}

#pragma mark - Acquire / Release

- (void)acquireDisplayImage {
    NSAssert([NSThread isMainThread], @"acquireDisplayImage must be on main thread");
    self.acquireCount += 1;
    if (self.acquireCount == 1) {
        [self loadDisplayImageFromDiskIfNeeded];
    }
}

- (void)releaseDisplayImage {
    NSAssert([NSThread isMainThread], @"releaseDisplayImage must be on main thread");
    if (self.acquireCount <= 0) {
        return;
    }
    self.acquireCount -= 1;
    if (self.acquireCount == 0) {
        self.displayLoadGeneration += 1;
        self.displayImage = nil;
        self.hasCachedImageLuminance = NO;
    }
}

- (void)loadDisplayImageFromDiskIfNeeded {
    if (self.displayImage != nil) {
        return;
    }
    if (!self.hasDisplayFile) {
        return;
    }
    NSURL *url = [[self class] displayFileURL];
    NSInteger generation = ++self.displayLoadGeneration;
    dispatch_async(self.importQueue, ^{
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
        CGFloat luminance = 0.5;
        BOOL hasLuminance = NO;
        if (image != nil) {
            luminance = BrowserWallpaperAverageLuminance(image);
            hasLuminance = YES;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.displayLoadGeneration || self.acquireCount <= 0) {
                return;
            }
            if (self.displayImage != nil || image == nil) {
                return;
            }
            self.displayImage = image;
            self.cachedImageLuminance = luminance;
            self.hasCachedImageLuminance = hasLuminance;
            [self postChangeReason:@"reload"];
        });
    });
}

- (void)reloadDisplayImageKeepingAcquire {
    if (self.acquireCount <= 0) {
        self.displayImage = nil;
        self.hasCachedImageLuminance = NO;
        return;
    }
    self.displayLoadGeneration += 1;
    self.displayImage = nil;
    self.hasCachedImageLuminance = NO;
    [self loadDisplayImageFromDiskIfNeeded];
}

#pragma mark - Public mutators

- (void)setWallpaperEnabled:(BOOL)enabled {
    if (self.enabledFlag == enabled) {
        return;
    }
    self.enabledFlag = enabled;
    [self persistMetaWithMaxPixelSize:[[self class] maxScreenPixelEdge]];
    [self postChangeReason:@"enabled"];
}

- (void)setScrimAlpha:(CGFloat)alpha {
    CGFloat clamped = [self clampScrim:alpha];
    if (fabs(_scrimAlpha - clamped) < 0.0001) {
        return;
    }
    // 必须写 ivar：属性 setter 即本方法，self.scrimAlpha= 会无限递归栈溢出。
    _scrimAlpha = clamped;
    // 拖动滑杆时只先刷 UI；落盘节流，避免每次 mouse drag 同步写文件。
    [self schedulePersistMeta];
    [self postChangeReason:@"scrim"];
}

- (void)schedulePersistMeta {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(persistMetaNow)
                                               object:nil];
    [self performSelector:@selector(persistMetaNow) withObject:nil afterDelay:0.2];
}

- (void)persistMetaNow {
    [self persistMetaWithMaxPixelSize:[[self class] maxScreenPixelEdge]];
}

- (void)clearWallpaper {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *displayURL = [[self class] displayFileURL];
    NSURL *metaURL = [[self class] metaFileURL];
    [fm removeItemAtURL:displayURL error:nil];
    [fm removeItemAtURL:metaURL error:nil];
    self.sourceFileName = nil;
    self.enabledFlag = NO;
    self.displayImage = nil;
    self.hasCachedImageLuminance = NO;
    self.cachedImageLuminance = 0.5;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:kEnabledDefaultsKey];
    [self postChangeReason:@"clear"];
}

- (void)importImageFromURL:(NSURL *)fileURL
                completion:(void (^)(NSError * _Nullable error))completion {
    if (fileURL == nil) {
        if (completion) {
            completion([NSError errorWithDomain:kWallpaperErrorDomain
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"未选择图片"}]);
        }
        return;
    }

    NSUInteger maxPixel = [[self class] maxScreenPixelEdge];
    NSString *sourceName = fileURL.lastPathComponent ?: @"wallpaper.jpg";
    dispatch_async(self.importQueue, ^{
        NSError *error = nil;
        BOOL ok = [self writeDisplayImageFromURL:fileURL maxPixelSize:maxPixel error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                if (completion) {
                    completion(error ?: [NSError errorWithDomain:kWallpaperErrorDomain
                                                            code:2
                                                        userInfo:@{NSLocalizedDescriptionKey: @"无法导入图片"}]);
                }
                return;
            }
            self.sourceFileName = sourceName;
            self.enabledFlag = YES;
            [self persistMetaWithMaxPixelSize:maxPixel];
            [self reloadDisplayImageKeepingAcquire];
            [self postChangeReason:@"import"];
            if (completion) {
                completion(nil);
            }
        });
    });
}

#pragma mark - ImageIO

- (BOOL)writeDisplayImageFromURL:(NSURL *)fileURL
                    maxPixelSize:(NSUInteger)maxPixelSize
                           error:(NSError **)error {
    if (![[self class] ensureDirectoryExists:error]) {
        return NO;
    }

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (source == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:kWallpaperErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法读取图片文件"}];
        }
        return NO;
    }

    NSDictionary *options = @{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge id)kCGImageSourceShouldCacheImmediately: @NO,
    };
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (thumb == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:kWallpaperErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"图片解码失败"}];
        }
        return NO;
    }

    NSURL *outURL = [[self class] displayFileURL];
    // 覆盖写入前移除旧文件，避免部分失败留下坏文件。
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)outURL,
                                                                 (__bridge CFStringRef)@"public.jpeg",
                                                                 1,
                                                                 NULL);
    if (dest == NULL) {
        CGImageRelease(thumb);
        if (error) {
            *error = [NSError errorWithDomain:kWallpaperErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写入显示用图片"}];
        }
        return NO;
    }

    NSDictionary *destProps = @{
        (__bridge id)kCGImageDestinationLossyCompressionQuality: @(kJPEGQuality),
    };
    CGImageDestinationAddImage(dest, thumb, (__bridge CFDictionaryRef)destProps);
    BOOL finalized = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(thumb);

    if (!finalized) {
        if (error) {
            *error = [NSError errorWithDomain:kWallpaperErrorDomain
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"写入显示用图片失败"}];
        }
        return NO;
    }
    return YES;
}

@end
