#import "LoginAssistController.h"
#import "BrowserWindowController.h"
#import "BrowserRiskHostPolicy.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginRunner.h"
#import "LoginElementPicker.h"
#import "LoginFormDetector.h"
#import "LoginAssistPreferences.h"
#import "SystemPasswordBridge.h"
#import "SaveRecipePromptCoordinator.h"
#import "BrowserLoginAssistSettingsWindowController.h"
#import "BrowserTransientToast.h"
#import "OTPInbox.h"
#import "CompanionChannel.h"
#import "FormMemo.h"
#import "FormMemoStore.h"
#import "FormMemoRunner.h"
#import "FormMemoInlineDetector.h"
#import "FormMemoPreferences.h"
#import "FormMemoPageSaveCoordinator.h"
#import "LoginFieldSaveCoordinator.h"
#import "SBTextField.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <AppKit/AppKit.h>
#import <Security/Security.h>

static const NSTimeInterval kAutoLoginDelay = 0.55;
static const NSTimeInterval kAutoLoginCooldown = 12.0;
/// 等待登录表单出现的最长时间；超时则静默放弃自动登录（不向用户报错）。
static const NSTimeInterval kAutoLoginFormWaitMax = 12.0;
/// 冷启动内跳过自动登录读凭证，避免与 Companion / 云同步叠弹对话框。
static const NSTimeInterval kAutoLoginColdStartSuppress = 12.0;
static NSTimeInterval sLoginAssistProcessStartAt = 0;
/// kVK_ANSI_V — 模拟 ⌘V 粘贴（多格验证码框等场景比 insertText / JS 赋值更可靠）
static const unsigned short kOTPCommandVKeyCode = 0x09;
/// kVK_Return — 粘贴后默认回车提交；多格 OTP（豆包等粘贴即跳转）会跳过
static const unsigned short kOTPReturnKeyCode = 0x24;
/// 粘贴后稍等，让页面完成 paste 分发再回车（过短会导致回车无效）
static const NSTimeInterval kOTPPasteThenEnterDelay = 0.45;

@interface LoginAssistController ()
@property (nonatomic, strong) NSArray<LoginRecipe *> *matchedRecipes;
@property (nonatomic, strong) NSArray<FormMemo *> *matchedMemos;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL hasDetectedLoginForm;
@property (nonatomic, assign) BOOL detectedHasOTP;
@property (nonatomic, copy, nullable) NSString *detectedUsernameSelector;
@property (nonatomic, copy, nullable) NSString *detectedPasswordSelector;
@property (nonatomic, copy, nullable) NSString *detectedSubmitSelector;
@property (nonatomic, copy, nullable) NSString *detectedFormId;
@property (nonatomic, copy, nullable) NSArray *detectedSlots;
@property (nonatomic, copy, nullable) NSString *lastAutoRecipeID;
@property (nonatomic, assign) NSTimeInterval lastAutoTimestamp;
@property (nonatomic, strong, nullable) dispatch_block_t pendingAutoBlock;
@property (nonatomic, copy, nullable) NSString *pendingAutoLoginRecipeID;
@property (nonatomic, strong, nullable) dispatch_block_t pendingAutoLoginExpireBlock;
@property (nonatomic, strong, nullable) id autoLoginEscapeMonitor;
@property (nonatomic, strong, nullable) BrowserLoginAssistSettingsWindowController *settingsController;
@property (nonatomic, strong) SystemPasswordBridge *passwordBridge;
@property (nonatomic, strong) SaveRecipePromptCoordinator *savePromptCoordinator;
@property (nonatomic, strong) FormMemoPageSaveCoordinator *memoSaveCoordinator;
@property (nonatomic, strong) LoginFieldSaveCoordinator *fieldSaveCoordinator;
@property (nonatomic, strong, nullable) NSDictionary *lastIconContext;
@property (nonatomic, strong, nullable) NSTimer *clipboardPollTimer;
@property (nonatomic, copy, nullable) NSString *lastSeenPasteboardChangeCount;
@property (nonatomic, copy, nullable) NSString *lastFillRequestKey;
@property (nonatomic, assign) NSTimeInterval lastFillRequestTime;
@end

@implementation LoginAssistController

+ (void)initialize {
    if (self == [LoginAssistController class]) {
        sLoginAssistProcessStartAt = [NSDate date].timeIntervalSince1970;
    }
}

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _matchedRecipes = @[];
        _matchedMemos = @[];
        _passwordBridge = [[SystemPasswordBridge alloc] init];
        _savePromptCoordinator = [[SaveRecipePromptCoordinator alloc] initWithWindowController:windowController];
        _memoSaveCoordinator = [[FormMemoPageSaveCoordinator alloc] initWithWindowController:windowController];
        _fieldSaveCoordinator = [[LoginFieldSaveCoordinator alloc] initWithWindowController:windowController];
        _detectedSlots = @[];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recipesDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(memosDidChange:)
                                                     name:FormMemoStoreDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otpInboxDidReceiveCode:)
                                                     name:OTPInboxDidReceiveCodeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(formMemoPreferencesDidChange:)
                                                     name:FormMemoPreferencesDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(loginAssistPreferencesDidChange:)
                                                     name:LoginAssistPreferencesDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelPendingAutoLogin];
    [self stopClipboardPolling];
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [LoginElementPicker registerMessageHandlerOnConfiguration:configuration handler:self];
    [LoginFormDetector installOnConfiguration:configuration messageHandler:self];
    [FormMemoInlineDetector installOnConfiguration:configuration messageHandler:self];
}

- (void)formMemoPreferencesDidChange:(NSNotification *)notification {
    (void)notification;
    // 开关变更对新建标签 / 新导航后的页面生效（与登录内联一致）。
}

- (void)loginAssistPreferencesDidChange:(NSNotification *)notification {
    (void)notification;
    [self pushFieldAssistTargetsToActiveWebView];
}

- (void)wireLoginButton:(NSButton *)button {
    self.loginButton = button;
    // 条上固定图标与 ⋯ 菜单一致：打开/切换助手侧栏（不做一键登录）。
    button.target = self.windowController;
    button.action = @selector(toggleAssistSidebar:);
    // 右键「固定/隐藏」由 ActionGroup 统一处理；登录项经 appendItemsToToolbarContextMenu: 合并。
    for (NSGestureRecognizer *gr in [button.gestureRecognizers copy]) {
        if ([gr isKindOfClass:[NSClickGestureRecognizer class]] &&
            ((NSClickGestureRecognizer *)gr).buttonMask == 0x2) {
            [button removeGestureRecognizer:gr];
        }
    }
    [self refreshButtonAppearance];
}

- (void)recipesDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateForURL:self.windowController.webView.URL];
}

- (void)memosDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateForURL:self.windowController.webView.URL];
}

- (void)otpInboxDidReceiveCode:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    BOOL waiting = [info[@"waiting"] boolValue];
    BOOL buffered = [info[@"buffered"] boolValue];
    BOOL copied = [info[@"copiedToClipboard"] boolValue];
    NSString *code = info[@"code"];
    if (![code isKindOfClass:[NSString class]]) {
        code = @"";
    }
    NSWindow *window = self.windowController.window;
    if (!window) {
        return;
    }

    // 第一时间用 Toast 展示完整验证码（后续状态 Toast 稍晚，避免立刻盖住）
    if (code.length > 0) {
        [BrowserTransientToast showMessage:[NSString stringWithFormat:@"验证码：%@", code]
                                  inWindow:window
                                  duration:3.6];
    }

    // 一键登录正在 waitOTP：LoginRunner 会填入
    if (waiting) {
        NSString *status = copied
            ? @"正在按 Recipe 填入…（已复制到剪贴板）"
            : @"正在按 Recipe 填入…";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSWindow *w = self.windowController.window;
            if (!w) {
                return;
            }
            NSString *msg = code.length > 0
                ? [NSString stringWithFormat:@"验证码：%@\n%@", code, status]
                : status;
            [BrowserTransientToast showMessage:msg inWindow:w duration:2.5];
        });
        return;
    }

    if (!buffered || code.length == 0) {
        return;
    }

    // 未在 wait：有 Recipe 则填验证码栏；否则插入光标处（操作立即执行，状态 Toast 稍后）
    [self applyIncomingOTPCode:code copiedToClipboard:copied];
}

/// Companion/粘贴等到码且当前没有 waiter 时：优先按 Recipe 填栏，否则插入光标位置。
- (void)applyIncomingOTPCode:(NSString *)code copiedToClipboard:(BOOL)copied {
    WKWebView *webView = self.windowController.webView;
    NSURL *url = webView.URL;
    LoginRecipe *recipe = url ? [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url] : nil;
    BOOL hasOTPRecipe = (recipe.otpSelector.length > 0);

    if (hasOTPRecipe && webView) {
        __weak typeof(self) weakSelf = self;
        [LoginRunner fillOTPCode:code
                       intoRecipe:recipe
                        inWebView:webView
                     shouldSubmit:NO
                       completion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (success) {
                [[OTPInbox sharedInbox] markCodeConsumed:code];
                NSString *status = copied
                    ? @"已按 Recipe 填入（并已复制到剪贴板）"
                    : @"已按 Recipe 填入";
                [strongSelf showOTPFollowUpToastWithCode:code status:status];
            } else {
                // Recipe 填入失败则退化为光标插入
                [strongSelf insertOTPAtCaret:code
                           copiedToClipboard:copied
                              failureReason:error.localizedDescription];
            }
        }];
        return;
    }

    [self insertOTPAtCaret:code copiedToClipboard:copied failureReason:nil];
}

/// 确保剪贴板为当前验证码（Companion 通常已写入，此处兜底）。
- (void)ensureOTPCodeOnPasteboard:(NSString *)code {
    if (code.length == 0) {
        return;
    }
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSString *current = [pb stringForType:NSPasteboardTypeString] ?: @"";
    if ([current isEqualToString:code]) {
        return;
    }
    [pb clearContents];
    [pb setString:code forType:NSPasteboardTypeString];
}

/// 第一响应者是否在网页内容内（WK 内部 view，而非地址栏等）。
- (BOOL)isWebContentFirstResponderInWindow:(NSWindow *)window webView:(WKWebView *)webView {
    if (!window || !webView) {
        return NO;
    }
    NSResponder *responder = window.firstResponder;
    if (![responder isKindOfClass:[NSView class]]) {
        return NO;
    }
    return [(NSView *)responder isDescendantOf:webView];
}

/// 向当前窗口投递 ⌘V 键事件，走与用户手动粘贴相同的快捷键路径。
- (BOOL)postCommandVPasteInWindow:(NSWindow *)window {
    if (!window) {
        return NO;
    }
    [window makeKeyAndOrderFront:nil];

    NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
    NSUInteger windowNumber = window.windowNumber;
    NSEvent *keyDown = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:NSEventModifierFlagCommand
                                       timestamp:timestamp
                                    windowNumber:windowNumber
                                         context:nil
                                      characters:@"v"
                     charactersIgnoringModifiers:@"v"
                                       isARepeat:NO
                                         keyCode:kOTPCommandVKeyCode];
    if (!keyDown) {
        return NO;
    }

    NSResponder *responder = window.firstResponder;
    if (responder && [responder performKeyEquivalent:keyDown]) {
        return YES;
    }

    NSEvent *keyUp = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                      location:NSZeroPoint
                                 modifierFlags:NSEventModifierFlagCommand
                                     timestamp:timestamp
                                  windowNumber:windowNumber
                                       context:nil
                                    characters:@"v"
               charactersIgnoringModifiers:@"v"
                                     isARepeat:NO
                                       keyCode:kOTPCommandVKeyCode];
    [NSApp sendEvent:keyDown];
    if (keyUp) {
        [NSApp sendEvent:keyUp];
    }
    return YES;
}

/// 向当前窗口投递回车，用于单框验证码粘贴后的提交。
- (BOOL)postReturnKeyInWindow:(NSWindow *)window {
    if (!window) {
        return NO;
    }
    [window makeKeyAndOrderFront:nil];

    NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
    NSUInteger windowNumber = window.windowNumber;
    NSEvent *keyDown = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:timestamp
                                    windowNumber:windowNumber
                                         context:nil
                                      characters:@"\r"
                     charactersIgnoringModifiers:@"\r"
                                       isARepeat:NO
                                         keyCode:kOTPReturnKeyCode];
    if (!keyDown) {
        return NO;
    }
    NSEvent *keyUp = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:timestamp
                                  windowNumber:windowNumber
                                       context:nil
                                    characters:@"\r"
               charactersIgnoringModifiers:@"\r"
                                     isARepeat:NO
                                       keyCode:kOTPReturnKeyCode];
    [NSApp sendEvent:keyDown];
    if (keyUp) {
        [NSApp sendEvent:keyUp];
    }
    return YES;
}

/// 检测豆包式多格验证码：粘贴即自动提交，再按回车会干扰跳转。
- (void)detectAutoSubmitOTPFieldInWebView:(WKWebView *)webView
                               completion:(void (^)(BOOL shouldSkipEnter))completion {
    if (!webView || !completion) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    NSString *script =
        @"(function(){\n"
         "  const el = document.activeElement;\n"
         "  if (!el) return false;\n"
         "  function maxLen(node) {\n"
         "    const m = node.getAttribute && node.getAttribute('maxlength');\n"
         "    if (m == null || m === '') return null;\n"
         "    const n = parseInt(m, 10);\n"
         "    return Number.isFinite(n) ? n : null;\n"
         "  }\n"
         "  const root = el.closest('form') || el.parentElement || document;\n"
         "  const candidates = Array.from(root.querySelectorAll('input')).filter(function(inp) {\n"
         "    if (inp.disabled || inp.readOnly) return false;\n"
         "    const t = (inp.type || 'text').toLowerCase();\n"
         "    if (t !== 'text' && t !== 'tel' && t !== 'number' && t !== 'password' && t !== 'search') return false;\n"
         "    const ml = maxLen(inp);\n"
         "    return ml === 1 || ml === 0;\n"
         "  });\n"
         "  // 4～8 个单字符框：豆包等粘贴后会自动进入，勿再回车\n"
         "  if (candidates.length >= 4 && candidates.length <= 8) {\n"
         "    if (candidates.indexOf(el) !== -1) return true;\n"
         "    if (el.closest && candidates.some(function(c) { return el.contains(c) || c.contains(el); })) return true;\n"
         "  }\n"
         "  // 焦点在单字框且同级还有多个单字框\n"
         "  const ml = maxLen(el);\n"
         "  if ((el.tagName === 'INPUT') && (ml === 1 || ml === 0)) {\n"
         "    const parent = el.parentElement;\n"
         "    if (parent) {\n"
         "      const sibs = Array.from(parent.querySelectorAll('input')).filter(function(inp) {\n"
         "        const m = maxLen(inp);\n"
         "        return m === 1 || m === 0;\n"
         "      });\n"
         "      if (sibs.length >= 4) return true;\n"
         "    }\n"
         "  }\n"
         "  return false;\n"
         "})()";
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        BOOL skip = (error == nil && [result respondsToSelector:@selector(boolValue)] && [result boolValue]);
        completion(skip);
    }];
}

/// ⌘V 成功后：网页内默认再回车；多格自动提交页跳过回车。
- (void)finishOTPPasteWithOptionalEnterForCode:(NSString *)code
                             copiedToClipboard:(BOOL)copied
                                failureReason:(NSString *)failureReason
                                       window:(NSWindow *)window
                                      webView:(WKWebView *)webView {
    [[OTPInbox sharedInbox] markCodeConsumed:code];

    BOOL inWeb = [self isWebContentFirstResponderInWindow:window webView:webView];
    if (!inWeb || !webView) {
        NSString *status = copied
            ? @"已通过 ⌘V 粘贴（并已复制到剪贴板）"
            : @"已通过 ⌘V 粘贴";
        if (failureReason.length > 0) {
            status = @"Recipe 填入失败，已改 ⌘V 粘贴";
        }
        [self showOTPFollowUpToastWithCode:code status:status];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self detectAutoSubmitOTPFieldInWebView:webView completion:^(BOOL shouldSkipEnter) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (shouldSkipEnter) {
            NSString *status = copied
                ? @"已通过 ⌘V 粘贴（多格验证码，未回车以免打断自动进入）"
                : @"已通过 ⌘V 粘贴（多格验证码，未回车）";
            if (failureReason.length > 0) {
                status = @"Recipe 填入失败，已改 ⌘V 粘贴（未回车）";
            }
            [strongSelf showOTPFollowUpToastWithCode:code status:status];
            return;
        }

        NSWindow *w = strongSelf.windowController.window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOTPPasteThenEnterDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf) {
                return;
            }
            NSWindow *liveWindow = innerSelf.windowController.window ?: w;
            // 粘贴后页面若已自动跳转/失焦，不再回车
            WKWebView *liveWeb = innerSelf.windowController.webView;
            if (![innerSelf isWebContentFirstResponderInWindow:liveWindow webView:liveWeb]) {
                NSString *status = copied
                    ? @"已通过 ⌘V 粘贴（页面已继续，未回车）"
                    : @"已通过 ⌘V 粘贴（页面已继续，未回车）";
                [innerSelf showOTPFollowUpToastWithCode:code status:status];
                return;
            }
            BOOL sent = [innerSelf postReturnKeyInWindow:liveWindow];
            NSString *status = nil;
            if (sent) {
                status = copied
                    ? @"已通过 ⌘V 粘贴并回车（并已复制到剪贴板）"
                    : @"已通过 ⌘V 粘贴并回车";
                if (failureReason.length > 0) {
                    status = @"Recipe 填入失败，已改 ⌘V 粘贴并回车";
                }
            } else {
                status = copied
                    ? @"已通过 ⌘V 粘贴（并已复制到剪贴板）"
                    : @"已通过 ⌘V 粘贴";
            }
            [innerSelf showOTPFollowUpToastWithCode:code status:status];
        });
    }];
}

- (void)insertOTPAtCaret:(NSString *)code
       copiedToClipboard:(BOOL)copied
           failureReason:(NSString *)failureReason {
    NSWindow *window = self.windowController.window;
    WKWebView *webView = self.windowController.webView;

    // 1) 优先 ⌘V：多格验证码（如豆包）等仅响应快捷键粘贴的表单；成功后再视情况回车
    if (window && code.length > 0) {
        [self ensureOTPCodeOnPasteboard:code];
        if ([self postCommandVPasteInWindow:window]) {
            [self finishOTPPasteWithOptionalEnterForCode:code
                                       copiedToClipboard:copied
                                          failureReason:failureReason
                                                 window:window
                                                webView:webView];
            return;
        }
    }

    // 2) AppKit 第一响应者可插入文本（地址栏等）
    NSResponder *resp = window.firstResponder;
    if (resp && ![resp isKindOfClass:[WKWebView class]] &&
        [resp respondsToSelector:@selector(insertText:)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [resp performSelector:@selector(insertText:) withObject:code];
        #pragma clang diagnostic pop
        [[OTPInbox sharedInbox] markCodeConsumed:code];
        NSString *status = copied
            ? @"已在光标处插入（并已复制到剪贴板）"
            : @"已在光标处插入";
        if (failureReason.length > 0) {
            status = [NSString stringWithFormat:@"Recipe 填入失败，已插入光标处"];
        }
        [self showOTPFollowUpToastWithCode:code status:status];
        return;
    }

    // 3) 网页 activeElement / 可编辑处插入
    if (!webView) {
        NSString *status = copied
            ? @"已复制到剪贴板，请 ⌘V 粘贴"
            : @"请手动粘贴";
        [self showOTPFollowUpToastWithCode:code status:status];
        return;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@[code ?: @""] options:0 error:nil];
    NSString *arrayJSON = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"[\"\"]";
    NSString *script = [NSString stringWithFormat:
        @"(function(){\n"
         "  const code = (%@)[0];\n"
         "  function dispatch(el) {\n"
         "    el.dispatchEvent(new Event('input', {bubbles:true}));\n"
         "    el.dispatchEvent(new Event('change', {bubbles:true}));\n"
         "  }\n"
         "  const el = document.activeElement;\n"
         "  if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {\n"
         "    const start = (typeof el.selectionStart === 'number') ? el.selectionStart : (el.value||'').length;\n"
         "    const end = (typeof el.selectionEnd === 'number') ? el.selectionEnd : start;\n"
         "    const v = el.value || '';\n"
         "    el.focus();\n"
         "    el.value = v.slice(0, start) + code + v.slice(end);\n"
         "    try { el.setSelectionRange(start + code.length, start + code.length); } catch (e) {}\n"
         "    dispatch(el);\n"
         "    return 'input';\n"
         "  }\n"
         "  if (el && el.isContentEditable) {\n"
         "    el.focus();\n"
         "    try {\n"
         "      if (document.execCommand('insertText', false, code)) return 'editable';\n"
         "    } catch (e) {}\n"
         "    el.textContent = (el.textContent || '') + code;\n"
         "    dispatch(el);\n"
         "    return 'editable-fallback';\n"
         "  }\n"
         "  const guess = document.querySelector(\n"
         "    'input[autocomplete=\"one-time-code\"],input[name*=\"otp\"],input[name*=\"code\"],'\n"
         "    + 'input[placeholder*=\"验证码\"],input[type=\"tel\"]'\n"
         "  );\n"
         "  if (guess) {\n"
         "    guess.focus();\n"
         "    guess.value = code;\n"
         "    dispatch(guess);\n"
         "    return 'guess';\n"
         "  }\n"
         "  return 'none';\n"
         "})()",
        arrayJSON];

    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *resultStatus = [result isKindOfClass:[NSString class]] ? (NSString *)result : @"none";
        BOOL ok = error == nil && resultStatus.length > 0 && ![resultStatus isEqualToString:@"none"];
        if (ok) {
            [[OTPInbox sharedInbox] markCodeConsumed:code];
        }
        NSString *follow = nil;
        if (ok) {
            follow = copied
                ? @"已在光标处插入（并已复制到剪贴板）"
                : @"已在光标处插入";
            if ([resultStatus isEqualToString:@"guess"]) {
                follow = copied
                    ? @"已填入疑似验证码框（并已复制到剪贴板）"
                    : @"已填入疑似验证码框";
            }
            if (failureReason.length > 0) {
                follow = @"Recipe 填入失败，已改插入光标处";
            }
        } else {
            follow = copied
                ? @"已复制到剪贴板，请点输入框后 ⌘V"
                : @"请手动粘贴";
        }
        [strongSelf showOTPFollowUpToastWithCode:code status:follow];
    }];
}

/// 延后显示后续状态，避免盖住「验证码：xxxxxx」首条 Toast
- (void)showOTPFollowUpToastWithCode:(NSString *)code status:(NSString *)status {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSWindow *w = self.windowController.window;
        if (!w || status.length == 0) {
            return;
        }
        NSString *msg = code.length > 0
            ? [NSString stringWithFormat:@"验证码：%@\n%@", code, status]
            : status;
        [BrowserTransientToast showMessage:msg inWindow:w duration:2.6];
    });
}

- (void)updateForURL:(NSURL *)url {
    if (!url || url.absoluteString.length == 0) {
        self.matchedRecipes = @[];
        self.matchedMemos = @[];
        self.hasDetectedLoginForm = NO;
        self.detectedSlots = @[];
    } else if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        self.matchedRecipes = @[];
        self.matchedMemos = @[];
        self.hasDetectedLoginForm = NO;
        self.detectedHasOTP = NO;
        self.detectedFormId = nil;
        self.detectedSlots = @[];
    } else {
        self.matchedRecipes = [[LoginRecipeStore sharedStore] recipesMatchingURL:url];
        self.matchedMemos = [[FormMemoStore sharedStore] memosMatchingURL:url];
    }
    [self refreshButtonAppearance];
    [self pushMemoFillTargetsToActiveWebView];
    [self pushFieldAssistTargetsToActiveWebView];
}

- (void)pushFieldAssistTargetsToActiveWebView {
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        return;
    }
    if (![LoginAssistPreferences inlineAssistEnabled] ||
        ![[LoginAssistPreferences loginFieldInlineMode] isEqualToString:LoginFieldInlineModePerField]) {
        NSString *clearJS = [LoginFormDetector javaScriptSettingFieldAssistTargets:@[]];
        [webView evaluateJavaScript:clearJS completionHandler:nil];
        return;
    }
    NSURL *url = webView.URL;
    if (!url || [BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        NSString *clearJS = [LoginFormDetector javaScriptSettingFieldAssistTargets:@[]];
        [webView evaluateJavaScript:clearJS completionHandler:nil];
        return;
    }

    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url];
    if (!recipe && self.matchedRecipes.count > 0) {
        recipe = self.matchedRecipes.firstObject;
    }

    void (^apply)(LoginCredentials *) = ^(LoginCredentials *creds) {
        NSArray *targets = [LoginFormDetector fieldAssistTargetDictionariesForRecipe:recipe
                                                                        credentials:creds
                                                                     detectedSlots:self.detectedSlots
                                                           extraFieldInlineEnabled:[LoginAssistPreferences loginExtraFieldInlineEnabled]];
        NSString *js = [LoginFormDetector javaScriptSettingFieldAssistTargets:targets];
        [webView evaluateJavaScript:js completionHandler:nil];
    };

    if (!recipe) {
        apply(nil);
        return;
    }
    [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID
                                                        completion:^(LoginCredentials *credentials, NSError *error) {
        (void)error;
        apply(credentials);
    }];
}

- (void)scheduleFieldAssistTargetRetries {
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[ @0.3, @0.8, @1.6, @3.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf pushFieldAssistTargetsToActiveWebView];
        });
    }
}

- (void)pushMemoFillTargetsToActiveWebView {
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        return;
    }
    FormMemo *memo = nil;
    NSURL *url = webView.URL;
    BOOL hasMemo = NO;
    if (url && ![BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        memo = [[FormMemoStore sharedStore] defaultMemoMatchingURL:url];
        if (!memo && self.matchedMemos.count > 0) {
            memo = self.matchedMemos.firstObject;
        }
        if (!memo) {
            NSArray<FormMemo *> *matched = [[FormMemoStore sharedStore] memosMatchingURL:url];
            memo = matched.firstObject;
        }
        hasMemo = (memo != nil) || (self.matchedMemos.count > 0);
    }
    NSArray<NSDictionary *> *targets = [FormMemoInlineDetector fillTargetDictionariesFromMemo:memo];
    if (targets.count > 0) {
        hasMemo = YES;
    }
    NSString *js = [FormMemoInlineDetector javaScriptSettingFillTargets:targets hasMemo:hasMemo];
    [webView evaluateJavaScript:js completionHandler:nil];
}

- (void)scheduleMemoFillTargetRetries {
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[ @0.3, @0.8, @1.6, @3.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf pushMemoFillTargetsToActiveWebView];
        });
    }
}

- (void)refreshButtonAppearance {
    NSButton *button = self.loginButton;
    if (!button) {
        return;
    }
    BOOL hasRecipe = self.matchedRecipes.count > 0;
    BOOL hasMemo = self.matchedMemos.count > 0;
    BOOL useful = hasRecipe || hasMemo || self.hasDetectedLoginForm;
    // 条上入口改为打开侧栏，始终可点（执行仍走 ⌘⇧L / 侧栏内按钮）。
    button.enabled = YES;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = useful
            ? [NSColor controlAccentColor]
            : [NSColor secondaryLabelColor];
    }
    if (hasRecipe && hasMemo) {
        button.toolTip = @"打开登录助手侧栏（⌘⇧A；⌘⇧L 一键登录）";
    } else if (hasRecipe) {
        LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:self.windowController.webView.URL];
        NSString *name = recipe.title.length > 0 ? recipe.title : recipe.host;
        button.toolTip = [NSString stringWithFormat:@"打开登录助手侧栏（可登录：%@；⌘⇧L）", name ?: @"站点"];
    } else if (hasMemo) {
        FormMemo *memo = [[FormMemoStore sharedStore] defaultMemoMatchingURL:self.windowController.webView.URL];
        NSString *name = memo.title.length > 0 ? memo.title : memo.host;
        button.toolTip = [NSString stringWithFormat:@"打开登录助手侧栏（可填备忘：%@；⌘⇧M）", name ?: @"站点"];
    } else if (self.hasDetectedLoginForm) {
        button.toolTip = @"打开登录助手侧栏（检测到登录表单；⌘⇧A）";
    } else {
        button.toolTip = @"打开登录助手侧栏（⌘⇧A）";
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    [self updateForURL:url];
    [self scheduleAutoLoginIfNeededForURL:url];
    [self.savePromptCoordinator noteNavigationFinishedInWebView:webView URL:url];
    // SPA / 晚渲染：多次重试推送填入图标
    [self scheduleMemoFillTargetRetries];
    [self scheduleFieldAssistTargetRetries];
}

- (void)clearPendingAutoLoginRequest {
    self.pendingAutoLoginRecipeID = nil;
    if (self.pendingAutoLoginExpireBlock) {
        dispatch_block_cancel(self.pendingAutoLoginExpireBlock);
        self.pendingAutoLoginExpireBlock = nil;
    }
}

- (void)cancelPendingAutoLoginSchedule {
    if (self.pendingAutoBlock) {
        dispatch_block_cancel(self.pendingAutoBlock);
        self.pendingAutoBlock = nil;
    }
    [self clearPendingAutoLoginRequest];
    if (self.autoLoginEscapeMonitor) {
        [NSEvent removeMonitor:self.autoLoginEscapeMonitor];
        self.autoLoginEscapeMonitor = nil;
    }
}

- (void)tryExecutePendingAutoLoginIfReady {
    if (!self.pendingAutoLoginRecipeID || self.isRunning) {
        return;
    }
    if (!self.hasDetectedLoginForm) {
        return;
    }

    NSString *recipeID = self.pendingAutoLoginRecipeID;
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:recipeID];
    NSURL *currentURL = self.windowController.webView.URL;
    if (!recipe || !recipe.autoLogin || ![recipe matchesURL:currentURL]) {
        [self clearPendingAutoLoginRequest];
        return;
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([recipeID isEqualToString:self.lastAutoRecipeID] &&
        (now - self.lastAutoTimestamp) < kAutoLoginCooldown) {
        [self clearPendingAutoLoginRequest];
        return;
    }

    [self clearPendingAutoLoginRequest];
    if (self.autoLoginEscapeMonitor) {
        [NSEvent removeMonitor:self.autoLoginEscapeMonitor];
        self.autoLoginEscapeMonitor = nil;
    }
    self.lastAutoRecipeID = recipeID;
    self.lastAutoTimestamp = now;
    [self runRecipe:recipe fillOnly:NO notifyOTP:NO];
}

- (void)scheduleAutoLoginIfNeededForURL:(NSURL *)url {
    [self cancelPendingAutoLoginSchedule];
    if (self.isRunning || !url) {
        return;
    }
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        return;
    }
    if (sLoginAssistProcessStartAt > 0 &&
        ([NSDate date].timeIntervalSince1970 - sLoginAssistProcessStartAt) < kAutoLoginColdStartSuppress) {
        return;
    }
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url];
    if (!recipe || !recipe.autoLogin) {
        return;
    }

    self.pendingAutoLoginRecipeID = recipe.recipeID;

    __weak typeof(self) weakSelf = self;
    dispatch_block_t expire = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf clearPendingAutoLoginRequest];
        if (strongSelf.autoLoginEscapeMonitor) {
            [NSEvent removeMonitor:strongSelf.autoLoginEscapeMonitor];
            strongSelf.autoLoginEscapeMonitor = nil;
        }
    });
    self.pendingAutoLoginExpireBlock = expire;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAutoLoginFormWaitMax * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   expire);

    self.autoLoginEscapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                        handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53) {
            [weakSelf cancelPendingAutoLoginSchedule];
            return nil;
        }
        return event;
    }];

    for (NSNumber *delay in @[ @(kAutoLoginDelay), @1.5, @3.0, @5.0, @8.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf tryExecutePendingAutoLoginIfReady];
        });
    }
}

- (void)cancelPendingAutoLogin {
    [self cancelPendingAutoLoginSchedule];
    if (self.isRunning) {
        [LoginRunner cancelAll];
        [FormMemoRunner cancelAll];
        [self stopClipboardPolling];
        self.isRunning = NO;
        [self refreshButtonAppearance];
    }
}

- (IBAction)oneClickLogin:(id)sender {
    (void)sender;
    [self cancelPendingAutoLogin];
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:self.windowController.webView.URL];
    FormMemo *memo = [[FormMemoStore sharedStore] defaultMemoMatchingURL:self.windowController.webView.URL];
    if (recipe && memo) {
        [self presentAssistMenuFromView:self.loginButton context:nil];
        return;
    }
    if (recipe) {
        // Recipe 自带 waitOTP 时走完整流程；仅启发式 OTP（无 Recipe 短信步）才 fillOnly。
        BOOL fillOnly = self.detectedHasOTP && ![recipe requiresOTPWait];
        [self runRecipe:recipe fillOnly:fillOnly notifyOTP:fillOnly];
        return;
    }
    if (memo) {
        [self runMemo:memo];
        return;
    }
    [self presentAssistMenuFromView:self.loginButton context:nil];
}

- (IBAction)fillSiteMemo:(id)sender {
    (void)sender;
    [self cancelPendingAutoLogin];
    FormMemo *memo = [[FormMemoStore sharedStore] defaultMemoMatchingURL:self.windowController.webView.URL];
    if (!memo) {
        NSWindow *window = self.windowController.window;
        if (window) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"当前页无站点备忘";
            alert.informativeText = @"可为该网址配置字段备忘，之后即可一键填入普通表单。";
            alert.alertStyle = NSAlertStyleInformational;
            [alert addButtonWithTitle:@"打开站点备忘"];
            [alert addButtonWithTitle:@"取消"];
            __weak typeof(self) weakSelf = self;
            [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
                if (returnCode == NSAlertFirstButtonReturn) {
                    [weakSelf presentAssistSidebarRevealingMemoID:nil];
                }
            }];
        }
        return;
    }
    if (self.matchedMemos.count > 1) {
        [self presentAssistMenuFromView:self.loginButton context:nil];
        return;
    }
    [self runMemo:memo];
}

- (void)showRecipeMenuFromButton:(NSButton *)button {
    [self presentAssistMenuFromView:button context:nil];
}

- (void)appendItemsToToolbarContextMenu:(NSMenu *)menu {
    if (!menu) {
        return;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [self addAssistMenuItemsToMenu:menu context:nil];
}

- (void)presentAssistMenuFromView:(NSView *)view context:(NSDictionary *)context {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"登录助手"];
    [self addAssistMenuItemsToMenu:menu context:context];

    if (view) {
        NSPoint location = NSMakePoint(0, NSHeight(view.bounds));
        [menu popUpMenuPositioningItem:nil atLocation:location inView:view];
    } else {
        NSWindow *window = self.windowController.window;
        NSPoint screen = [NSEvent mouseLocation];
        NSPoint windowPoint = [window convertPointFromScreen:screen];
        [menu popUpMenuPositioningItem:nil atLocation:windowPoint inView:window.contentView];
    }
}

- (void)addAssistMenuItemsToMenu:(NSMenu *)menu context:(NSDictionary *)context {
    NSDictionary *ctx = context ?: self.lastIconContext;
    BOOL hasOTP = context ? [context[@"hasOTP"] boolValue] : self.detectedHasOTP;

    NSMenuItem *systemItem = [[NSMenuItem alloc] initWithTitle:@"用系统密码填充…"
                                                        action:@selector(fillWithSystemPassword:)
                                                 keyEquivalent:@""];
    systemItem.target = self;
    systemItem.representedObject = ctx;
    [menu addItem:systemItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<LoginRecipe *> *recipes = self.matchedRecipes;
    if (recipes.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"（无匹配的登录配置）"
                                                       action:nil
                                                keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    } else {
        for (LoginRecipe *recipe in recipes) {
            NSString *base = recipe.title.length > 0 ? recipe.title : recipe.host;
            BOOL recipeHandlesOTP = [recipe requiresOTPWait];
            if (hasOTP && !recipeHandlesOTP) {
                NSString *title = [NSString stringWithFormat:@"填入帐密 · %@（请手动完成验证）", base];
                NSMenuItem *fill = [[NSMenuItem alloc] initWithTitle:title
                                                              action:@selector(runRecipeFillOnlyFromMenu:)
                                                       keyEquivalent:@""];
                fill.target = self;
                fill.representedObject = recipe.recipeID;
                [menu addItem:fill];
            } else {
                NSString *loginTitle = recipeHandlesOTP
                    ? [NSString stringWithFormat:@"一键登录（含验证码）· %@", base]
                    : [NSString stringWithFormat:@"一键登录 · %@", base];
                NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:loginTitle
                                                               action:@selector(runRecipeFromMenu:)
                                                        keyEquivalent:@""];
                login.target = self;
                login.representedObject = recipe.recipeID;
                [menu addItem:login];

                NSMenuItem *fillOnly = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"仅填入 · %@", base]
                                                                  action:@selector(runRecipeFillOnlyFromMenu:)
                                                           keyEquivalent:@""];
                fillOnly.target = self;
                fillOnly.representedObject = recipe.recipeID;
                [menu addItem:fillOnly];
            }
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<FormMemo *> *memos = self.matchedMemos;
    if (memos.count == 0) {
        NSMenuItem *emptyMemo = [[NSMenuItem alloc] initWithTitle:@"（无匹配的站点备忘）"
                                                           action:nil
                                                    keyEquivalent:@""];
        emptyMemo.enabled = NO;
        [menu addItem:emptyMemo];
    } else if (memos.count == 1) {
        FormMemo *memo = memos.firstObject;
        NSString *base = memo.title.length > 0 ? memo.title : memo.host;
        NSMenuItem *fillMemo = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"填入站点备忘：%@", base]
                                                          action:@selector(runMemoFromMenu:)
                                                   keyEquivalent:@""];
        fillMemo.target = self;
        fillMemo.representedObject = memo.memoID;
        [menu addItem:fillMemo];
    } else {
        NSMenu *sub = [[NSMenu alloc] initWithTitle:@"填入站点备忘"];
        for (FormMemo *memo in memos) {
            NSString *base = memo.title.length > 0 ? memo.title : memo.host;
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:base
                                                          action:@selector(runMemoFromMenu:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.representedObject = memo.memoID;
            [sub addItem:item];
        }
        NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:@"填入站点备忘"
                                                        action:nil
                                                 keyEquivalent:@""];
        parent.submenu = sub;
        [menu addItem:parent];
    }

    NSMenuItem *manageMemo = [[NSMenuItem alloc] initWithTitle:@"管理站点备忘…"
                                                        action:@selector(openMemoSidebar:)
                                                 keyEquivalent:@""];
    manageMemo.target = self;
    [menu addItem:manageMemo];

    NSMenuItem *openSidebar = [[NSMenuItem alloc] initWithTitle:@"打开助手侧栏"
                                                         action:@selector(openAssistSidebar:)
                                                  keyEquivalent:@""];
    openSidebar.target = self;
    [menu addItem:openSidebar];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *save = [[NSMenuItem alloc] initWithTitle:@"将当前输入保存为配置…"
                                                  action:@selector(saveCurrentInputAsRecipe:)
                                           keyEquivalent:@""];
    save.target = self;
    save.representedObject = ctx;
    [menu addItem:save];

    NSMenuItem *saveForm = [[NSMenuItem alloc] initWithTitle:@"将本表已填项保存为配置…"
                                                      action:@selector(saveCurrentFormFieldsAsRecipe:)
                                               keyEquivalent:@""];
    saveForm.target = self;
    saveForm.representedObject = ctx;
    [menu addItem:saveForm];

    NSMenuItem *manage = [[NSMenuItem alloc] initWithTitle:@"管理登录配置…"
                                                    action:@selector(openRecipeSidebar:)
                                             keyEquivalent:@""];
    manage.target = self;
    [menu addItem:manage];

    NSMenuItem *advanced = [[NSMenuItem alloc] initWithTitle:@"高级设置…"
                                                      action:@selector(openSettings:)
                                               keyEquivalent:@""];
    advanced.target = self;
    [menu addItem:advanced];

    NSMenuItem *pasteOTP = [[NSMenuItem alloc] initWithTitle:@"粘贴验证码…"
                                                      action:@selector(pasteOTPFromUser)
                                               keyEquivalent:@""];
    pasteOTP.target = self;
    [menu addItem:pasteOTP];
}

- (void)runRecipeFromMenu:(NSMenuItem *)item {
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:item.representedObject];
    if (recipe) {
        [self cancelPendingAutoLogin];
        [self runRecipe:recipe fillOnly:NO notifyOTP:NO];
    }
}

- (void)runRecipeFillOnlyFromMenu:(NSMenuItem *)item {
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:item.representedObject];
    if (recipe) {
        [self cancelPendingAutoLogin];
        [self runRecipe:recipe fillOnly:YES notifyOTP:YES];
    }
}

- (void)fillWithSystemPassword:(NSMenuItem *)item {
    NSDictionary *ctx = [item.representedObject isKindOfClass:[NSDictionary class]] ? item.representedObject : nil;
    NSString *userSel = ctx[@"usernameSelector"] ?: self.detectedUsernameSelector;
    NSString *passSel = ctx[@"passwordSelector"] ?: self.detectedPasswordSelector;
    if (userSel.length == 0 || passSel.length == 0) {
        [self showError:@"无法填充" message:@"未检测到用户名或密码字段。" recipeID:nil];
        return;
    }

    WKWebView *webView = self.windowController.webView;
    NSWindow *window = self.windowController.window;
    __weak typeof(self) weakSelf = self;
    [self.passwordBridge requestPasswordWithAnchorWindow:window completion:^(NSString *username, NSString *password, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error || username.length == 0) {
            NSString *msg = error.localizedDescription ?: @"未选择密码";
            if ([error.domain isEqualToString:ASAuthorizationErrorDomain] && error.code == ASAuthorizationErrorCanceled) {
                return;
            }
            // ad-hoc / 无 entitlement 时常见失败，给出可读说明
            if (msg.length == 0 || [msg containsString:@"canceled"] || [msg containsString:@"Cancelled"]) {
                return;
            }
            [strongSelf showError:@"系统密码不可用"
                          message:[NSString stringWithFormat:@"%@\n\n本地 ad-hoc 签名下系统密码选择器可能不可用；可改用登录助手配置，或使用正式开发者签名。", msg]
                         recipeID:nil];
            return;
        }
        [LoginRunner fillInWebView:webView
                  usernameSelector:userSel
                  passwordSelector:passSel
                          username:username
                          password:password ?: @""
                    submitSelector:nil
                      shouldSubmit:NO
                        completion:^(BOOL success, NSError *fillError) {
            if (!success) {
                [strongSelf showError:@"填充失败" message:fillError.localizedDescription ?: @"未知错误" recipeID:nil];
            }
        }];
    }];
}

- (void)saveCurrentInputAsRecipe:(NSMenuItem *)item {
    (void)item;
    WKWebView *webView = self.windowController.webView;
    NSURL *url = webView.URL;
    NSString *host = url.isFileURL ? @"file" : (url.host.lowercaseString ?: @"");
    [self.savePromptCoordinator promptSaveFromWebView:webView preferredHost:host existingFormInfo:nil];
}

- (void)saveCurrentFormFieldsAsRecipe:(NSMenuItem *)item {
    NSDictionary *ctx = [item.representedObject isKindOfClass:[NSDictionary class]] ? item.representedObject : (self.lastIconContext ?: @{});
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        return;
    }
    NSString *formId = self.detectedFormId ?: @"";
    if ([ctx[@"formId"] isKindOfClass:[NSString class]] && [(NSString *)ctx[@"formId"] length] > 0) {
        formId = ctx[@"formId"];
    }
    NSMutableDictionary *body = [@{
        @"formId": formId ?: @"",
        @"href": webView.URL.absoluteString ?: @"",
        @"usernameSelector": self.detectedUsernameSelector ?: @"",
        @"passwordSelector": self.detectedPasswordSelector ?: @"",
        @"submitSelector": self.detectedSubmitSelector ?: @"",
    } mutableCopy];
    NSError *jsonError = nil;
    NSData *fidData = [NSJSONSerialization dataWithJSONObject:@[formId ?: @""] options:0 error:&jsonError];
    NSString *fidArrayJSON = fidData ? [[NSString alloc] initWithData:fidData encoding:NSUTF8StringEncoding] : nil;
    NSString *fidJSON = @"\"\"";
    if (fidArrayJSON.length >= 2) {
        fidJSON = [fidArrayJSON substringWithRange:NSMakeRange(1, fidArrayJSON.length - 2)];
    }
    NSString *js = [NSString stringWithFormat:
                    @"(function(){ try { return window.__meoLoginAssistCollectFormFields(%@); } catch(e) { return []; } })();",
                    fidJSON];
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        (void)error;
        NSArray *fields = [result isKindOfClass:[NSArray class]] ? (NSArray *)result : @[];
        if (fields.count == 0) {
            [BrowserTransientToast showMessage:@"本表没有可保存的已填字段"
                                      inWindow:strongSelf.windowController.window
                                      duration:2.0];
            return;
        }
        body[@"fields"] = fields;
        NSWindow *window = strongSelf.windowController.window;
        if (!window) {
            return;
        }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"保存本表到登录助手？";
        alert.informativeText = [NSString stringWithFormat:@"将保存本表已填写的 %lu 个字段（帐密存应用内部）。", (unsigned long)fields.count];
        [alert addButtonWithTitle:@"保存"];
        [alert addButtonWithTitle:@"取消"];
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn) {
                return;
            }
            [strongSelf.fieldSaveCoordinator handleSaveFormMessage:body
                                                       fromWebView:webView
                                                        completion:^(BOOL saved) {
                if (saved) {
                    [strongSelf pushFieldAssistTargetsToActiveWebView];
                }
            }];
        }];
    }];
}

- (NSString *)credentialValue:(NSString *)slot fromCredentials:(LoginCredentials *)credentials {
    if ([slot isEqualToString:@"username"]) {
        return credentials.username ?: @"";
    }
    if ([slot isEqualToString:@"password"]) {
        return credentials.password ?: @"";
    }
    if ([slot isEqualToString:@"phone"]) {
        return credentials.phone ?: @"";
    }
    return @"";
}

- (NSString *)recipeSelector:(NSString *)slot forRecipe:(LoginRecipe *)recipe {
    if ([slot isEqualToString:@"username"]) {
        return recipe.usernameSelector ?: @"";
    }
    if ([slot isEqualToString:@"password"]) {
        return recipe.passwordSelector ?: @"";
    }
    if ([slot isEqualToString:@"phone"]) {
        return recipe.phoneSelector ?: @"";
    }
    return @"";
}

- (void)performFillSelector:(NSString *)primarySelector
              fallbackSelector:(NSString *)fallbackSelector
                         value:(NSString *)value
                       inWebView:(WKWebView *)webView {
    if (value.length == 0 || primarySelector.length == 0) {
        [BrowserTransientToast showMessage:@"该字段没有已保存的值"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [LoginRunner fillSelector:primarySelector value:value inWebView:webView completion:^(BOOL success, NSError *fillError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (success) {
            return;
        }
        if (fallbackSelector.length > 0 && ![fallbackSelector isEqualToString:primarySelector]) {
            [LoginRunner fillSelector:fallbackSelector value:value inWebView:webView completion:^(BOOL ok2, NSError *err2) {
                if (!ok2) {
                    [BrowserTransientToast showMessage:err2.localizedDescription ?: (fillError.localizedDescription ?: @"填入失败")
                                              inWindow:strongSelf.windowController.window
                                              duration:2.5];
                }
            }];
            return;
        }
        [BrowserTransientToast showMessage:fillError.localizedDescription ?: @"填入失败"
                                  inWindow:strongSelf.windowController.window
                                  duration:2.5];
    }];
}

- (void)fillCredentialSlot:(NSString *)slot
                  selector:(NSString *)selector
                    recipe:(LoginRecipe *)recipe
                   webView:(WKWebView *)webView
                retryBusy:(BOOL)retryBusy {
    NSString *requestKey = [NSString stringWithFormat:@"%@|%@|%@", recipe.recipeID ?: @"", slot ?: @"", selector ?: @""];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([requestKey isEqualToString:self.lastFillRequestKey] && (now - self.lastFillRequestTime) < 0.35) {
        return;
    }
    self.lastFillRequestKey = requestKey;
    self.lastFillRequestTime = now;

    NSString *fallbackSelector = [self recipeSelector:slot forRecipe:recipe];
    __weak typeof(self) weakSelf = self;

    LoginCredentials *cached = [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID error:nil];
    if (cached) {
        NSString *value = [self credentialValue:slot fromCredentials:cached];
        [self performFillSelector:selector fallbackSelector:fallbackSelector value:value inWebView:webView];
        return;
    }

    [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipe.recipeID
                                                        completion:^(LoginCredentials *credentials, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (!credentials) {
            if (error.code == LoginCredentialStoreErrorBusy && retryBusy) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [strongSelf fillCredentialSlot:slot selector:selector recipe:recipe webView:webView retryBusy:NO];
                });
                return;
            }
            NSString *msg = @"无法读取已保存的帐密";
            if (error.code == LoginCredentialStoreErrorBusy) {
                msg = @"凭证读取繁忙，请稍后再试";
            } else if (error.localizedDescription.length > 0) {
                msg = error.localizedDescription;
            }
            [BrowserTransientToast showMessage:msg
                                      inWindow:strongSelf.windowController.window
                                      duration:2.5];
            return;
        }
        NSString *value = [strongSelf credentialValue:slot fromCredentials:credentials];
        [strongSelf performFillSelector:selector fallbackSelector:fallbackSelector value:value inWebView:webView];
    }];
}

- (void)handleFillFieldMessage:(NSDictionary *)body fromWebView:(WKWebView *)webView {
    NSString *slot = body[@"slot"];
    NSString *selector = body[@"selector"];
    if (![slot isKindOfClass:[NSString class]] || ![selector isKindOfClass:[NSString class]] || selector.length == 0) {
        return;
    }
    NSURL *url = webView.URL;
    LoginRecipe *recipe = url ? [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url] : nil;
    if (!recipe && self.matchedRecipes.count > 0) {
        recipe = self.matchedRecipes.firstObject;
    }
    if (!recipe) {
        [BrowserTransientToast showMessage:@"当前页没有登录配置"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        return;
    }

    if ([slot isEqualToString:@"otp"]) {
        __weak typeof(self) weakSelf = self;
        [[OTPInbox sharedInbox] waitForCodeWithTimeout:0.8 completion:^(NSString *code, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            (void)error;
            if (code.length == 0) {
                [BrowserTransientToast showMessage:@"暂无验证码，请先通过 Companion 或粘贴获取"
                                          inWindow:strongSelf.windowController.window
                                          duration:2.5];
                return;
            }
            [LoginRunner fillOTPCode:code
                           intoRecipe:recipe
                            inWebView:webView
                         shouldSubmit:NO
                           completion:^(BOOL success, NSError *fillError) {
                if (success) {
                    [[OTPInbox sharedInbox] markCodeConsumed:code];
                    [BrowserTransientToast showMessage:@"已填入验证码"
                                              inWindow:strongSelf.windowController.window
                                              duration:1.8];
                } else {
                    [BrowserTransientToast showMessage:fillError.localizedDescription ?: @"填入失败"
                                              inWindow:strongSelf.windowController.window
                                              duration:2.5];
                }
            }];
        }];
        return;
    }

    if ([slot isEqualToString:@"extra"]) {
        NSString *value = @"";
        for (LoginRecipeExtraField *ef in recipe.extraFields) {
            if ([ef.selector isEqualToString:selector]) {
                value = ef.value ?: @"";
                break;
            }
        }
        if (value.length == 0) {
            [BrowserTransientToast showMessage:@"该字段没有已保存的值"
                                      inWindow:self.windowController.window
                                      duration:2.0];
            return;
        }
        __weak typeof(self) weakSelf = self;
        [LoginRunner fillSelector:selector value:value inWebView:webView completion:^(BOOL success, NSError *error) {
            if (!success) {
                [BrowserTransientToast showMessage:error.localizedDescription ?: @"填入失败"
                                          inWindow:weakSelf.windowController.window
                                          duration:2.5];
            }
        }];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *useSelector = selector;
    [self fillCredentialSlot:slot selector:useSelector recipe:recipe webView:webView retryBusy:YES];
    (void)weakSelf;
}

- (void)openSettings:(id)sender {
    (void)sender;
    [self presentSettingsEditingRecipeID:nil];
}

- (void)openMemoSettings:(id)sender {
    (void)sender;
    [self presentSettingsEditingMemoID:nil];
}

- (void)openAssistSidebar:(id)sender {
    (void)sender;
    [self presentAssistSidebar];
}

- (void)openRecipeSidebar:(id)sender {
    (void)sender;
    [self presentAssistSidebarRevealingRecipeID:nil];
}

- (void)openMemoSidebar:(id)sender {
    (void)sender;
    [self presentAssistSidebarRevealingMemoID:nil];
}

- (void)presentAssistSidebar {
    [self.windowController setAssistSidebarVisible:YES revealingRecipeID:nil memoID:nil];
}

- (void)presentAssistSidebarRevealingRecipeID:(NSString *)recipeID {
    if (recipeID.length > 0) {
        [self.windowController setAssistSidebarVisible:YES revealingRecipeID:recipeID memoID:nil];
    } else {
        [self.windowController showLoginAssistSettings:nil];
    }
}

- (void)presentAssistSidebarRevealingMemoID:(NSString *)memoID {
    if (memoID.length > 0) {
        [self.windowController setAssistSidebarVisible:YES revealingRecipeID:nil memoID:memoID];
    } else {
        [self.windowController showFormMemoSettings:nil];
    }
}

- (void)runMemoFromMenu:(NSMenuItem *)item {
    FormMemo *memo = [[FormMemoStore sharedStore] memoWithID:item.representedObject];
    if (memo) {
        [self cancelPendingAutoLogin];
        [self runMemo:memo];
    }
}

- (void)runRecipe:(LoginRecipe *)recipe {
    [self runRecipe:recipe fillOnly:NO notifyOTP:NO];
}

- (void)runRecipe:(LoginRecipe *)recipe fillOnly:(BOOL)fillOnly {
    [self runRecipe:recipe fillOnly:fillOnly notifyOTP:fillOnly];
}

- (void)runMemo:(FormMemo *)memo {
    if (self.isRunning || !memo) {
        return;
    }
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        [self showError:@"无法填入" message:@"当前没有可操作的网页。" recipeID:nil];
        return;
    }
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:webView.URL]) {
        [BrowserTransientToast showMessage:@"当前页为人机验证或高风险域，请手动完成"
                                  inWindow:self.windowController.window
                                  duration:2.5];
        return;
    }
    NSArray<FormMemoField *> *fields = [memo enabledFields];
    if (fields.count == 0) {
        [self showMemoResultAlertWithMemoID:memo.memoID
                                    message:@"没有可填入的字段。请先在站点备忘中配置选择器。"];
        return;
    }

    self.isRunning = YES;
    [self refreshButtonAppearance];
    __weak typeof(self) weakSelf = self;
    NSString *memoID = memo.memoID;
    [FormMemoRunner fillFields:fields
                     inWebView:webView
                   waitTimeout:memo.waitTimeoutMs
                    completion:^(FormMemoFillResult *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isRunning = NO;
        [strongSelf refreshButtonAppearance];
        NSWindow *window = strongSelf.windowController.window;
        if (result.allSucceeded) {
            [BrowserTransientToast showMessage:result.summaryMessage
                                      inWindow:window
                                      duration:2.0];
            return;
        }
        [strongSelf showMemoResultAlertWithMemoID:memoID message:result.summaryMessage];
    }];
}

- (void)showMemoResultAlertWithMemoID:(NSString *)memoID message:(NSString *)message {
    NSWindow *window = self.windowController.window;
    if (!window) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"站点备忘";
    alert.informativeText = message.length > 0 ? message : @"填入未完成。";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"确定"];
    if (memoID.length > 0) {
        [alert addButtonWithTitle:@"打开编辑"];
    }
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn && memoID.length > 0) {
            [weakSelf presentAssistSidebarRevealingMemoID:memoID];
        }
    }];
}

- (void)runRecipe:(LoginRecipe *)recipe fillOnly:(BOOL)fillOnly notifyOTP:(BOOL)notifyOTP {
    if (self.isRunning || !recipe) {
        return;
    }
    WKWebView *webView = self.windowController.webView;
    if (!webView) {
        [self showError:@"无法登录" message:@"当前没有可操作的网页。" recipeID:recipe.recipeID];
        return;
    }
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:webView.URL]) {
        [BrowserTransientToast showMessage:@"当前页为人机验证或高风险域，请手动完成"
                                  inWindow:self.windowController.window
                                  duration:2.5];
        return;
    }

    // 异步读本地凭证；「繁忙」不与警告叠弹（历史兼容）。
    self.isRunning = YES;
    [self refreshButtonAppearance];
    NSString *recipeID = recipe.recipeID;
    __weak typeof(self) weakSelf = self;
    [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipeID
                                                        completion:^(LoginCredentials *credentials, NSError *loadError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (!credentials) {
            strongSelf.isRunning = NO;
            [strongSelf refreshButtonAppearance];
            if ([loadError.domain isEqualToString:LoginCredentialStoreErrorDomain] &&
                loadError.code == LoginCredentialStoreErrorBusy) {
                return;
            }
            [strongSelf showError:@"无法读取凭证"
                          message:loadError.localizedDescription ?: @"凭证读取失败"
                         recipeID:recipeID];
            return;
        }

        LoginRecipe *current = [[LoginRecipeStore sharedStore] recipeWithID:recipeID] ?: recipe;
        BOOL needsOTP = [current requiresOTPWait];
        BOOL hasUserPass = (credentials.username.length > 0) || (credentials.password.length > 0);
        if (!needsOTP && !hasUserPass) {
            strongSelf.isRunning = NO;
            [strongSelf refreshButtonAppearance];
            [strongSelf showError:@"缺少账号密码" message:@"请在助手侧栏中填写用户名与密码。" recipeID:recipeID];
            return;
        }
        if (needsOTP && current.otpSelector.length == 0) {
            strongSelf.isRunning = NO;
            [strongSelf refreshButtonAppearance];
            [strongSelf showError:@"缺少验证码配置" message:@"请在助手侧栏中配置验证码选择器。" recipeID:recipeID];
            return;
        }

        WKWebView *activeWebView = strongSelf.windowController.webView;
        if (!activeWebView) {
            strongSelf.isRunning = NO;
            [strongSelf refreshButtonAppearance];
            [strongSelf showError:@"无法登录" message:@"当前没有可操作的网页。" recipeID:recipeID];
            return;
        }
        if (needsOTP && !fillOnly) {
            NSString *channelHint = [CompanionChannel sharedChannel].state == CompanionChannelStateConnected
                ? @"等待手机推送验证码…"
                : @"等待验证码…（手机未连接时可粘贴）";
            [BrowserTransientToast showMessage:channelHint
                                      inWindow:strongSelf.windowController.window
                                      duration:2.5];
            [strongSelf startClipboardPolling];
        }

        [LoginRunner runRecipe:current
                     inWebView:activeWebView
                   credentials:credentials
                      fillOnly:fillOnly
                    completion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) runnerSelf = weakSelf;
            if (!runnerSelf) {
                return;
            }
            [runnerSelf stopClipboardPolling];
            runnerSelf.isRunning = NO;
            [runnerSelf refreshButtonAppearance];
            if (!success) {
                NSString *message = error.localizedDescription ?: @"未知错误";
                if ([CompanionChannel sharedChannel].state != CompanionChannelStateConnected &&
                    [current requiresOTPWait]) {
                    message = [message stringByAppendingString:@"\n提示：可在助手侧栏或高级设置中查看配对状态，或粘贴验证码后重试。"];
                }
                [runnerSelf showError:@"登录助手执行失败"
                              message:message
                             recipeID:recipeID];
                return;
            }
            if (notifyOTP && fillOnly) {
                NSString *toast = runnerSelf.detectedHasOTP
                    ? @"帐密已填入，请完成验证后手动登录"
                    : @"帐密已填入";
                [BrowserTransientToast showMessage:toast
                                          inWindow:runnerSelf.windowController.window
                                          duration:2.0];
            }
        }];
    }];
}

- (void)startClipboardPolling {
    [self stopClipboardPolling];
    self.lastSeenPasteboardChangeCount = [NSString stringWithFormat:@"%ld", (long)NSPasteboard.generalPasteboard.changeCount];
    __weak typeof(self) weakSelf = self;
    self.clipboardPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                              repeats:YES
                                                                block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf pollClipboardForOTP];
    }];
}

- (void)stopClipboardPolling {
    [self.clipboardPollTimer invalidate];
    self.clipboardPollTimer = nil;
}

- (void)pollClipboardForOTP {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSString *change = [NSString stringWithFormat:@"%ld", (long)pb.changeCount];
    if ([change isEqualToString:self.lastSeenPasteboardChangeCount]) {
        return;
    }
    self.lastSeenPasteboardChangeCount = change;
    NSString *text = [pb stringForType:NSPasteboardTypeString];
    NSString *code = [OTPInbox extractOTPFromText:text ?: @""];
    if (code.length == 0) {
        return;
    }
    [[OTPInbox sharedInbox] submitCode:code
                                source:OTPInboxSourceClipboard
                             timestamp:[NSDate date].timeIntervalSince1970
                                 error:nil];
}

- (void)pasteOTPFromUser {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"粘贴验证码";
    alert.informativeText = @"输入或粘贴 4～8 位验证码。";
    SBTextField *input = [SBTextField standardField];
    input.frame = NSMakeRect(0, 0, 240, 24);
    NSString *clip = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    NSString *guess = [OTPInbox extractOTPFromText:clip ?: @""];
    input.stringValue = guess ?: @"";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"确定"];
    [alert addButtonWithTitle:@"取消"];
    NSWindow *window = self.windowController.window;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertFirstButtonReturn) {
            return;
        }
        NSString *value = input.stringValue;
        NSString *otp = [OTPInbox extractOTPFromText:value] ?: value;
        [[OTPInbox sharedInbox] submitCode:otp
                                    source:OTPInboxSourcePaste
                                 timestamp:[NSDate date].timeIntervalSince1970
                                     error:nil];
    }];
}

- (void)showError:(NSString *)title message:(NSString *)message recipeID:(NSString *)recipeID {
    NSWindow *window = self.windowController.window;
    if (!window) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"确定"];
    if (recipeID.length > 0) {
        [alert addButtonWithTitle:@"打开编辑"];
    }
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn && recipeID.length > 0) {
            [weakSelf presentAssistSidebarRevealingRecipeID:recipeID];
        }
    }];
}

- (void)presentSettingsEditingRecipeID:(NSString *)recipeID {
    if (!self.settingsController) {
        self.settingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
        self.settingsController.pickerHost = self;
    }
    [self.settingsController showWindow:nil];
    [self.settingsController.window center];
    [self.settingsController.window makeKeyAndOrderFront:nil];
    [self.settingsController revealRecipeSection];
    if (recipeID.length > 0) {
        [self.settingsController selectRecipeID:recipeID];
    }
}

- (void)presentSettingsEditingMemoID:(NSString *)memoID {
    if (!self.settingsController) {
        self.settingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
        self.settingsController.pickerHost = self;
    }
    [self.settingsController showWindow:nil];
    [self.settingsController.window center];
    [self.settingsController.window makeKeyAndOrderFront:nil];
    [self.settingsController revealMemoSection];
    if (memoID.length > 0) {
        [self.settingsController selectMemoID:memoID];
    }
}

- (void)presentCompanionSettings {
    if (!self.settingsController) {
        self.settingsController = [[BrowserLoginAssistSettingsWindowController alloc] init];
        self.settingsController.pickerHost = self;
    }
    [self.settingsController showWindow:nil];
    [self.settingsController.window center];
    [self.settingsController.window makeKeyAndOrderFront:nil];
    [self.settingsController revealCompanionSection];
}

- (WKWebView *)activeWebViewForPicking {
    return self.windowController.webView;
}

#pragma mark - Script messages

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if ([message.name isEqualToString:@"loginAssistPick"]) {
        [LoginElementPicker handleScriptMessageBody:message.body];
        return;
    }
    if ([message.name isEqualToString:FormMemoInlineHandlerName]) {
        NSURL *pageURL = message.webView.URL;
        if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:pageURL]) {
            return;
        }
        if (![message.body isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSDictionary *body = (NSDictionary *)message.body;
        NSString *type = body[@"type"];
        if ([type isEqualToString:@"saveField"]) {
            if (![FormMemoPreferences inlineSaveEnabled]) {
                return;
            }
            [self.memoSaveCoordinator handleSaveFieldMessage:body fromWebView:message.webView];
        } else if ([type isEqualToString:@"fillMemo"]) {
            FormMemo *memo = [[FormMemoStore sharedStore] defaultMemoMatchingURL:pageURL];
            if (!memo) {
                memo = [[FormMemoStore sharedStore] memosMatchingURL:pageURL].firstObject;
            }
            if (memo) {
                [self runMemo:memo];
            } else {
                [BrowserTransientToast showMessage:@"当前页没有站点备忘"
                                          inWindow:self.windowController.window
                                          duration:2.0];
            }
        }
        return;
    }
    if (![message.name isEqualToString:LoginFormInlineHandlerName]) {
        return;
    }
    if (![LoginAssistPreferences inlineAssistEnabled]) {
        return;
    }
    NSURL *pageURL = message.webView.URL;
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:pageURL]) {
        self.hasDetectedLoginForm = NO;
        [self refreshButtonAppearance];
        return;
    }
    if (![message.body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *type = body[@"type"];
    if ([type isEqualToString:@"formDetected"]) {
        self.hasDetectedLoginForm = YES;
        self.detectedHasOTP = [body[@"hasOTP"] boolValue];
        self.detectedFormId = body[@"formId"];
        self.detectedUsernameSelector = body[@"usernameSelector"];
        self.detectedPasswordSelector = body[@"passwordSelector"];
        self.detectedSubmitSelector = body[@"submitSelector"];
        if ([body[@"slots"] isKindOfClass:[NSArray class]]) {
            self.detectedSlots = body[@"slots"];
        } else {
            NSMutableArray *fallback = [NSMutableArray array];
            if (self.detectedUsernameSelector.length > 0) {
                [fallback addObject:@{@"slot": @"username", @"selector": self.detectedUsernameSelector}];
            }
            if (self.detectedPasswordSelector.length > 0) {
                [fallback addObject:@{@"slot": @"password", @"selector": self.detectedPasswordSelector}];
            }
            self.detectedSlots = fallback;
        }
        [self refreshButtonAppearance];
        [self pushFieldAssistTargetsToActiveWebView];
        [self tryExecutePendingAutoLoginIfReady];
    } else if ([type isEqualToString:@"formCleared"]) {
        self.hasDetectedLoginForm = NO;
        self.detectedHasOTP = NO;
        self.detectedFormId = nil;
        self.detectedSlots = @[];
        [self refreshButtonAppearance];
        [self pushFieldAssistTargetsToActiveWebView];
    } else if ([type isEqualToString:@"iconClicked"] || [type isEqualToString:@"iconMenu"] || [type isEqualToString:@"crossFrameAssist"]) {
        self.lastIconContext = body;
        self.hasDetectedLoginForm = YES;
        self.detectedHasOTP = [body[@"hasOTP"] boolValue];
        self.detectedUsernameSelector = body[@"usernameSelector"];
        self.detectedPasswordSelector = body[@"passwordSelector"];
        self.detectedSubmitSelector = body[@"submitSelector"];
        if ([type isEqualToString:@"crossFrameAssist"]) {
            [BrowserTransientToast showMessage:@"登录框在跨域框架内，已打开登录助手（请用侧栏/一键登录）"
                                      inWindow:self.windowController.window
                                      duration:2.6];
        }
        [self presentAssistMenuFromView:nil context:body];
    } else if ([type isEqualToString:@"saveField"]) {
        __weak typeof(self) weakSelf = self;
        [self.fieldSaveCoordinator handleSaveFieldMessage:body
                                              fromWebView:message.webView
                                               completion:^(BOOL saved) {
            if (saved) {
                [weakSelf pushFieldAssistTargetsToActiveWebView];
                [weakSelf updateForURL:message.webView.URL];
            }
        }];
    } else if ([type isEqualToString:@"saveFieldEmpty"]) {
        [BrowserTransientToast showMessage:@"请先填写再保存"
                                  inWindow:self.windowController.window
                                  duration:2.0];
    } else if ([type isEqualToString:@"fillField"]) {
        [self handleFillFieldMessage:body fromWebView:message.webView];
    } else if ([type isEqualToString:@"saveForm"]) {
        __weak typeof(self) weakSelf = self;
        [self.fieldSaveCoordinator handleSaveFormMessage:body
                                             fromWebView:message.webView
                                              completion:^(BOOL saved) {
            if (saved) {
                [weakSelf pushFieldAssistTargetsToActiveWebView];
                [weakSelf updateForURL:message.webView.URL];
            }
        }];
    } else if ([type isEqualToString:@"credentialsDraft"]) {
        [self.savePromptCoordinator noteCredentialsDraftOnPage];
    } else if ([type isEqualToString:@"formSubmitted"]) {
        [self.savePromptCoordinator noteFormSubmitted];
    }
}

@end
