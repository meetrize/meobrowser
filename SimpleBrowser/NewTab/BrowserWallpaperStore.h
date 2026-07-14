#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const BrowserWallpaperDidChangeNotification;
/// userInfo[@"reason"]：import | clear | enabled | scrim | reload
extern NSString * const BrowserWallpaperChangeReasonKey;

@interface BrowserWallpaperStore : NSObject

+ (instancetype)sharedStore;

/// 已启用且磁盘上存在 display 文件。
@property (nonatomic, assign, readonly, getter=isWallpaperEnabled) BOOL wallpaperEnabled;
/// UserDefaults / meta 中的开关（无文件时亦可为 YES，但 isWallpaperEnabled 为 NO）。
@property (nonatomic, assign, readonly, getter=isEnabledFlag) BOOL enabledFlag;
@property (nonatomic, assign, readonly) BOOL hasDisplayFile;
@property (nonatomic, assign, readonly) CGFloat scrimAlpha;
@property (nonatomic, copy, readonly, nullable) NSString *sourceFileName;
@property (nonatomic, strong, readonly, nullable) NSImage *displayImage;

- (void)acquireDisplayImage;
- (void)releaseDisplayImage;

- (void)importImageFromURL:(NSURL *)fileURL
                completion:(void (^)(NSError * _Nullable error))completion;
- (void)setWallpaperEnabled:(BOOL)enabled;
- (void)setScrimAlpha:(CGFloat)alpha;
- (void)clearWallpaper;

+ (NSURL *)wallpaperDirectoryURL;
+ (NSUInteger)maxScreenPixelEdge;

@end

NS_ASSUME_NONNULL_END
