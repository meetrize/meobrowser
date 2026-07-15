#import "LoginAssistController.h"
#import "BrowserWindowController.h"
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
#import <AuthenticationServices/AuthenticationServices.h>

static const NSTimeInterval kAutoLoginDelay = 0.55;
static const NSTimeInterval kAutoLoginCooldown = 12.0;

@interface LoginAssistController ()
@property (nonatomic, strong) NSArray<LoginRecipe *> *matchedRecipes;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL hasDetectedLoginForm;
@property (nonatomic, assign) BOOL detectedHasOTP;
@property (nonatomic, copy, nullable) NSString *detectedUsernameSelector;
@property (nonatomic, copy, nullable) NSString *detectedPasswordSelector;
@property (nonatomic, copy, nullable) NSString *detectedSubmitSelector;
@property (nonatomic, copy, nullable) NSString *detectedFormId;
@property (nonatomic, copy, nullable) NSString *lastAutoRecipeID;
@property (nonatomic, assign) NSTimeInterval lastAutoTimestamp;
@property (nonatomic, strong, nullable) dispatch_block_t pendingAutoBlock;
@property (nonatomic, strong, nullable) id autoLoginEscapeMonitor;
@property (nonatomic, strong, nullable) BrowserLoginAssistSettingsWindowController *settingsController;
@property (nonatomic, strong) SystemPasswordBridge *passwordBridge;
@property (nonatomic, strong) SaveRecipePromptCoordinator *savePromptCoordinator;
@property (nonatomic, strong, nullable) NSDictionary *lastIconContext;
@end

@implementation LoginAssistController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _matchedRecipes = @[];
        _passwordBridge = [[SystemPasswordBridge alloc] init];
        _savePromptCoordinator = [[SaveRecipePromptCoordinator alloc] initWithWindowController:windowController];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recipesDidChange:)
                                                     name:LoginRecipeStoreDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelPendingAutoLogin];
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    [LoginElementPicker registerMessageHandlerOnConfiguration:configuration handler:self];
    [LoginFormDetector installOnConfiguration:configuration messageHandler:self];
}

- (void)wireLoginButton:(NSButton *)button {
    self.loginButton = button;
    button.target = self;
    button.action = @selector(oneClickLogin:);
    BOOL hasRightClick = NO;
    for (NSGestureRecognizer *gr in button.gestureRecognizers) {
        if ([gr isKindOfClass:[NSClickGestureRecognizer class]] &&
            ((NSClickGestureRecognizer *)gr).buttonMask == 0x2) {
            hasRightClick = YES;
            break;
        }
    }
    if (!hasRightClick) {
        NSClickGestureRecognizer *rightClick = [[NSClickGestureRecognizer alloc] initWithTarget:self
                                                                                         action:@selector(loginButtonRightClicked:)];
        rightClick.buttonMask = 0x2;
        [button addGestureRecognizer:rightClick];
    }
    [self refreshButtonAppearance];
}

- (void)recipesDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateForURL:self.windowController.webView.URL];
}

- (void)updateForURL:(NSURL *)url {
    if (!url || url.absoluteString.length == 0) {
        self.matchedRecipes = @[];
        self.hasDetectedLoginForm = NO;
    } else {
        self.matchedRecipes = [[LoginRecipeStore sharedStore] recipesMatchingURL:url];
    }
    [self refreshButtonAppearance];
}

- (void)refreshButtonAppearance {
    NSButton *button = self.loginButton;
    if (!button) {
        return;
    }
    BOOL hasMatch = self.matchedRecipes.count > 0;
    BOOL useful = hasMatch || self.hasDetectedLoginForm;
    button.enabled = useful && !self.isRunning;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = (useful && !self.isRunning)
            ? [NSColor controlAccentColor]
            : [NSColor tertiaryLabelColor];
    }
    if (self.isRunning) {
        button.toolTip = @"正在登录…";
    } else if (hasMatch) {
        LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:self.windowController.webView.URL];
        NSString *name = recipe.title.length > 0 ? recipe.title : recipe.host;
        button.toolTip = [NSString stringWithFormat:@"一键登录：%@（⌘⇧L；右键更多）", name ?: @"站点"];
    } else if (self.hasDetectedLoginForm) {
        button.toolTip = @"检测到登录表单（单击打开登录助手）";
    } else {
        button.toolTip = @"当前页无可登录配置（拖动可调整顺序）";
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    [self updateForURL:url];
    [self scheduleAutoLoginIfNeededForURL:url];
    [self.savePromptCoordinator noteNavigationFinishedInWebView:webView URL:url];
}

- (void)scheduleAutoLoginIfNeededForURL:(NSURL *)url {
    [self cancelPendingAutoLogin];
    if (self.isRunning || !url) {
        return;
    }
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url];
    if (!recipe || !recipe.autoLogin) {
        return;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([recipe.recipeID isEqualToString:self.lastAutoRecipeID] &&
        (now - self.lastAutoTimestamp) < kAutoLoginCooldown) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *recipeID = recipe.recipeID;
    dispatch_block_t block = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.pendingAutoBlock = nil;
        if (strongSelf.autoLoginEscapeMonitor) {
            [NSEvent removeMonitor:strongSelf.autoLoginEscapeMonitor];
            strongSelf.autoLoginEscapeMonitor = nil;
        }
        LoginRecipe *current = [[LoginRecipeStore sharedStore] recipeWithID:recipeID];
        NSURL *currentURL = strongSelf.windowController.webView.URL;
        if (!current || !current.autoLogin || ![current matchesURL:currentURL]) {
            return;
        }
        strongSelf.lastAutoRecipeID = recipeID;
        strongSelf.lastAutoTimestamp = [NSDate date].timeIntervalSince1970;
        [strongSelf runRecipe:current fillOnly:NO notifyOTP:NO];
    });
    self.pendingAutoBlock = block;
    self.autoLoginEscapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                        handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53) {
            [weakSelf cancelPendingAutoLogin];
            return nil;
        }
        return event;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAutoLoginDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   block);
}

- (void)cancelPendingAutoLogin {
    if (self.pendingAutoBlock) {
        dispatch_block_cancel(self.pendingAutoBlock);
        self.pendingAutoBlock = nil;
    }
    if (self.autoLoginEscapeMonitor) {
        [NSEvent removeMonitor:self.autoLoginEscapeMonitor];
        self.autoLoginEscapeMonitor = nil;
    }
}

- (IBAction)oneClickLogin:(id)sender {
    (void)sender;
    [self cancelPendingAutoLogin];
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:self.windowController.webView.URL];
    if (recipe) {
        BOOL fillOnly = self.detectedHasOTP;
        [self runRecipe:recipe fillOnly:fillOnly notifyOTP:fillOnly];
        return;
    }
    [self presentAssistMenuFromView:self.loginButton context:nil];
}

- (void)loginButtonRightClicked:(NSClickGestureRecognizer *)gesture {
    if (gesture.state != NSGestureRecognizerStateEnded) {
        return;
    }
    [self presentAssistMenuFromView:self.loginButton context:nil];
}

- (void)showRecipeMenuFromButton:(NSButton *)button {
    [self presentAssistMenuFromView:button context:nil];
}

- (void)presentAssistMenuFromView:(NSView *)view context:(NSDictionary *)context {
    NSDictionary *ctx = context ?: self.lastIconContext;
    BOOL hasOTP = context ? [context[@"hasOTP"] boolValue] : self.detectedHasOTP;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"登录助手"];

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
            if (hasOTP) {
                NSString *title = [NSString stringWithFormat:@"填入帐密 · %@（请手动完成验证）", base];
                NSMenuItem *fill = [[NSMenuItem alloc] initWithTitle:title
                                                              action:@selector(runRecipeFillOnlyFromMenu:)
                                                       keyEquivalent:@""];
                fill.target = self;
                fill.representedObject = recipe.recipeID;
                [menu addItem:fill];
            } else {
                NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"一键登录 · %@", base]
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

    BOOL canSave = [ctx[@"hasUsername"] boolValue] && [ctx[@"hasPassword"] boolValue];
    if (!canSave) {
        canSave = YES; // 尝试读草稿
    }
    NSMenuItem *save = [[NSMenuItem alloc] initWithTitle:@"将当前输入保存为配置…"
                                                  action:@selector(saveCurrentInputAsRecipe:)
                                           keyEquivalent:@""];
    save.target = self;
    save.representedObject = ctx;
    [menu addItem:save];

    NSMenuItem *manage = [[NSMenuItem alloc] initWithTitle:@"管理登录配置…"
                                                    action:@selector(openSettings:)
                                             keyEquivalent:@""];
    manage.target = self;
    [menu addItem:manage];

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

- (void)openSettings:(id)sender {
    (void)sender;
    [self presentSettingsEditingRecipeID:nil];
}

- (void)runRecipe:(LoginRecipe *)recipe {
    [self runRecipe:recipe fillOnly:NO notifyOTP:NO];
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

    NSString *username = nil;
    NSString *password = nil;
    NSError *loadError = nil;
    if (![[LoginCredentialStore sharedStore] loadUsername:&username
                                                 password:&password
                                              forRecipeID:recipe.recipeID
                                                    error:&loadError]) {
        [self showError:@"无法读取凭证" message:loadError.localizedDescription ?: @"钥匙串读取失败" recipeID:recipe.recipeID];
        return;
    }
    if ((username.length == 0) && (password.length == 0)) {
        [self showError:@"缺少账号密码" message:@"请在登录助手设置中填写用户名与密码。" recipeID:recipe.recipeID];
        return;
    }

    self.isRunning = YES;
    [self refreshButtonAppearance];

    __weak typeof(self) weakSelf = self;
    [LoginRunner runRecipe:recipe
                 inWebView:webView
                  username:username ?: @""
                  password:password ?: @""
                  fillOnly:fillOnly
                completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isRunning = NO;
        [strongSelf refreshButtonAppearance];
        if (!success) {
            [strongSelf showError:@"登录助手执行失败"
                          message:error.localizedDescription ?: @"未知错误"
                         recipeID:recipe.recipeID];
            return;
        }
        if (notifyOTP && fillOnly) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"帐密已填入";
            alert.informativeText = @"检测到验证码字段或已选择仅填入。请完成验证后手动点击登录。";
            [alert addButtonWithTitle:@"好"];
            [alert beginSheetModalForWindow:strongSelf.windowController.window completionHandler:nil];
        }
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
            [weakSelf presentSettingsEditingRecipeID:recipeID];
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
    if (recipeID.length > 0) {
        [self.settingsController selectRecipeID:recipeID];
    }
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
    if (![message.name isEqualToString:LoginFormInlineHandlerName]) {
        return;
    }
    if (![LoginAssistPreferences inlineAssistEnabled]) {
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
        [self refreshButtonAppearance];
    } else if ([type isEqualToString:@"formCleared"]) {
        self.hasDetectedLoginForm = NO;
        self.detectedHasOTP = NO;
        self.detectedFormId = nil;
        [self refreshButtonAppearance];
    } else if ([type isEqualToString:@"iconClicked"]) {
        self.lastIconContext = body;
        self.hasDetectedLoginForm = YES;
        self.detectedHasOTP = [body[@"hasOTP"] boolValue];
        self.detectedUsernameSelector = body[@"usernameSelector"];
        self.detectedPasswordSelector = body[@"passwordSelector"];
        self.detectedSubmitSelector = body[@"submitSelector"];
        [self presentAssistMenuFromView:nil context:body];
    } else if ([type isEqualToString:@"credentialsDraft"]) {
        [self.savePromptCoordinator noteCredentialsDraftOnPage];
    } else if ([type isEqualToString:@"formSubmitted"]) {
        [self.savePromptCoordinator noteFormSubmitted];
    }
}

@end
