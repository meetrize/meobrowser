#import "OTPInbox.h"
#import <AppKit/AppKit.h>

OTPInboxSource const OTPInboxSourceCompanion = @"companion";
OTPInboxSource const OTPInboxSourcePaste = @"paste";
OTPInboxSource const OTPInboxSourceClipboard = @"clipboard";
OTPInboxSource const OTPInboxSourceMock = @"mock";

NSNotificationName const OTPInboxDidReceiveCodeNotification = @"OTPInboxDidReceiveCodeNotification";

@interface OTPInboxPending : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, copy) OTPInboxSource source;
@end

@implementation OTPInboxPending
@end

@interface OTPInbox ()
@property (nonatomic, strong, nullable) OTPInboxPending *pending;
@property (nonatomic, copy, nullable) NSString *consumedCode;
@property (nonatomic, assign) NSTimeInterval consumedAt;
@property (nonatomic, copy, nullable) OTPInboxWaitCompletion waitCompletion;
@property (nonatomic, strong, nullable) dispatch_block_t waitTimeoutBlock;
@property (nonatomic, assign) NSInteger waitGeneration;
@end

@implementation OTPInbox

+ (instancetype)sharedInbox {
    static OTPInbox *inbox;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inbox = [[self alloc] init];
    });
    return inbox;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ttlSeconds = 120;
    }
    return self;
}

+ (NSString *)extractOTPFromText:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\b(\\d{4,8})\\b"
                                                                        options:0
                                                                          error:nil];
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:text
                                                          options:0
                                                            range:NSMakeRange(0, text.length)];
    if (matches.count == 0) {
        return nil;
    }
    NSTextCheckingResult *last = matches.lastObject;
    if (last.numberOfRanges < 2) {
        return nil;
    }
    return [text substringWithRange:[last rangeAtIndex:1]];
}

- (BOOL)isValidCode:(NSString *)code {
    if (code.length < 4 || code.length > 8) {
        return NO;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [code rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

/// Companion / 粘贴等到码后写入系统剪贴板，便于页面未自动填入时 ⌘V。返回是否已写入。
- (BOOL)copyCodeToPasteboardIfNeeded:(NSString *)code source:(OTPInboxSource)source {
    if (code.length == 0) {
        return NO;
    }
    if ([source isEqualToString:OTPInboxSourceClipboard]) {
        return NO;
    }
    void (^copyBlock)(void) = ^{
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb setString:code forType:NSPasteboardTypeString];
        NSLog(@"[OTPInbox] copied code to clipboard source=%@", source);
    };
    if ([NSThread isMainThread]) {
        copyBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), copyBlock);
    }
    return YES;
}

- (BOOL)submitCode:(NSString *)code
            source:(OTPInboxSource)source
         timestamp:(NSTimeInterval)timestamp
             error:(NSError **)error {
    NSString *normalized = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![self isValidCode:normalized]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OTPInbox"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"验证码格式无效（需要 4～8 位数字）"}];
        }
        return NO;
    }
    if (timestamp <= 0) {
        timestamp = [NSDate date].timeIntervalSince1970;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ((now - timestamp) > self.ttlSeconds || (timestamp - now) > 30) {
        if (error) {
            *error = [NSError errorWithDomain:@"OTPInbox"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"验证码已过期"}];
        }
        return NO;
    }
    if (self.consumedCode.length > 0 &&
        [self.consumedCode isEqualToString:normalized] &&
        (now - self.consumedAt) < self.ttlSeconds) {
        if (error) {
            *error = [NSError errorWithDomain:@"OTPInbox"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"验证码已使用"}];
        }
        return NO;
    }

    if (self.waitCompletion) {
        OTPInboxWaitCompletion completion = self.waitCompletion;
        [self clearWaitStateKeepingPending:NO];
        self.consumedCode = normalized;
        self.consumedAt = now;
        BOOL copied = [self copyCodeToPasteboardIfNeeded:normalized source:source];
        NSLog(@"[OTPInbox] accepted code length=%lu source=%@", (unsigned long)normalized.length, source);
        [[NSNotificationCenter defaultCenter] postNotificationName:OTPInboxDidReceiveCodeNotification
                                                            object:self
                                                          userInfo:@{
                                                              @"source": source ?: OTPInboxSourceMock,
                                                              @"waiting": @YES,
                                                              @"buffered": @NO,
                                                              @"copiedToClipboard": @(copied),
                                                          }];
        completion(normalized, nil);
        return YES;
    }

    OTPInboxPending *pending = [[OTPInboxPending alloc] init];
    pending.code = normalized;
    pending.timestamp = timestamp;
    pending.source = source ?: OTPInboxSourceMock;
    self.pending = pending;
    BOOL copied = [self copyCodeToPasteboardIfNeeded:normalized source:source];
    NSLog(@"[OTPInbox] buffered code length=%lu source=%@", (unsigned long)normalized.length, source);
    [[NSNotificationCenter defaultCenter] postNotificationName:OTPInboxDidReceiveCodeNotification
                                                        object:self
                                                      userInfo:@{
                                                          @"source": source ?: OTPInboxSourceMock,
                                                          @"waiting": @NO,
                                                          @"buffered": @YES,
                                                          @"copiedToClipboard": @(copied),
                                                      }];
    return YES;
}

- (void)clearWaitStateKeepingPending:(BOOL)keepPending {
    if (self.waitTimeoutBlock) {
        dispatch_block_cancel(self.waitTimeoutBlock);
        self.waitTimeoutBlock = nil;
    }
    self.waitCompletion = nil;
    if (!keepPending) {
        // pending cleared by caller when delivered
    }
}

- (void)waitForCodeWithTimeout:(NSTimeInterval)timeout
                    completion:(OTPInboxWaitCompletion)completion {
    if (!completion) {
        return;
    }
    [self cancelWait];

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.pending) {
        OTPInboxPending *pending = self.pending;
        if ((now - pending.timestamp) <= self.ttlSeconds &&
            !(self.consumedCode.length > 0 && [self.consumedCode isEqualToString:pending.code])) {
            self.pending = nil;
            self.consumedCode = pending.code;
            self.consumedAt = now;
            completion(pending.code, nil);
            return;
        }
        self.pending = nil;
    }

    self.waitGeneration += 1;
    NSInteger generation = self.waitGeneration;
    self.waitCompletion = completion;

    if (timeout <= 0) {
        timeout = self.ttlSeconds;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.waitGeneration != generation) {
            return;
        }
        OTPInboxWaitCompletion waitCompletion = strongSelf.waitCompletion;
        strongSelf.waitCompletion = nil;
        strongSelf.waitTimeoutBlock = nil;
        if (waitCompletion) {
            waitCompletion(nil, [NSError errorWithDomain:@"OTPInbox"
                                                    code:4
                                                userInfo:@{NSLocalizedDescriptionKey: @"等待验证码超时"}]);
        }
    });
    self.waitTimeoutBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)cancelWait {
    self.waitGeneration += 1;
    if (self.waitTimeoutBlock) {
        dispatch_block_cancel(self.waitTimeoutBlock);
        self.waitTimeoutBlock = nil;
    }
    OTPInboxWaitCompletion completion = self.waitCompletion;
    self.waitCompletion = nil;
    if (completion) {
        completion(nil, [NSError errorWithDomain:@"OTPInbox"
                                            code:5
                                        userInfo:@{NSLocalizedDescriptionKey: @"已取消等待验证码"}]);
    }
}

@end
