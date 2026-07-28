#import "BrowserTabThumbnailCache.h"
#import "CaptchaCaptureService.h"

static const NSUInteger kMaxCachedThumbnails = 20;
static const CGFloat kMaxThumbnailLongEdge = 480.0;

@interface BrowserTabThumbnailCache ()
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSImage *> *imagesByTabID;
@property (nonatomic, strong) NSMutableArray<NSUUID *> *lruOrder;
@end

@implementation BrowserTabThumbnailCache

+ (instancetype)sharedCache {
    static BrowserTabThumbnailCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[BrowserTabThumbnailCache alloc] init];
    });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _imagesByTabID = [NSMutableDictionary dictionary];
        _lruOrder = [NSMutableArray array];
    }
    return self;
}

- (nullable NSImage *)imageForTabID:(NSUUID *)tabID {
    if (!tabID) {
        return nil;
    }
    NSImage *image = self.imagesByTabID[tabID];
    if (image) {
        [self.lruOrder removeObject:tabID];
        [self.lruOrder addObject:tabID];
    }
    return image;
}

- (void)setImage:(NSImage *)image forTabID:(NSUUID *)tabID {
    if (!image || !tabID) {
        return;
    }
    NSImage *scaled = [self scaledImage:image];
    self.imagesByTabID[tabID] = scaled;
    [self.lruOrder removeObject:tabID];
    [self.lruOrder addObject:tabID];
    while (self.lruOrder.count > kMaxCachedThumbnails) {
        NSUUID *evict = self.lruOrder.firstObject;
        if (!evict) {
            break;
        }
        [self.lruOrder removeObjectAtIndex:0];
        [self.imagesByTabID removeObjectForKey:evict];
    }
}

- (void)removeImageForTabID:(NSUUID *)tabID {
    if (!tabID) {
        return;
    }
    [self.imagesByTabID removeObjectForKey:tabID];
    [self.lruOrder removeObject:tabID];
}

- (void)removeAll {
    [self.imagesByTabID removeAllObjects];
    [self.lruOrder removeAllObjects];
}

- (NSImage *)scaledImage:(NSImage *)image {
    NSSize size = image.size;
    if (size.width <= 0 || size.height <= 0) {
        return image;
    }
    CGFloat longEdge = MAX(size.width, size.height);
    if (longEdge <= kMaxThumbnailLongEdge) {
        return image;
    }
    CGFloat scale = kMaxThumbnailLongEdge / longEdge;
    NSSize target = NSMakeSize(floor(size.width * scale), floor(size.height * scale));
    NSImage *out = [[NSImage alloc] initWithSize:target];
    [out lockFocus];
    [image drawInRect:NSMakeRect(0, 0, target.width, target.height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0
       respectFlipped:YES
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationMedium)}];
    [out unlockFocus];
    return out;
}

- (void)captureFromWebView:(WKWebView *)webView
                   forTabID:(NSUUID *)tabID
                 completion:(void (^)(NSImage *image))completion {
    if (!webView || !tabID) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    __weak typeof(self) weakSelf = self;
    [CaptchaCaptureService captureVisibleInWebView:webView completion:^(NSImage *image, NSError *error) {
        (void)error;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) {
            if (completion) {
                completion(nil);
            }
            return;
        }
        [strongSelf setImage:image forTabID:tabID];
        if (completion) {
            completion([strongSelf imageForTabID:tabID]);
        }
    }];
}

@end
