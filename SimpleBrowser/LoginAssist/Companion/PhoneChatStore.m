#import "PhoneChatStore.h"
#import "PhoneNotificationInboxSettings.h"
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

NSNotificationName const PhoneChatStoreDidChangeNotification = @"PhoneChatStoreDidChangeNotification";
NSString * const PhoneChatStoreThreadIDKey = @"threadId";
NSString * const PhoneChatStoreWeChatPackageName = @"com.tencent.mm";

static const NSUInteger kMaxMessagesPerThread = 500;
static const NSTimeInterval kInboundDedupeWindowSeconds = 2.0;

@interface PhoneChatStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, PhoneChatThread *> *threadsByID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<PhoneChatMessage *> *> *messagesByThread;
@property (nonatomic, copy) NSString *rootDir;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PhoneChatStore

+ (instancetype)sharedStore {
    static PhoneChatStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _threadsByID = [NSMutableDictionary dictionary];
        _messagesByThread = [NSMutableDictionary dictionary];
        _rootDir = [[self class] chatRootDirectory];
        _queue = dispatch_queue_create("com.meobrowser.phoneChat", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_queue, ^{
            [self loadLocked];
            [self enforceRetentionLocked];
            [self persistThreadsLocked];
        });
    }
    return self;
}

+ (NSString *)chatRootDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [[root stringByAppendingPathComponent:@"MeoBrowser"]
                     stringByAppendingPathComponent:@"PhoneChat"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *msgDir = [dir stringByAppendingPathComponent:@"messages"];
    [[NSFileManager defaultManager] createDirectoryAtPath:msgDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return dir;
}

+ (NSString *)normalizeTitle:(NSString *)raw {
    NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) {
        return t;
    }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[\\(\\[（]\\d+[\\)\\]）]\\s*$"
                                                                        options:0
                                                                          error:nil];
    t = [re stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange colon = [t rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":："]];
    if (colon.location != NSNotFound && colon.location >= 1 && colon.location <= 31) {
        t = [[t substringToIndex:colon.location]
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return t;
}

+ (NSString *)threadIDForPackageName:(NSString *)packageName title:(NSString *)title {
    NSString *norm = [self normalizeTitle:title];
    NSString *raw = [NSString stringWithFormat:@"%@\n%@", packageName ?: @"", norm ?: @""];
    const char *c = raw.UTF8String ?: "";
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(c, (CC_LONG)strlen(c), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

#pragma mark - Public

- (PhoneChatThread *)ensureThreadForPackageName:(NSString *)packageName title:(NSString *)title {
    __block PhoneChatThread *thread = nil;
    dispatch_sync(self.queue, ^{
        thread = [self ensureThreadLockedPackageName:packageName title:title];
        [self persistThreadsLocked];
    });
    return thread;
}

- (BOOL)appendInboundIfNeededForPackageName:(NSString *)packageName
                                      title:(NSString *)title
                                       body:(NSString *)body
                             notificationID:(NSString *)notificationID
                                 postTimeMs:(long long)postTimeMs {
    NSString *pkg = [packageName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *ttl = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *txt = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pkg.length == 0 || ttl.length == 0) {
        return NO;
    }
    if (txt.length == 0) {
        txt = @" ";
    }

    __block BOOL appended = NO;
    __block NSString *threadID = nil;
    dispatch_sync(self.queue, ^{
        PhoneChatThread *thread = [self ensureThreadLockedPackageName:pkg title:ttl];
        threadID = thread.threadID;
        NSMutableArray<PhoneChatMessage *> *list = [self messagesArrayLockedForThreadID:thread.threadID];

        PhoneChatMessage *lastIn = nil;
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            if (list[(NSUInteger)i].direction == PhoneChatDirectionIn) {
                lastIn = list[(NSUInteger)i];
                break;
            }
        }
        NSDate *when = postTimeMs > 0
            ? [NSDate dateWithTimeIntervalSince1970:postTimeMs / 1000.0]
            : [NSDate date];
        if (lastIn && [lastIn.text isEqualToString:txt] &&
            fabs([when timeIntervalSinceDate:lastIn.createdAt]) < kInboundDedupeWindowSeconds) {
            return;
        }
        // 同 notificationId + 同正文：跳过（同 key 覆盖推送）
        if (notificationID.length > 0 && lastIn &&
            [lastIn.notificationID isEqualToString:notificationID] &&
            [lastIn.text isEqualToString:txt]) {
            return;
        }
        // 正文相对上次入站无变化则跳过（同会话刷新）
        if (lastIn && [lastIn.text isEqualToString:txt]) {
            return;
        }

        PhoneChatMessage *msg = [[PhoneChatMessage alloc] init];
        msg.messageID = [NSString stringWithFormat:@"in:%@#%lu#%lld",
                         notificationID.length > 0 ? notificationID : thread.threadID,
                         (unsigned long)txt.hash,
                         postTimeMs > 0 ? postTimeMs : (long long)(when.timeIntervalSince1970 * 1000)];
        // 防 messageId 碰撞
        if ([self messageExistsLocked:msg.messageID inThread:thread.threadID]) {
            msg.messageID = [msg.messageID stringByAppendingFormat:@"-%@", NSUUID.UUID.UUIDString];
        }
        msg.threadID = thread.threadID;
        msg.direction = PhoneChatDirectionIn;
        msg.text = txt;
        msg.createdAt = when;
        msg.notificationID = notificationID.length > 0 ? notificationID : nil;
        msg.status = PhoneChatOutboundStatusNone;
        [list addObject:msg];
        [self trimMessagesLocked:list];

        thread.title = [PhoneChatStore normalizeTitle:ttl].length > 0
            ? [PhoneChatStore normalizeTitle:ttl] : ttl;
        thread.lastMessageAt = when;
        thread.lastPreview = txt;
        thread.unreadCount += 1;

        [self persistMessagesLockedForThreadID:thread.threadID];
        [self persistThreadsLocked];
        appended = YES;
        os_log_info(OS_LOG_DEFAULT, "phoneChat inbound append thread=%{public}@ textLen=%lu",
                    thread.threadID, (unsigned long)txt.length);
    });
    if (appended && threadID.length > 0) {
        [self postDidChangeForThreadID:threadID];
    }
    return appended;
}

- (PhoneChatMessage *)beginOutboundMessageForThreadID:(NSString *)threadID
                                                 text:(NSString *)text
                                            requestID:(NSString *)requestID {
    __block PhoneChatMessage *msg = nil;
    dispatch_sync(self.queue, ^{
        PhoneChatThread *thread = self.threadsByID[threadID];
        if (!thread) {
            return;
        }
        NSString *txt = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (txt.length == 0 || requestID.length == 0) {
            return;
        }
        NSMutableArray<PhoneChatMessage *> *list = [self messagesArrayLockedForThreadID:threadID];
        msg = [[PhoneChatMessage alloc] init];
        msg.messageID = [@"out:" stringByAppendingString:NSUUID.UUID.UUIDString];
        msg.threadID = threadID;
        msg.direction = PhoneChatDirectionOut;
        msg.text = txt;
        msg.createdAt = [NSDate date];
        msg.requestID = requestID;
        msg.status = PhoneChatOutboundStatusSending;
        [list addObject:msg];
        [self trimMessagesLocked:list];
        thread.lastMessageAt = msg.createdAt;
        thread.lastPreview = txt;
        [self persistMessagesLockedForThreadID:threadID];
        [self persistThreadsLocked];
    });
    if (msg) {
        [self postDidChangeForThreadID:threadID];
    }
    return msg;
}

- (void)markOutboundSentForRequestID:(NSString *)requestID {
    [self updateOutboundRequestID:requestID status:PhoneChatOutboundStatusSent];
}

- (void)markOutboundFailedForRequestID:(NSString *)requestID {
    [self updateOutboundRequestID:requestID status:PhoneChatOutboundStatusFailed];
}

- (PhoneChatThread *)threadForID:(NSString *)threadID {
    __block PhoneChatThread *t = nil;
    dispatch_sync(self.queue, ^{
        t = self.threadsByID[threadID];
    });
    return t;
}

- (PhoneChatThread *)threadForPackageName:(NSString *)packageName title:(NSString *)title {
    NSString *tid = [PhoneChatStore threadIDForPackageName:packageName title:title];
    return [self threadForID:tid];
}

- (NSArray<PhoneChatMessage *> *)messagesForThreadID:(NSString *)threadID {
    __block NSArray<PhoneChatMessage *> *out = @[];
    dispatch_sync(self.queue, ^{
        NSArray *list = self.messagesByThread[threadID];
        out = list ? [list copy] : @[];
    });
    return out;
}

- (void)markThreadRead:(NSString *)threadID {
    __block BOOL changed = NO;
    dispatch_sync(self.queue, ^{
        PhoneChatThread *t = self.threadsByID[threadID];
        if (t && t.unreadCount != 0) {
            t.unreadCount = 0;
            [self persistThreadsLocked];
            changed = YES;
        }
    });
    if (changed) {
        [self postDidChangeForThreadID:threadID];
    }
}

#pragma mark - Locked helpers

- (PhoneChatThread *)ensureThreadLockedPackageName:(NSString *)packageName title:(NSString *)title {
    NSString *tid = [PhoneChatStore threadIDForPackageName:packageName title:title];
    PhoneChatThread *t = self.threadsByID[tid];
    if (t) {
        NSString *norm = [PhoneChatStore normalizeTitle:title];
        if (norm.length > 0) {
            t.title = norm;
        }
        return t;
    }
    t = [[PhoneChatThread alloc] init];
    t.threadID = tid;
    t.packageName = packageName;
    t.title = [PhoneChatStore normalizeTitle:title];
    if (t.title.length == 0) {
        t.title = title;
    }
    t.lastMessageAt = [NSDate date];
    t.lastPreview = @"";
    t.unreadCount = 0;
    self.threadsByID[tid] = t;
    self.messagesByThread[tid] = [NSMutableArray array];
    return t;
}

- (NSMutableArray<PhoneChatMessage *> *)messagesArrayLockedForThreadID:(NSString *)threadID {
    NSMutableArray *list = self.messagesByThread[threadID];
    if (!list) {
        list = [NSMutableArray array];
        self.messagesByThread[threadID] = list;
    }
    return list;
}

- (BOOL)messageExistsLocked:(NSString *)messageID inThread:(NSString *)threadID {
    for (PhoneChatMessage *m in self.messagesByThread[threadID]) {
        if ([m.messageID isEqualToString:messageID]) {
            return YES;
        }
    }
    return NO;
}

- (void)trimMessagesLocked:(NSMutableArray<PhoneChatMessage *> *)list {
    while (list.count > kMaxMessagesPerThread) {
        [list removeObjectAtIndex:0];
    }
}

- (void)updateOutboundRequestID:(NSString *)requestID status:(PhoneChatOutboundStatus)status {
    if (requestID.length == 0) {
        return;
    }
    __block NSString *threadID = nil;
    dispatch_sync(self.queue, ^{
        for (NSString *tid in self.messagesByThread) {
            for (PhoneChatMessage *m in self.messagesByThread[tid]) {
                if (m.direction == PhoneChatDirectionOut && [m.requestID isEqualToString:requestID]) {
                    m.status = status;
                    threadID = tid;
                    [self persistMessagesLockedForThreadID:tid];
                    return;
                }
            }
        }
    });
    if (threadID.length > 0) {
        [self postDidChangeForThreadID:threadID];
    }
}

#pragma mark - Persist

- (NSString *)threadsFilePath {
    return [self.rootDir stringByAppendingPathComponent:@"threads.json"];
}

- (NSString *)messagesFilePathForThreadID:(NSString *)threadID {
    // threadID is hex sha1 — safe as filename
    return [[self.rootDir stringByAppendingPathComponent:@"messages"]
            stringByAppendingPathComponent:[threadID stringByAppendingPathExtension:@"jsonl"]];
}

- (void)loadLocked {
    NSData *data = [NSData dataWithContentsOfFile:[self threadsFilePath]];
    if (data) {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *arr = nil;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            arr = obj[@"threads"];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            arr = obj;
        }
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                PhoneChatThread *t = [PhoneChatThread threadWithDictionary:d];
                if (t) {
                    self.threadsByID[t.threadID] = t;
                }
            }
        }
    }
    for (NSString *tid in self.threadsByID.allKeys) {
        [self loadMessagesLockedForThreadID:tid];
    }
}

- (void)loadMessagesLockedForThreadID:(NSString *)threadID {
    NSString *path = [self messagesFilePathForThreadID:threadID];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *list = [NSMutableArray array];
    if (content.length > 0) {
        NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if (line.length == 0) {
                continue;
            }
            NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
            id obj = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
            PhoneChatMessage *m = [PhoneChatMessage messageWithDictionary:obj];
            if (m) {
                [list addObject:m];
            }
        }
    }
    self.messagesByThread[threadID] = list;
}

- (void)persistThreadsLocked {
    NSMutableArray *arr = [NSMutableArray array];
    for (PhoneChatThread *t in self.threadsByID.allValues) {
        [arr addObject:[t dictionaryRepresentation]];
    }
    NSDictionary *root = @{ @"version": @1, @"threads": arr };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:[self threadsFilePath] atomically:YES];
    }
}

- (void)persistMessagesLockedForThreadID:(NSString *)threadID {
    NSArray<PhoneChatMessage *> *list = self.messagesByThread[threadID] ?: @[];
    NSMutableString *out = [NSMutableString string];
    for (PhoneChatMessage *m in list) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:[m dictionaryRepresentation] options:0 error:nil];
        if (d) {
            NSString *line = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (line) {
                [out appendString:line];
                [out appendString:@"\n"];
            }
        }
    }
    [out writeToFile:[self messagesFilePathForThreadID:threadID]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
}

- (void)enforceRetentionLocked {
    NSInteger days = [PhoneNotificationInboxSettings sharedSettings].retentionDays;
    if (days <= 0) {
        return;
    }
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-days * 24 * 3600];
    for (NSString *tid in self.messagesByThread.allKeys) {
        NSMutableArray *list = self.messagesByThread[tid];
        NSMutableArray *kept = [NSMutableArray array];
        for (PhoneChatMessage *m in list) {
            if ([m.createdAt compare:cutoff] != NSOrderedAscending) {
                [kept addObject:m];
            }
        }
        if (kept.count != list.count) {
            self.messagesByThread[tid] = kept;
            [self persistMessagesLockedForThreadID:tid];
            PhoneChatThread *t = self.threadsByID[tid];
            if (t && kept.count > 0) {
                PhoneChatMessage *last = kept.lastObject;
                t.lastMessageAt = last.createdAt;
                t.lastPreview = last.text;
            }
        }
    }
}

- (void)postDidChangeForThreadID:(NSString *)threadID {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PhoneChatStoreDidChangeNotification
                                                            object:self
                                                          userInfo:@{ PhoneChatStoreThreadIDKey: threadID ?: @"" }];
    });
}

@end
