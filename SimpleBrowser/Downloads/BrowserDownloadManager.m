#import "BrowserDownloadManager.h"
#import "BrowserDownloadItem.h"
#import "BrowserSSLExceptionStore.h"
#import "BrowserFeedReader.h"
#import "BrowserRiskHostPolicy.h"
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

NSNotificationName const BrowserDownloadManagerDidChangeNotification = @"BrowserDownloadManagerDidChangeNotification";

static const NSUInteger kMaxKeptItems = 50;

static NSString *HostFromURL(NSURL *url);
static NSString *SanitizedFilename(NSString *raw);
static NSURL *UniqueDestinationURLInDownloads(NSString *filename);
static NSString *ExtensionForMIMEType(NSString *mime);
static NSString *DefaultFilenameForMIMEType(NSString *mime);
static NSString *JSONStringLiteral(NSString *string);
static NSString *MIMETypeBySniffingData(NSData *data);

/// blob: 分块拉取时每段二进制大小（Base64 约再 ×4/3）。
static const NSUInteger kBlobDownloadChunkBytes = 256 * 1024;

static NSArray<NSString *> *ProgressKVOKeyPaths(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // fractionCompleted alone does not fire when total size is unknown (chunked / no Content-Length).
        keys = @[ @"fractionCompleted", @"completedUnitCount", @"totalUnitCount" ];
    });
    return keys;
}

@interface BrowserDownloadManager ()
@property (nonatomic, strong) NSMutableArray<BrowserDownloadItem *> *mutableItems;
@property (nonatomic, strong) NSHashTable<id<BrowserDownloadManagerObserver>> *observers;
@property (nonatomic, strong) NSMapTable<WKDownload *, BrowserDownloadItem *> *itemByDownload;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *observedProgressItemIDs;
@property (nonatomic, assign) BOOL progressNotifyCoalesceScheduled;
@end

@interface BrowserDownloadManager (Private)
- (void)saveDataURL:(NSURL *)url;
- (void)saveBlobURL:(NSURL *)url fromWebView:(WKWebView *)webView;
- (void)failBlobDownloadItem:(BrowserDownloadItem *)item message:(NSString *)message;
- (void)finishBlobDownloadItem:(BrowserDownloadItem *)item
                      withData:(NSData *)data
                          mime:(NSString *)mime
                     sourceURL:(NSURL *)sourceURL;
- (void)fetchBlobChunkForItem:(BrowserDownloadItem *)item
                    sessionID:(NSString *)sessionID
                      webView:(WKWebView *)webView
                       buffer:(NSMutableData *)buffer
                       offset:(NSUInteger)offset
                    totalSize:(NSUInteger)totalSize
                         mime:(NSString *)mime
                    sourceURL:(NSURL *)sourceURL;
- (void)continueBlobBytesDownloadForItem:(BrowserDownloadItem *)item
                               sessionID:(NSString *)sessionID
                                 webView:(WKWebView *)webView
                              sourceURL:(NSURL *)sourceURL
                                   mime:(NSString *)mime
                                   size:(NSUInteger)totalSize;
@end

static BOOL DataLooksLikeTextError(NSData *data);
static void CleanupBlobDownloadSession(WKWebView *webView, NSString *sessionID);

@implementation BrowserDownloadManager

+ (instancetype)sharedManager {
    static BrowserDownloadManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BrowserDownloadManager alloc] init];
    });
    return shared;
}

+ (void)installMediaCaptureScriptOnConfiguration:(WKWebViewConfiguration *)configuration {
    if (!configuration) {
        return;
    }
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self mediaCaptureUserScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:NO];
    [ucc addUserScript:script];
}

/// 尽早挂钩：保留 Blob 引用（避免 revoke 后 fetch 失败），并嗅探豆包 get_play_info 的 main_url。
/// Cloudflare Turnstile 会对「改写 fetch/XHR」极敏感：人机页整段静默；fetch/XHR 仅在媒体站启用。
+ (NSString *)mediaCaptureUserScriptSource {
    NSString *suppressFn = [BrowserRiskHostPolicy javaScriptShouldSuppressPageAutomationFunctionNamed:@"meoShouldSkipMediaCapture"];
    NSString *body = @
    "  if (window.__meoMediaCaptureInstalled) { return; }\n"
    "  if (meoShouldSkipMediaCapture()) { return; }\n"
    "\n"
    "  function hostNeedsPlayInfoHook() {\n"
    "    try {\n"
    "      var h = (location.hostname || '').toLowerCase();\n"
    "      var needles = ['doubao.com', 'jianying.com', 'capcut.com', 'bytedance.com', 'byteintl.com', 'tiktok.com', 'ixigua.com'];\n"
    "      for (var i = 0; i < needles.length; i++) {\n"
    "        var n = needles[i];\n"
    "        if (h === n || h.endsWith('.' + n)) return true;\n"
    "      }\n"
    "    } catch (e) {}\n"
    "    return false;\n"
    "  }\n"
    "  // 非媒体站完全不挂钩（含 createObjectURL）：linux.do 等 CF 主站 interstitial 也保持原生环境。\n"
    "  if (!hostNeedsPlayInfoHook()) { return; }\n"
    "\n"
    "  window.__meoMediaCaptureInstalled = true;\n"
    "  window.__meoMediaBlobByURL = Object.create(null);\n"
    "  window.__meoMediaHTTPS = [];\n"
    "  window.__meoPlayInfoVids = [];\n"
    "\n"
    "  function pushHTTPS(url) {\n"
    "    if (!url || typeof url !== 'string' || !/^https?:/i.test(url)) { return; }\n"
    "    try { url = url.replace(/\\\\u002F/g, '/'); } catch (e) {}\n"
    "    if (/\\.m3u8(\\?|$)/i.test(url)) { return; }\n"
    "    var list = window.__meoMediaHTTPS;\n"
    "    for (var i = 0; i < list.length; i++) {\n"
    "      if (list[i].url === url) { list[i].ts = Date.now(); return; }\n"
    "    }\n"
    "    list.push({ url: url, ts: Date.now() });\n"
    "    if (list.length > 40) { list.splice(0, list.length - 40); }\n"
    "  }\n"
    "\n"
    "  function rememberVid(vid) {\n"
    "    if (!vid || typeof vid !== 'string') { return; }\n"
    "    if (window.__meoPlayInfoVids.indexOf(vid) >= 0) { return; }\n"
    "    window.__meoPlayInfoVids.push(vid);\n"
    "    if (window.__meoPlayInfoVids.length > 30) { window.__meoPlayInfoVids.shift(); }\n"
    "  }\n"
    "\n"
    "  function harvestJSON(obj, depth) {\n"
    "    if (!obj || depth > 6) { return; }\n"
    "    if (typeof obj === 'string') {\n"
    "      if (/^https?:/i.test(obj) && /(mp4|webm|mov|video|media|tos-|byte)/i.test(obj)) {\n"
    "        pushHTTPS(obj);\n"
    "      }\n"
    "      return;\n"
    "    }\n"
    "    if (Array.isArray(obj)) {\n"
    "      for (var i = 0; i < obj.length; i++) { harvestJSON(obj[i], depth + 1); }\n"
    "      return;\n"
    "    }\n"
    "    if (typeof obj !== 'object') { return; }\n"
    "    if (typeof obj.main_url === 'string') { pushHTTPS(obj.main_url); }\n"
    "    if (typeof obj.backup_url === 'string') { pushHTTPS(obj.backup_url); }\n"
    "    if (obj.original_media_info) { harvestJSON(obj.original_media_info, depth + 1); }\n"
    "    if (obj.data) { harvestJSON(obj.data, depth + 1); }\n"
    "    var keys = ['url', 'video_url', 'play_url', 'download_url', 'src'];\n"
    "    for (var k = 0; k < keys.length; k++) {\n"
    "      var v = obj[keys[k]];\n"
    "      if (typeof v === 'string' && /^https?:/i.test(v)) { pushHTTPS(v); }\n"
    "    }\n"
    "    if (typeof obj.vid === 'string') { rememberVid(obj.vid); }\n"
    "    if (typeof obj.video_id === 'string') { rememberVid(obj.video_id); }\n"
    "    if (typeof obj.key === 'string' && obj.key.length > 8) { rememberVid(obj.key); }\n"
    "  }\n"
    "\n"
    "  function harvestText(text) {\n"
    "    if (!text || typeof text !== 'string' || text.length > 5000000) { return; }\n"
    "    try {\n"
    "      if (text.charAt(0) === '{' || text.charAt(0) === '[') {\n"
    "        harvestJSON(JSON.parse(text), 0);\n"
    "        return;\n"
    "      }\n"
    "    } catch (e) {}\n"
    "    var re = /https?:\\\\/\\\\/[^\\\\s\\\"'<>]+/g;\n"
    "    var m;\n"
    "    while ((m = re.exec(text))) {\n"
    "      var u = m[0].replace(/\\\\+$/, '');\n"
    "      if (/(mp4|webm|mov|video|media|tos-|byte)/i.test(u)) { pushHTTPS(u); }\n"
    "    }\n"
    "  }\n"
    "\n"
    "  var origCreate = URL.createObjectURL;\n"
    "  URL.createObjectURL = function(obj) {\n"
    "    var url = origCreate.call(this, obj);\n"
    "    try {\n"
    "      if (obj && typeof Blob !== 'undefined' && obj instanceof Blob) {\n"
    "        window.__meoMediaBlobByURL[url] = {\n"
    "          blob: obj,\n"
    "          mime: obj.type || '',\n"
    "          size: obj.size || 0,\n"
    "          ts: Date.now()\n"
    "        };\n"
    "      }\n"
    "    } catch (e) {}\n"
    "    return url;\n"
    "  };\n"
    "\n"
    "  var origRevoke = URL.revokeObjectURL;\n"
    "  URL.revokeObjectURL = function(url) {\n"
    "    try {\n"
    "      setTimeout(function() {\n"
    "        try { delete window.__meoMediaBlobByURL[url]; } catch (e) {}\n"
    "      }, 180000);\n"
    "    } catch (e2) {}\n"
    "    return origRevoke.call(this, url);\n"
    "  };\n"
    "\n"
    "  var origFetch = window.fetch;\n"
    "  if (typeof origFetch === 'function') {\n"
    "    window.fetch = function() {\n"
    "      var args = arguments;\n"
    "      var input = args[0];\n"
    "      var reqURL = '';\n"
    "      try {\n"
    "        if (typeof input === 'string') { reqURL = input; }\n"
    "        else if (input && input.url) { reqURL = input.url; }\n"
    "      } catch (e) {}\n"
    "      try {\n"
    "        if (/get_play_info/i.test(reqURL)) {\n"
    "          var init = args[1];\n"
    "          if (init && typeof init.body === 'string') {\n"
    "            try {\n"
    "              var body = JSON.parse(init.body);\n"
    "              if (body && body.key) { rememberVid(String(body.key)); }\n"
    "            } catch (e3) {}\n"
    "          }\n"
    "        }\n"
    "      } catch (e4) {}\n"
    "      return origFetch.apply(this, args).then(function(res) {\n"
    "        try {\n"
    "          if (/get_play_info|play_info/i.test(reqURL) || /get_play_info|play_info/i.test(res.url || '')) {\n"
    "            res.clone().text().then(harvestText).catch(function() {});\n"
    "          }\n"
    "        } catch (e5) {}\n"
    "        return res;\n"
    "      });\n"
    "    };\n"
    "  }\n"
    "\n"
    "  var origOpen = XMLHttpRequest.prototype.open;\n"
    "  var origSend = XMLHttpRequest.prototype.send;\n"
    "  XMLHttpRequest.prototype.open = function(method, url) {\n"
    "    try { this.__meoURL = String(url || ''); } catch (e) { this.__meoURL = ''; }\n"
    "    return origOpen.apply(this, arguments);\n"
    "  };\n"
    "  XMLHttpRequest.prototype.send = function(body) {\n"
    "    var xhr = this;\n"
    "    try {\n"
    "      if (/get_play_info/i.test(xhr.__meoURL || '') && typeof body === 'string') {\n"
    "        try {\n"
    "          var b = JSON.parse(body);\n"
    "          if (b && b.key) { rememberVid(String(b.key)); }\n"
    "        } catch (e) {}\n"
    "      }\n"
    "    } catch (e2) {}\n"
    "    xhr.addEventListener('load', function() {\n"
    "      try {\n"
    "        if (/get_play_info|play_info/i.test(xhr.__meoURL || '')) {\n"
    "          harvestText(xhr.responseText);\n"
    "        }\n"
    "      } catch (e3) {}\n"
    "    });\n"
    "    return origSend.apply(this, arguments);\n"
    "  };\n";

    return [NSString stringWithFormat:@"(function() {\n%@%@})();", suppressFn, body];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableItems = [[NSMutableArray alloc] init];
        _observers = [NSHashTable weakObjectsHashTable];
        _itemByDownload = [NSMapTable weakToStrongObjectsMapTable];
        _observedProgressItemIDs = [[NSMutableSet alloc] init];
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
        if (!item.hasKnownTotalUnitCount || item.totalUnitCount <= 0) {
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

- (BOOL)aggregateProgressIsDeterminate {
    for (BrowserDownloadItem *item in self.mutableItems) {
        if (item.state != BrowserDownloadStatePending && item.state != BrowserDownloadStateDownloading) {
            continue;
        }
        if (item.hasKnownTotalUnitCount && item.totalUnitCount > 0) {
            return YES;
        }
    }
    return NO;
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
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"data"]) {
        [self saveDataURL:url];
        return;
    }
    // blob: 仅存在于页面内存，WKDownload / 网络请求无法读取，须在同源 WebView 内 fetch。
    if ([scheme isEqualToString:@"blob"]) {
        [self saveBlobURL:url fromWebView:webView];
        return;
    }
    if (!webView) {
        return;
    }
    if (@available(macOS 11.3, *)) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        // 媒体 CDN 常校验 Referer；沿用当前页，避免下到鉴权/错误正文。
        NSString *referer = webView.URL.absoluteString;
        if (referer.length > 0) {
            [request setValue:referer forHTTPHeaderField:@"Referer"];
            if ([webView.URL.host.lowercaseString containsString:@"doubao.com"]) {
                [request setValue:@"https://www.doubao.com" forHTTPHeaderField:@"Origin"];
            }
        }
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

- (void)saveBlobURL:(NSURL *)url fromWebView:(WKWebView *)webView {
    if (!url || !webView) {
        return;
    }

    BrowserDownloadItem *item = [[BrowserDownloadItem alloc] init];
    item.sourceURL = url;
    item.sourceHost = HostFromURL(url) ?: @"blob";
    item.filename = @"video.mp4";
    item.state = BrowserDownloadStateDownloading;
    item.progress = 0;
    item.createdAt = [NSDate date];
    item.unread = YES;
    [self.mutableItems insertObject:item atIndex:0];
    [self trimOldFinishedItems];
    [self notifyChange];

    NSString *sessionID = item.itemID.UUIDString ?: [[NSUUID UUID] UUIDString];
    // callAsyncJavaScript 才能正确等待 Promise；evaluateJavaScript 回传 Promise 会报
    // "JavaScript execution returned a result of an unsupported type"。
    NSString *functionBody =
        @"const preferred = preferredArg;"
         "const sessionId = sessionIdArg;"
         "function looksLikeMedia(u8, mime) {"
         "  if (mime && /^(video|audio|image)\\//i.test(mime)) { return true; }"
         "  if (!u8 || u8.length < 12) { return false; }"
         "  if (u8[4]===0x66 && u8[5]===0x74 && u8[6]===0x79 && u8[7]===0x70) { return true; }"
         "  if (u8[0]===0x1A && u8[1]===0x45 && u8[2]===0xDF && u8[3]===0xA3) { return true; }"
         "  if (u8[0]===0x52 && u8[1]===0x49 && u8[2]===0x46 && u8[3]===0x46) { return true; }"
         "  return false;"
         "}"
         "function asTextPreview(u8) {"
         "  var n = Math.min(u8.length, 160), s = '';"
         "  for (var i = 0; i < n; i++) {"
         "    var c = u8[i];"
         "    s += (c === 9 || c === 10 || c === 13 || (c >= 32 && c < 127)) ? String.fromCharCode(c) : ' ';"
         "  }"
         "  return s.replace(/\\s+/g, ' ').trim();"
         "}"
         "function looksLikeTextError(u8) {"
         "  if (!u8 || u8.length === 0) { return true; }"
         "  if (u8.length > 8192) { return false; }"
         "  var printable = 0;"
         "  for (var i = 0; i < u8.length; i++) {"
         "    var c = u8[i];"
         "    if (c === 9 || c === 10 || c === 13 || (c >= 32 && c < 127)) { printable++; }"
         "  }"
         "  if (printable / u8.length < 0.9) { return false; }"
         "  var t = asTextPreview(u8);"
         "  return /unsupported|not support|error|fail|denied|DOCTYPE|html/i.test(t) || u8.length < 2048;"
         "}"
         "function storeBytes(bytes, mime, url) {"
         "  if (!window.__meoBlobDownloads) { window.__meoBlobDownloads = {}; }"
         "  window.__meoBlobDownloads[sessionId] = { bytes: bytes, mime: mime || 'application/octet-stream' };"
         "  return { ok: true, mode: 'bytes', size: bytes.length, mime: mime || 'application/octet-stream', url: url || preferred };"
         "}"
         "async function readBlob(blob, url) {"
         "  const buf = await blob.arrayBuffer();"
         "  const bytes = new Uint8Array(buf);"
         "  const mime = blob.type || '';"
         "  if (looksLikeTextError(bytes) && !looksLikeMedia(bytes, mime)) {"
         "    throw new Error(asTextPreview(bytes) || 'blob 不是视频');"
         "  }"
         "  if (!looksLikeMedia(bytes, mime) && bytes.length < 4096) {"
         "    throw new Error('内容过小，不像视频');"
         "  }"
         "  return storeBytes(bytes, mime || 'video/mp4', url);"
         "}"
         "function bestCachedHTTPS() {"
         "  const list = (window.__meoMediaHTTPS || []).slice().sort((a, b) => (b.ts || 0) - (a.ts || 0));"
         "  for (const item of list) {"
         "    const u = item.url;"
         "    if (/^https?:/i.test(u) && !/\\.m3u8(\\?|$)/i.test(u)) { return u; }"
         "  }"
         "  return null;"
         "}"
         "function bestCachedBlobEntry() {"
         "  const map = window.__meoMediaBlobByURL || {};"
         "  const preferredEntry = map[preferred];"
         "  if (preferredEntry && preferredEntry.blob && preferredEntry.size > 4096 && !/^text\\//i.test(preferredEntry.mime || '')) {"
         "    return { url: preferred, entry: preferredEntry };"
         "  }"
         "  let best = null, bestURL = null;"
         "  for (const u of Object.keys(map)) {"
         "    const e = map[u];"
         "    if (!e || !e.blob || !(e.size > 4096) || /^text\\//i.test(e.mime || '')) { continue; }"
         "    if (!best || e.size > best.size) { best = e; bestURL = u; }"
         "  }"
         "  return best ? { url: bestURL, entry: best } : null;"
         "}"
         "function findVids() {"
         "  const set = {};"
         "  (window.__meoPlayInfoVids || []).forEach(v => { set[v] = 1; });"
         "  try {"
         "    const html = document.documentElement ? document.documentElement.innerHTML : '';"
         "    const patterns = ["
         "      /\"(?:vid|video_id)\"\\s*:\\s*\"([^\"]+)\"/g,"
         "      /&quot;(?:vid|video_id)&quot;\\s*:\\s*&quot;([^&]+)&quot;/g"
         "    ];"
         "    for (const re of patterns) {"
         "      let m;"
         "      while ((m = re.exec(html))) { if (m[1]) set[m[1]] = 1; }"
         "    }"
         "  } catch (e) {}"
         "  return Object.keys(set);"
         "}"
         "async function callGetPlayInfo(vid) {"
         "  const params = new URLSearchParams({"
         "    version_code: '20800', language: 'zh-CN', device_platform: 'web',"
         "    aid: '497858', real_aid: '497858', pkg_type: 'release_version',"
         "    samantha_web: '1', 'use-olympus-account': '1'"
         "  });"
         "  const res = await fetch('https://www.doubao.com/samantha/media/get_play_info?' + params.toString(), {"
         "    method: 'POST', credentials: 'include',"
         "    headers: { 'content-type': 'application/json', 'origin': 'https://www.doubao.com' },"
         "    body: JSON.stringify({ key: vid })"
         "  });"
         "  const json = await res.json();"
         "  let url = json && json.data && json.data.original_media_info && json.data.original_media_info.main_url;"
         "  if (!url && json && json.data) {"
         "    const d = json.data;"
         "    url = (d.original_media_info && (d.original_media_info.main_url || d.original_media_info.backup_url))"
         "      || d.main_url || d.play_url || d.url;"
         "  }"
         "  if (!url) { throw new Error('get_play_info 无 main_url'); }"
         "  if (!window.__meoMediaHTTPS) { window.__meoMediaHTTPS = []; }"
         "  window.__meoMediaHTTPS.push({ url: url, ts: Date.now() });"
         "  return url;"
         "}"
         "async function resolveViaPlayInfo() {"
         "  const vids = findVids();"
         "  for (const vid of vids.slice(0, 6)) {"
         "    try { const url = await callGetPlayInfo(vid); if (url) return url; } catch (e) {}"
         "  }"
         "  return null;"
         "}"
         "async function main() {"
         "  const https = bestCachedHTTPS();"
         "  if (https) { return { ok: true, mode: 'url', url: https, mime: 'video/mp4' }; }"
         "  const cached = bestCachedBlobEntry();"
         "  const errors = [];"
         "  if (cached) {"
         "    try { return await readBlob(cached.entry.blob, cached.url); }"
         "    catch (err) { errors.push(String(err && err.message ? err.message : err)); }"
         "  }"
         "  const playURL = await resolveViaPlayInfo();"
         "  if (playURL) { return { ok: true, mode: 'url', url: playURL, mime: 'video/mp4' }; }"
         "  if (/^blob:/i.test(preferred)) {"
         "    try {"
         "      const res = await fetch(preferred);"
         "      return await readBlob(await res.blob(), preferred);"
         "    } catch (err) {"
         "      errors.push(String(err && err.message ? err.message : err));"
         "    }"
         "  }"
         "  throw new Error(errors.filter(Boolean).join('；') || '未找到可下载的视频，请刷新豆包页面后再试');"
         "}"
         "try {"
         "  const payload = await main();"
         "  return JSON.stringify(payload || { ok: false, error: 'empty' });"
         "} catch (err) {"
         "  return JSON.stringify({ ok: false, error: String(err && err.message ? err.message : err) });"
         "}";

    NSDictionary *arguments = @{
        @"preferredArg": url.absoluteString ?: @"",
        @"sessionIdArg": sessionID ?: @"",
    };

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    void (^handleResult)(id, NSError *) = ^(id result, NSError *error) {
        BrowserDownloadManager *strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf) {
            return;
        }
        if (item.state == BrowserDownloadStateCancelled) {
            return;
        }
        if (error) {
            [strongSelf failBlobDownloadItem:item
                                     message:error.localizedDescription ?: @"无法读取页面内视频数据"];
            return;
        }
        NSString *jsonString = nil;
        if ([result isKindOfClass:[NSString class]]) {
            jsonString = (NSString *)result;
        } else if ([result isKindOfClass:[NSDictionary class]]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            jsonString = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        }
        if (jsonString.length == 0) {
            [strongSelf failBlobDownloadItem:item message:@"无法解析视频下载结果"];
            return;
        }

        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *payload = jsonData
            ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil]
            : nil;
        if (![payload isKindOfClass:[NSDictionary class]] || ![payload[@"ok"] boolValue]) {
            NSString *message = @"无法读取页面内媒体（blob）";
            id errVal = payload[@"error"];
            if ([errVal isKindOfClass:[NSString class]] && [(NSString *)errVal length] > 0) {
                message = (NSString *)errVal;
            }
            [strongSelf failBlobDownloadItem:item message:message];
            return;
        }

        NSString *mode = [payload[@"mode"] isKindOfClass:[NSString class]] ? payload[@"mode"] : @"bytes";
        if ([mode isEqualToString:@"url"]) {
            NSString *resolved = [payload[@"url"] isKindOfClass:[NSString class]] ? payload[@"url"] : nil;
            NSURL *resolvedURL = resolved.length > 0 ? [NSURL URLWithString:resolved] : nil;
            if (!resolvedURL || !strongWebView) {
                [strongSelf failBlobDownloadItem:item message:@"未找到有效的视频下载地址"];
                return;
            }
            [strongSelf.mutableItems removeObject:item];
            [strongSelf notifyChange];
            [strongSelf startDownloadWithURL:resolvedURL fromWebView:strongWebView];
            return;
        }

        NSUInteger totalSize = [payload[@"size"] unsignedIntegerValue];
        NSString *mime = [payload[@"mime"] isKindOfClass:[NSString class]]
            ? (NSString *)payload[@"mime"]
            : @"application/octet-stream";
        NSString *resolvedString = [payload[@"url"] isKindOfClass:[NSString class]] ? payload[@"url"] : nil;
        NSURL *resolvedURL = resolvedString.length > 0 ? [NSURL URLWithString:resolvedString] : url;
        if (!strongWebView) {
            [strongSelf failBlobDownloadItem:item message:@"页面已关闭，无法保存"];
            return;
        }
        [strongSelf continueBlobBytesDownloadForItem:item
                                           sessionID:sessionID
                                             webView:strongWebView
                                           sourceURL:resolvedURL ?: url
                                                mime:mime
                                                size:totalSize];
    };

    if (@available(macOS 11.0, *)) {
        [webView callAsyncJavaScript:functionBody
                           arguments:arguments
                             inFrame:nil
                      inContentWorld:[WKContentWorld pageWorld]
                   completionHandler:handleResult];
    } else {
        handleResult(nil, [NSError errorWithDomain:@"BrowserDownloadManager"
                                              code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"系统版本过低，无法保存页面内视频"}]);
    }
}

- (void)continueBlobBytesDownloadForItem:(BrowserDownloadItem *)item
                               sessionID:(NSString *)sessionID
                                 webView:(WKWebView *)webView
                               sourceURL:(NSURL *)sourceURL
                                    mime:(NSString *)mime
                                    size:(NSUInteger)totalSize {
    item.filename = SanitizedFilename(DefaultFilenameForMIMEType(mime));
    item.hasKnownTotalUnitCount = YES;
    item.totalUnitCount = (int64_t)totalSize;
    item.completedUnitCount = 0;
    item.sourceURL = sourceURL ?: item.sourceURL;
    [self notifyChange];

    if (totalSize == 0) {
        [self failBlobDownloadItem:item message:@"视频数据为空"];
        CleanupBlobDownloadSession(webView, sessionID);
        return;
    }

    NSMutableData *buffer = [NSMutableData dataWithCapacity:totalSize];
    [self fetchBlobChunkForItem:item
                      sessionID:sessionID
                        webView:webView
                         buffer:buffer
                         offset:0
                      totalSize:totalSize
                           mime:mime
                      sourceURL:sourceURL];
}

- (void)fetchBlobChunkForItem:(BrowserDownloadItem *)item
                    sessionID:(NSString *)sessionID
                      webView:(WKWebView *)webView
                       buffer:(NSMutableData *)buffer
                       offset:(NSUInteger)offset
                    totalSize:(NSUInteger)totalSize
                         mime:(NSString *)mime
                    sourceURL:(NSURL *)sourceURL {
    if (!item || !webView || !buffer) {
        return;
    }
    if (item.state == BrowserDownloadStateCancelled) {
        CleanupBlobDownloadSession(webView, sessionID);
        return;
    }

    NSUInteger length = MIN(kBlobDownloadChunkBytes, totalSize - offset);
    NSString *script = [NSString stringWithFormat:
        @"(function() {"
         "  var entry = window.__meoBlobDownloads && window.__meoBlobDownloads[%@];"
         "  if (!entry || !entry.bytes) { return null; }"
         "  var slice = entry.bytes.subarray(%lu, %lu);"
         "  var step = 0x8000;"
         "  var binary = '';"
         "  for (var i = 0; i < slice.length; i += step) {"
         "    binary += String.fromCharCode.apply(null, slice.subarray(i, Math.min(i + step, slice.length)));"
         "  }"
         "  return btoa(binary);"
         "})()",
        JSONStringLiteral(sessionID),
        (unsigned long)offset,
        (unsigned long)(offset + length)];

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWebView = webView;
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        BrowserDownloadManager *strongSelf = weakSelf;
        WKWebView *strongWebView = weakWebView;
        if (!strongSelf) {
            return;
        }
        if (item.state == BrowserDownloadStateCancelled) {
            return;
        }
        if (error || ![result isKindOfClass:[NSString class]] || [(NSString *)result length] == 0) {
            [strongSelf failBlobDownloadItem:item
                                     message:error.localizedDescription ?: @"读取媒体数据失败"];
            CleanupBlobDownloadSession(strongWebView, sessionID);
            return;
        }

        NSData *chunk = [[NSData alloc] initWithBase64EncodedString:(NSString *)result
                                                            options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (chunk.length == 0) {
            [strongSelf failBlobDownloadItem:item message:@"媒体数据解码失败"];
            CleanupBlobDownloadSession(strongWebView, sessionID);
            return;
        }
        [buffer appendData:chunk];
        item.completedUnitCount = (int64_t)buffer.length;
        item.progress = totalSize > 0
            ? MIN(1.0, (double)buffer.length / (double)totalSize)
            : 1.0;
        [strongSelf scheduleCoalescedProgressNotify];

        NSUInteger nextOffset = offset + length;
        if (nextOffset >= totalSize) {
            CleanupBlobDownloadSession(strongWebView, sessionID);
            [strongSelf finishBlobDownloadItem:item
                                      withData:buffer
                                          mime:mime
                                     sourceURL:sourceURL];
            return;
        }

        if (!strongWebView) {
            [strongSelf failBlobDownloadItem:item message:@"页面已关闭，无法保存"];
            return;
        }
        [strongSelf fetchBlobChunkForItem:item
                                sessionID:sessionID
                                  webView:strongWebView
                                   buffer:buffer
                                   offset:nextOffset
                                totalSize:totalSize
                                     mime:mime
                                sourceURL:sourceURL];
    }];
}

- (void)failBlobDownloadItem:(BrowserDownloadItem *)item message:(NSString *)message {
    if (!item) {
        return;
    }
    if (item.state == BrowserDownloadStateCancelled || item.state == BrowserDownloadStateCompleted) {
        return;
    }
    item.state = BrowserDownloadStateFailed;
    item.errorMessage = message.length > 0 ? message : @"保存失败";
    item.finishedAt = [NSDate date];
    [self notifyChange];
}

- (void)finishBlobDownloadItem:(BrowserDownloadItem *)item
                      withData:(NSData *)data
                          mime:(NSString *)mime
                     sourceURL:(NSURL *)sourceURL {
    if (!item) {
        return;
    }
    if (item.state == BrowserDownloadStateCancelled) {
        return;
    }

    NSString *resolvedMIME = mime.length > 0 ? mime : @"application/octet-stream";
    NSString *sniffed = MIMETypeBySniffingData(data);
    if (sniffed.length > 0) {
        resolvedMIME = sniffed;
    }

    BOOL mediaMIME = [resolvedMIME.lowercaseString hasPrefix:@"video/"]
        || [resolvedMIME.lowercaseString hasPrefix:@"audio/"]
        || [resolvedMIME.lowercaseString hasPrefix:@"image/"];
    if (!mediaMIME && DataLooksLikeTextError(data)) {
        NSString *preview = [[NSString alloc] initWithData:data.length > 200 ? [data subdataWithRange:NSMakeRange(0, 200)] : data
                                                  encoding:NSUTF8StringEncoding];
        if (preview.length == 0) {
            preview = [[NSString alloc] initWithData:data.length > 200 ? [data subdataWithRange:NSMakeRange(0, 200)] : data
                                            encoding:NSISOLatin1StringEncoding];
        }
        preview = [[preview stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *message = preview.length > 0
            ? [NSString stringWithFormat:@"不是有效视频（%@）", preview]
            : @"不是有效视频文件";
        [self failBlobDownloadItem:item message:message];
        return;
    }
    if (!mediaMIME && sniffed.length == 0 && data.length < 2048) {
        [self failBlobDownloadItem:item message:@"下载内容过小，不像视频文件"];
        return;
    }

    NSString *filename = SanitizedFilename(DefaultFilenameForMIMEType(resolvedMIME));
    NSURL *destination = UniqueDestinationURLInDownloads(filename);
    if (!destination) {
        [self failBlobDownloadItem:item message:@"无法写入下载文件夹"];
        return;
    }

    NSError *writeError = nil;
    if (![data writeToURL:destination options:NSDataWritingAtomic error:&writeError]) {
        [self failBlobDownloadItem:item
                           message:writeError.localizedDescription ?: @"写入文件失败"];
        return;
    }

    item.sourceURL = sourceURL ?: item.sourceURL;
    item.filename = destination.lastPathComponent;
    item.destinationURL = destination;
    item.state = BrowserDownloadStateCompleted;
    item.progress = 1.0;
    item.hasKnownTotalUnitCount = YES;
    item.completedUnitCount = (int64_t)data.length;
    item.totalUnitCount = (int64_t)data.length;
    item.finishedAt = [NSDate date];
    item.unread = YES;
    item.errorMessage = nil;
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
    // 下载未完成时不要打开：部分文件（尤其 .dmg）会被系统判定损坏。
    if (item.state != BrowserDownloadStateCompleted) {
        [self revealItemInFinder:item];
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
    // Feed MIME 由浏览器内可读视图处理，不走下载。
    if ([BrowserFeedReader shouldHandleNavigationResponse:navigationResponse]) {
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
    // Seed known size from HTTP Content-Length when WebKit progress has not yet published totalUnitCount.
    long long expected = response.expectedContentLength;
    if (expected > 0) {
        item.totalUnitCount = expected;
        item.hasKnownTotalUnitCount = YES;
        if (item.completedUnitCount > 0 && item.totalUnitCount > 0) {
            item.progress = MIN(1.0, (double)item.completedUnitCount / (double)item.totalUnitCount);
        }
    }
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
    void *ctx = (__bridge void *)item.itemID;
    for (NSString *keyPath in ProgressKVOKeyPaths()) {
        [progress addObserver:self
                   forKeyPath:keyPath
                      options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                      context:ctx];
    }
    [self.observedProgressItemIDs addObject:item.itemID];
}

- (void)stopObservingProgressForItem:(BrowserDownloadItem *)item {
    if (!item || ![self.observedProgressItemIDs containsObject:item.itemID]) {
        return;
    }
    WKDownload *download = item.download;
    NSProgress *progress = download.progress;
    if (progress) {
        void *ctx = (__bridge void *)item.itemID;
        for (NSString *keyPath in ProgressKVOKeyPaths()) {
            @try {
                [progress removeObserver:self forKeyPath:keyPath context:ctx];
            } @catch (__unused NSException *exception) {
            }
        }
    }
    [self.observedProgressItemIDs removeObject:item.itemID];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (![ProgressKVOKeyPaths() containsObject:keyPath]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    (void)change;
    NSUUID *itemID = (__bridge NSUUID *)context;
    if (!itemID || ![object isKindOfClass:[NSProgress class]]) {
        return;
    }
    NSProgress *progress = (NSProgress *)object;
    int64_t completed = progress.completedUnitCount;
    int64_t total = progress.totalUnitCount;
    BOOL knownTotal = (total > 0);
    double fraction = knownTotal
        ? MIN(1.0, MAX(0.0, (double)completed / (double)total))
        : progress.fractionCompleted;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BrowserDownloadManager *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BrowserDownloadItem *liveItem = nil;
        for (BrowserDownloadItem *candidate in strongSelf.mutableItems) {
            if ([candidate.itemID isEqual:itemID]) {
                liveItem = candidate;
                break;
            }
        }
        if (!liveItem) {
            return;
        }

        BOOL changed = NO;
        if (liveItem.completedUnitCount != completed) {
            liveItem.completedUnitCount = completed;
            changed = YES;
        }
        if (knownTotal) {
            if (liveItem.totalUnitCount != total || !liveItem.hasKnownTotalUnitCount) {
                liveItem.totalUnitCount = total;
                liveItem.hasKnownTotalUnitCount = YES;
                changed = YES;
            }
        } else if (!liveItem.hasKnownTotalUnitCount && liveItem.totalUnitCount != total && total > 0) {
            liveItem.totalUnitCount = total;
            liveItem.hasKnownTotalUnitCount = YES;
            changed = YES;
        }
        // Prefer our seeded/response total when NSProgress still reports unknown.
        BOOL displayKnown = liveItem.hasKnownTotalUnitCount && liveItem.totalUnitCount > 0;
        double nextProgress = displayKnown
            ? MIN(1.0, MAX(0.0, (double)liveItem.completedUnitCount / (double)liveItem.totalUnitCount))
            : fraction;
        if (fabs(liveItem.progress - nextProgress) > 0.0001) {
            liveItem.progress = nextProgress;
            changed = YES;
        }
        if (liveItem.state == BrowserDownloadStatePending) {
            liveItem.state = BrowserDownloadStateDownloading;
            changed = YES;
        }
        if (changed) {
            [strongSelf scheduleCoalescedProgressNotify];
        }
    });
}

- (void)scheduleCoalescedProgressNotify {
    if (self.progressNotifyCoalesceScheduled) {
        return;
    }
    self.progressNotifyCoalesceScheduled = YES;
    __weak typeof(self) weakSelf = self;
    // ~15 fps: enough for smooth bars without rebuilding UI on every byte tick.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 / 15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BrowserDownloadManager *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.progressNotifyCoalesceScheduled = NO;
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
    // blob:https://www.doubao.com/<uuid> → 展示内层 host
    if ([url.scheme.lowercaseString isEqualToString:@"blob"]) {
        NSString *spec = url.resourceSpecifier;
        if (spec.length == 0) {
            NSString *abs = url.absoluteString;
            if ([abs.lowercaseString hasPrefix:@"blob:"]) {
                spec = [abs substringFromIndex:5];
            }
        }
        NSURL *inner = spec.length > 0 ? [NSURL URLWithString:spec] : nil;
        if (inner.host.length > 0) {
            return HostFromURL(inner);
        }
        return @"blob";
    }
    NSString *host = url.host;
    if (host.length == 0) {
        return url.scheme.lowercaseString ?: url.absoluteString;
    }
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return host;
}

static NSString *ExtensionForMIMEType(NSString *mime) {
    NSString *lower = mime.lowercaseString ?: @"";
    NSRange semicolon = [lower rangeOfString:@";"];
    if (semicolon.location != NSNotFound) {
        lower = [lower substringToIndex:semicolon.location];
    }
    lower = [lower stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

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

    if ([lower isEqualToString:@"video/mp4"] || [lower isEqualToString:@"video/avc"]) {
        return @"mp4";
    }
    if ([lower isEqualToString:@"video/webm"]) {
        return @"webm";
    }
    if ([lower isEqualToString:@"video/quicktime"]) {
        return @"mov";
    }
    if ([lower isEqualToString:@"video/x-matroska"] || [lower isEqualToString:@"video/matroska"]) {
        return @"mkv";
    }
    if ([lower isEqualToString:@"video/x-msvideo"]) {
        return @"avi";
    }
    if ([lower isEqualToString:@"video/ogg"]) {
        return @"ogv";
    }
    if ([lower hasPrefix:@"video/"]) {
        NSString *subtype = [lower substringFromIndex:@"video/".length];
        if (subtype.length > 0 && ![subtype containsString:@"+"]) {
            return subtype;
        }
        return @"mp4";
    }

    if ([lower isEqualToString:@"audio/mpeg"] || [lower isEqualToString:@"audio/mp3"]) {
        return @"mp3";
    }
    if ([lower isEqualToString:@"audio/mp4"] || [lower isEqualToString:@"audio/aac"] || [lower isEqualToString:@"audio/x-m4a"]) {
        return @"m4a";
    }
    if ([lower isEqualToString:@"audio/wav"] || [lower isEqualToString:@"audio/x-wav"] || [lower isEqualToString:@"audio/wave"]) {
        return @"wav";
    }
    if ([lower isEqualToString:@"audio/webm"]) {
        return @"weba";
    }
    if ([lower isEqualToString:@"audio/ogg"] || [lower isEqualToString:@"application/ogg"]) {
        return @"ogg";
    }
    if ([lower hasPrefix:@"audio/"]) {
        NSString *subtype = [lower substringFromIndex:@"audio/".length];
        if (subtype.length > 0 && ![subtype containsString:@"+"]) {
            return subtype;
        }
        return @"m4a";
    }

    return @"bin";
}

static NSString *MIMETypeBySniffingData(NSData *data) {
    if (data.length < 12) {
        return nil;
    }
    const unsigned char *bytes = data.bytes;
    // ISO BMFF (mp4/mov): size + 'ftyp'
    if (bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p') {
        return @"video/mp4";
    }
    // EBML (webm/mkv)
    if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
        return @"video/webm";
    }
    // RIFF
    if (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F') {
        if (bytes[8] == 'W' && bytes[9] == 'A' && bytes[10] == 'V' && bytes[11] == 'E') {
            return @"audio/wav";
        }
        if (bytes[8] == 'A' && bytes[9] == 'V' && bytes[10] == 'I' && bytes[11] == ' ') {
            return @"video/x-msvideo";
        }
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return @"image/jpeg";
    }
    if (bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') {
        return @"image/png";
    }
    if (bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3') {
        return @"audio/mpeg";
    }
    return nil;
}

static BOOL DataLooksLikeTextError(NSData *data) {
    if (data.length == 0) {
        return YES;
    }
    if (data.length > 8192) {
        return NO;
    }
    const unsigned char *bytes = data.bytes;
    NSUInteger printable = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char c = bytes[i];
        if (c == 9 || c == 10 || c == 13 || (c >= 32 && c < 127)) {
            printable += 1;
        }
    }
    if ((double)printable / (double)data.length < 0.85) {
        return NO;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding]
        ?: @"";
    NSString *lower = text.lowercaseString;
    if (data.length < 2048) {
        return YES;
    }
    return [lower containsString:@"unsupported"]
        || [lower containsString:@"not support"]
        || [lower containsString:@"error"]
        || [lower containsString:@"fail"]
        || [lower containsString:@"doctype"]
        || [lower containsString:@"<html"];
}

static void CleanupBlobDownloadSession(WKWebView *webView, NSString *sessionID) {
    if (!webView || sessionID.length == 0) {
        return;
    }
    NSString *cleanup = [NSString stringWithFormat:
        @"if (window.__meoBlobDownloads) { delete window.__meoBlobDownloads[%@]; }",
        JSONStringLiteral(sessionID)];
    [webView evaluateJavaScript:cleanup completionHandler:nil];
}

static NSString *DefaultFilenameForMIMEType(NSString *mime) {
    NSString *lower = mime.lowercaseString ?: @"";
    NSString *ext = ExtensionForMIMEType(mime);
    NSString *prefix = @"download";
    if ([lower hasPrefix:@"video/"]) {
        prefix = @"video";
    } else if ([lower hasPrefix:@"audio/"]) {
        prefix = @"audio";
    } else if ([lower hasPrefix:@"image/"]) {
        prefix = @"image";
    }
    return [NSString stringWithFormat:@"%@.%@", prefix, ext];
}

static NSString *JSONStringLiteral(NSString *string) {
    if (!string) {
        return @"\"\"";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string] options:0 error:nil];
    if (!data) {
        return @"\"\"";
    }
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // ["..."] → "..."
    if (arrayJSON.length >= 2 && [arrayJSON hasPrefix:@"["] && [arrayJSON hasSuffix:@"]"]) {
        return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
    }
    return @"\"\"";
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
