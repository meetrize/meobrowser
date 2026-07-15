#import "BrowserDownloadManager.h"
#import "BrowserDownloadItem.h"
#import "BrowserSSLExceptionStore.h"
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

NSNotificationName const BrowserDownloadManagerDidChangeNotification = @"BrowserDownloadManagerDidChangeNotification";

static const NSUInteger kMaxKeptItems = 50;

static NSString *HostFromURL(NSURL *url);
static NSString *SanitizedFilename(NSString *raw);
static NSURL *UniqueDestinationURLInDownloads(NSString *filename);
static NSString *ExtensionForMIMEType(NSString *mime);

@interface BrowserDownloadManager ()
@property (nonatomic, strong) NSMutableArray<BrowserDownloadItem *> *mutableItems;
@property (nonatomic, strong) NSHashTable<id<BrowserDownloadManagerObserver>> *observers;
@property (nonatomic, strong) NSMapTable<WKDownload *, BrowserDownloadItem *> *itemByDownload;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSString *> *progressObservationKeys;
@end

@interface BrowserDownloadManager (Private)
- (void)saveDataURL:(NSURL *)url;
@end

@implementation BrowserDownloadManager

+ (instancetype)sharedManager {
    static BrowserDownloadManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserDownloadManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableItems = [[NSMutableArray alloc] init];
        _observers = [NSHashTable weakObjectsHashTable];
        _itemByDownload = [NSMapTable weakToStrongObjectsMapTable];
        _progressObservationKeys = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    for (BrowserDownloadItem *item in self.mutableItems) {
        [self stopObservingProgressForItem:item];
    }
}

#pragma mark - Public

- (NSArray<BrowserDownloadItem *> *)items {
    return [self.mutableItems copy];
}

- (NSUInteger)activeCount {
    NSUInteger count = 0;
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.state == BrowserDownloadStatePending || item.state == BrowserDownloadStateDownloading) {
            count += 1;
        }
    }
    return count;
}

- (BOOL)hasActiveDownloads {
    return self.activeCount > 0;
}

- (NSUInteger)unreadCompletedCount {
    NSUInteger count = 0;
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.state == BrowserDownloadStateCompleted && item.unread) {
            count += 1;
        }
    }
    return count;
}

- (double)aggregateProgress {
    double sum = 0;
    NSUInteger n = 0;
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.state != BrowserDownloadStatePending && item.state != BrowserDownloadStateDownloading) {
            continue;
        }
        sum += MAX(0.0, MIN(1.0, item.progress));
        n += 1;
    }
    if (n == 0) {
        return 0;
    }
    return sum / (double)n;
}

- (void)addObserver:(id<BrowserDownloadManagerObserver>)observer {
    if (observer) {
        [self.observers addObject:observer];
    }
}

- (void)removeObserver:(id<BrowserDownloadManagerObserver>)observer {
    if (observer) {
        [self.observers removeObject:observer];
    }
}

- (void)takeOwnershipOfDownload:(WKDownload *)download {
    if (!download) {
        return;
    }
    if ([self.itemByDownload objectForKey:download]) {
        return;
    }

    BrowserDownloadItem *item = [[BrowserDownloadItem alloc] init];
    item.download = download;
    item.state = BrowserDownloadStatePending;
    item.sourceURL = download.originalRequest.URL;
    item.sourceHost = HostFromURL(download.originalRequest.URL);
    if (download.originalRequest.URL.lastPathComponent.length > 0) {
        item.filename = download.originalRequest.URL.lastPathComponent;
    }

    download.delegate = self;
    [self.itemByDownload setObject:item forKey:download];
    [self.mutableItems insertObject:item atIndex:0];
    [self trimOldFinishedItems];
    [self notifyChange];
}

- (void)startDownloadWithURL:(NSURL *)url fromWebView:(WKWebView *)webView {
    if (!url) {
        return;
    }
    if ([url.scheme.lowercaseString isEqualToString:@"data"]) {
        [self saveDataURL:url];
        return;
    }
    if (!webView) {
        return;
    }
    if (@available(macOS 11.3, *)) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        __weak typeof(self) weakSelf = self;
        [webView startDownloadUsingRequest:request completionHandler:^(WKDownload *download) {
            [weakSelf takeOwnershipOfDownload:download];
        }];
    }
}

- (void)saveDataURL:(NSURL *)url {
    if (!url) {
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *resource = components.path ?: url.resourceSpecifier;
    if (resource.length == 0) {
        return;
    }

    NSRange comma = [resource rangeOfString:@","];
    if (comma.location == NSNotFound) {
        return;
    }

    NSString *meta = [resource substringToIndex:comma.location];
    NSString *payload = [resource substringFromIndex:NSMaxRange(comma)];
    BOOL isBase64 = [[meta lowercaseString] containsString:@";base64"];
    NSData *data = nil;
    if (isBase64) {
        data = [[NSData alloc] initWithBase64EncodedString:payload options:NSDataBase64DecodingIgnoreUnknownCharacters];
    } else {
        NSString *decoded = [payload stringByRemovingPercentEncoding] ?: payload;
        data = [decoded dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (data.length == 0) {
        return;
    }

    NSString *mime = @"application/octet-stream";
    NSArray<NSString *> *metaParts = [meta componentsSeparatedByString:@";"];
    if (metaParts.firstObject.length > 0) {
        mime = metaParts.firstObject;
    }

    NSString *ext = ExtensionForMIMEType(mime);
    NSString *filename = SanitizedFilename([NSString stringWithFormat:@"image.%@", ext]);
    NSURL *destination = UniqueDestinationURLInDownloads(filename);
    if (!destination) {
        return;
    }

    NSError *writeError = nil;
    if (![data writeToURL:destination options:NSDataWritingAtomic error:&writeError]) {
        return;
    }

    BrowserDownloadItem *item = [[BrowserDownloadItem alloc] init];
    item.sourceURL = url;
    item.sourceHost = @"data";
    item.filename = destination.lastPathComponent;
    item.destinationURL = destination;
    item.state = BrowserDownloadStateCompleted;
    item.progress = 1.0;
    item.hasKnownTotalUnitCount = YES;
    item.completedUnitCount = (int64_t)data.length;
    item.totalUnitCount = (int64_t)data.length;
    item.createdAt = [NSDate date];
    item.finishedAt = item.createdAt;
    item.unread = YES;
    [self.mutableItems insertObject:item atIndex:0];
    [self trimOldFinishedItems];
    [self notifyChange];
}

- (void)cancelItem:(BrowserDownloadItem *)item {
    if (!item) {
        return;
    }
    if (item.state != BrowserDownloadStatePending && item.state != BrowserDownloadStateDownloading) {
        return;
    }
    WKDownload *download = item.download;
    if (download) {
        __weak typeof(self) weakSelf = self;
        [download cancel:^(NSData *resumeData) {
            (void)resumeData;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf markItemAsCancelled:item];
            });
        }];
    } else {
        [self markItemAsCancelled:item];
    }
}

- (void)revealItemInFinder:(BrowserDownloadItem *)item {
    if (!item.destinationURL) {
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[item.destinationURL]];
}

- (void)openItem:(BrowserDownloadItem *)item {
    if (!item.destinationURL) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:item.destinationURL];
}

- (void)removeItem:(BrowserDownloadItem *)item {
    if (!item) {
        return;
    }
    [self stopObservingProgressForItem:item];
    if (item.download) {
        [self.itemByDownload removeObjectForKey:item.download];
        item.download.delegate = nil;
        item.download = nil;
    }
    [self.mutableItems removeObject:item];
    [self notifyChange];
}

- (void)clearFinishedItems {
    NSMutableArray<BrowserDownloadItem *> *toRemove = [[NSMutableArray alloc] init];
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.state == BrowserDownloadStateCompleted ||
            item.state == BrowserDownloadStateFailed ||
            item.state == BrowserDownloadStateCancelled) {
            [toRemove addObject:item];
        }
    }
    for (BrowserDownloadItem *item in toRemove) {
        [self stopObservingProgressForItem:item];
        if (item.download) {
            [self.itemByDownload removeObjectForKey:item.download];
            item.download.delegate = nil;
            item.download = nil;
        }
        [self.mutableItems removeObject:item];
    }
    [self notifyChange];
}

- (void)markAllCompletedAsRead {
    BOOL changed = NO;
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.unread) {
            item.unread = NO;
            changed = YES;
        }
    }
    if (changed) {
        [self notifyChange];
    }
}

+ (BOOL)shouldDownloadNavigationResponse:(WKNavigationResponse *)navigationResponse {
    if (!navigationResponse) {
        return NO;
    }
    if (!navigationResponse.canShowMIMEType) {
        return YES;
    }
    NSURLResponse *response = navigationResponse.response;
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    id dispositionValue = http.allHeaderFields[@"Content-Disposition"];
    if (![dispositionValue isKindOfClass:[NSString class]]) {
        dispositionValue = http.allHeaderFields[@"content-disposition"];
    }
    if (![dispositionValue isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *disposition = [(NSString *)dispositionValue lowercaseString];
    return [disposition containsString:@"attachment"];
}

#pragma mark - WKDownloadDelegate

- (void)download:(WKDownload *)download
decideDestinationUsingResponse:(NSURLResponse *)response
        suggestedFilename:(NSString *)suggestedFilename
        completionHandler:(void (^)(NSURL * _Nullable))completionHandler {
    BrowserDownloadItem *item = [self.itemByDownload objectForKey:download];
    if (!item) {
        item = [[BrowserDownloadItem alloc] init];
        item.download = download;
        [self.itemByDownload setObject:item forKey:download];
        [self.mutableItems insertObject:item atIndex:0];
    }

    NSString *name = SanitizedFilename(suggestedFilename.length > 0
                                       ? suggestedFilename
                                       : (response.suggestedFilename.length > 0
                                          ? response.suggestedFilename
                                          : @"download"));
    item.filename = name;
    if (!item.sourceURL) {
        item.sourceURL = response.URL ?: download.originalRequest.URL;
        item.sourceHost = HostFromURL(item.sourceURL);
    }

    NSURL *destination = UniqueDestinationURLInDownloads(name);
    if (!destination) {
        item.state = BrowserDownloadStateFailed;
        item.errorMessage = @"无法写入下载文件夹";
        item.finishedAt = [NSDate date];
        completionHandler(nil);
        [self notifyChange];
        return;
    }

    item.destinationURL = destination;
    item.state = BrowserDownloadStateDownloading;
    [self startObservingProgressForItem:item download:download];
    completionHandler(destination);
    [self notifyChange];
}

- (void)downloadDidFinish:(WKDownload *)download {
    BrowserDownloadItem *item = [self.itemByDownload objectForKey:download];
    if (!item) {
        return;
    }
    [self stopObservingProgressForItem:item];
    item.state = BrowserDownloadStateCompleted;
    item.progress = 1.0;
    item.finishedAt = [NSDate date];
    item.unread = YES;
    item.download = nil;
    [self.itemByDownload removeObjectForKey:download];
    [self notifyChange];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    (void)resumeData;
    BrowserDownloadItem *item = [self.itemByDownload objectForKey:download];
    if (!item) {
        return;
    }
    [self stopObservingProgressForItem:item];
    if (error.code == NSURLErrorCancelled) {
        item.state = BrowserDownloadStateCancelled;
        item.errorMessage = nil;
    } else {
        item.state = BrowserDownloadStateFailed;
        item.errorMessage = error.localizedDescription ?: @"下载失败";
    }
    item.finishedAt = [NSDate date];
    item.download = nil;
    [self.itemByDownload removeObjectForKey:download];
    [self notifyChange];
}

- (void)download:(WKDownload *)download
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    (void)download;
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if (![method isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    NSString *host = challenge.protectionSpace.host ?: @"";
    NSString *hostKey = [BrowserSSLExceptionStore hostKeyForHost:host port:challenge.protectionSpace.port];
    if (trust && [[BrowserSSLExceptionStore sharedStore] allowsHostKey:hostKey]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        return;
    }

    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

#pragma mark - Progress KVO

- (void)startObservingProgressForItem:(BrowserDownloadItem *)item download:(WKDownload *)download {
    [self stopObservingProgressForItem:item];
    NSProgress *progress = download.progress;
    if (!progress) {
        return;
    }
    NSString *keyPath = @"fractionCompleted";
    [progress addObserver:self
               forKeyPath:keyPath
                  options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                  context:(__bridge void *)item.itemID];
    self.progressObservationKeys[item.itemID] = keyPath;
}

- (void)stopObservingProgressForItem:(BrowserDownloadItem *)item {
    if (!item) {
        return;
    }
    NSString *keyPath = self.progressObservationKeys[item.itemID];
    if (!keyPath) {
        return;
    }
    WKDownload *download = item.download;
    NSProgress *progress = download.progress;
    if (progress) {
        @try {
            [progress removeObserver:self forKeyPath:keyPath context:(__bridge void *)item.itemID];
        } @catch (__unused NSException *exception) {
        }
    }
    [self.progressObservationKeys removeObjectForKey:item.itemID];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (![keyPath isEqualToString:@"fractionCompleted"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NSUUID *itemID = (__bridge NSUUID *)context;
    BrowserDownloadItem *item = nil;
    for (BrowserDownloadItem *candidate in self.mutableItems) {
        if ([candidate.itemID isEqual:itemID]) {
            item = candidate;
            break;
        }
    }
    if (!item || ![object isKindOfClass:[NSProgress class]]) {
        return;
    }
    NSProgress *progress = (NSProgress *)object;
    double fraction = progress.fractionCompleted;
    int64_t completed = progress.completedUnitCount;
    int64_t total = progress.totalUnitCount;
    BOOL knownTotal = (progress.totalUnitCount > 0);
    NSUUID *capturedID = item.itemID;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BrowserDownloadManager *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BrowserDownloadItem *liveItem = nil;
        for (BrowserDownloadItem *candidate in strongSelf.mutableItems) {
            if ([candidate.itemID isEqual:capturedID]) {
                liveItem = candidate;
                break;
            }
        }
        if (!liveItem) {
            return;
        }
        liveItem.progress = fraction;
        liveItem.completedUnitCount = completed;
        liveItem.totalUnitCount = total;
        liveItem.hasKnownTotalUnitCount = knownTotal;
        if (liveItem.state == BrowserDownloadStatePending) {
            liveItem.state = BrowserDownloadStateDownloading;
        }
        [strongSelf notifyChange];
    });
}

#pragma mark - Internals

- (void)markItemAsCancelled:(BrowserDownloadItem *)item {
    [self stopObservingProgressForItem:item];
    item.state = BrowserDownloadStateCancelled;
    item.finishedAt = [NSDate date];
    if (item.download) {
        [self.itemByDownload removeObjectForKey:item.download];
        item.download.delegate = nil;
        item.download = nil;
    }
    [self notifyChange];
}

- (void)trimOldFinishedItems {
    while (self.mutableItems.count > kMaxKeptItems) {
        BrowserDownloadItem *last = self.mutableItems.lastObject;
        if (last.state == BrowserDownloadStatePending || last.state == BrowserDownloadStateDownloading) {
            break;
        }
        [self removeItem:last];
    }
}

- (void)notifyChange {
    for (id<BrowserDownloadManagerObserver> observer in self.observers.allObjects) {
        [observer downloadManagerDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserDownloadManagerDidChangeNotification
                                                        object:self];
}

static NSString *HostFromURL(NSURL *url) {
    if (!url) {
        return nil;
    }
    NSString *host = url.host;
    if (host.length == 0) {
        return url.absoluteString;
    }
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return host;
}

static NSString *ExtensionForMIMEType(NSString *mime) {
    NSString *lower = mime.lowercaseString ?: @"";
    if ([lower isEqualToString:@"image/png"]) {
        return @"png";
    }
    if ([lower isEqualToString:@"image/jpeg"] || [lower isEqualToString:@"image/jpg"]) {
        return @"jpg";
    }
    if ([lower isEqualToString:@"image/gif"]) {
        return @"gif";
    }
    if ([lower isEqualToString:@"image/webp"]) {
        return @"webp";
    }
    if ([lower isEqualToString:@"image/svg+xml"]) {
        return @"svg";
    }
    if ([lower isEqualToString:@"image/bmp"]) {
        return @"bmp";
    }
    if ([lower isEqualToString:@"image/x-icon"] || [lower isEqualToString:@"image/vnd.microsoft.icon"]) {
        return @"ico";
    }
    if ([lower hasPrefix:@"image/"]) {
        NSString *subtype = [lower substringFromIndex:@"image/".length];
        if (subtype.length > 0 && ![subtype containsString:@"+"]) {
            return subtype;
        }
    }
    return @"bin";
}

static NSString *SanitizedFilename(NSString *raw) {
    if (raw.length == 0) {
        return @"download";
    }
    NSString *name = [raw lastPathComponent];
    if (name.length == 0) {
        name = @"download";
    }
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?\n\r\t"];
    NSArray<NSString *> *parts = [name componentsSeparatedByCharactersInSet:illegal];
    name = [parts componentsJoinedByString:@"_"];
    if (name.length == 0 || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        return @"download";
    }
    return name;
}

static NSURL *UniqueDestinationURLInDownloads(NSString *filename) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    NSURL *downloads = [fm URLForDirectory:NSDownloadsDirectory
                                  inDomain:NSUserDomainMask
                         appropriateForURL:nil
                                    create:YES
                                     error:&error];
    if (!downloads) {
        return nil;
    }

    NSString *baseName = [filename stringByDeletingPathExtension];
    NSString *extension = filename.pathExtension;
    NSURL *candidate = [downloads URLByAppendingPathComponent:filename isDirectory:NO];
    NSInteger suffix = 1;
    while ([fm fileExistsAtPath:candidate.path]) {
        NSString *nextName = extension.length > 0
            ? [NSString stringWithFormat:@"%@-%ld.%@", baseName, (long)suffix, extension]
            : [NSString stringWithFormat:@"%@-%ld", baseName, (long)suffix];
        candidate = [downloads URLByAppendingPathComponent:nextName isDirectory:NO];
        suffix += 1;
        if (suffix > 10000) {
            return nil;
        }
    }
    return candidate;
}

@end
