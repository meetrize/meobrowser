#import "LoginAssistController.h"
#import "BrowserWindowController.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "LoginRunner.h"
#import "LoginElementPicker.h"
#import "BrowserLoginAssistSettingsWindowController.h"

static const NSTimeInterval kAutoLoginDelay = 0.55;
static const NSTimeInterval kAutoLoginCooldown = 12.0;

@interface LoginAssistController ()
@property (nonatomic, strong) NSArray<LoginRecipe *> *matchedRecipes;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy, nullable) NSString *lastAutoRecipeID;
@property (nonatomic, assign) NSTimeInterval lastAutoTimestamp;
@property (nonatomic, strong, nullable) dispatch_block_t pendingAutoBlock;
@property (nonatomic, strong, nullable) id autoLoginEscapeMonitor;
@property (nonatomic, strong, nullable) BrowserLoginAssistSettingsWindowController *settingsController;
@end

@implementation LoginAssistController

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _matchedRecipes = @[];
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
        rightClick.buttonMask = 0x2; // right
        [button addGestureRecognizer:rightClick];
    }
    [self refreshButtonAppearance];
}

- (void)recipesDidChange:(NSNotification *)notification {
    (void)notification;
    NSURL *url = self.windowController.webView.URL;
    [self updateForURL:url];
}

- (void)updateForURL:(NSURL *)url {
    if (!url || url.absoluteString.length == 0) {
        self.matchedRecipes = @[];
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
    button.enabled = hasMatch && !self.isRunning;
    if (@available(macOS 10.14, *)) {
        button.contentTintColor = (hasMatch && !self.isRunning)
            ? [NSColor controlAccentColor]
            : [NSColor tertiaryLabelColor];
    }
    if (self.isRunning) {
        button.toolTip = @"正在登录…";
    } else if (hasMatch) {
        LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:self.windowController.webView.URL];
        NSString *name = recipe.title.length > 0 ? recipe.title : recipe.host;
        button.toolTip = [NSString stringWithFormat:@"一键登录：%@（⌘⇧L；右键选账号）", name ?: @"站点"];
    } else {
        button.toolTip = @"当前页无可登录配置（拖动可调整顺序）";
    }
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    (void)webView;
    [self updateForURL:url];
    [self scheduleAutoLoginIfNeededForURL:url];
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
        [strongSelf runRecipe:current];
    });
    self.pendingAutoBlock = block;
    self.autoLoginEscapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                        handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53) { // Esc
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
    NSURL *url = self.windowController.webView.URL;
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] defaultRecipeMatchingURL:url];
    if (!recipe) {
        return;
    }
    [self runRecipe:recipe];
}

- (void)loginButtonRightClicked:(NSClickGestureRecognizer *)gesture {
    if (gesture.state != NSGestureRecognizerStateEnded) {
        return;
    }
    [self showRecipeMenuFromButton:self.loginButton];
}

- (void)showRecipeMenuFromButton:(NSButton *)button {
    if (!button || self.matchedRecipes.count == 0) {
        return;
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"登录助手"];
    for (LoginRecipe *recipe in self.matchedRecipes) {
        NSString *title = recipe.title.length > 0 ? recipe.title : recipe.host;
        if (recipe.isDefault) {
            title = [title stringByAppendingString:@"（默认）"];
        }
        if (recipe.autoLogin) {
            title = [title stringByAppendingString:@" · 自动"];
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(runRecipeFromMenu:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = recipe.recipeID;
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *manage = [[NSMenuItem alloc] initWithTitle:@"管理登录配置…"
                                                    action:@selector(openSettings:)
                                             keyEquivalent:@""];
    manage.target = self;
    [menu addItem:manage];
    NSPoint location = NSMakePoint(0, NSHeight(button.bounds));
    [menu popUpMenuPositioningItem:nil atLocation:location inView:button];
}

- (void)runRecipeFromMenu:(NSMenuItem *)item {
    NSString *recipeID = item.representedObject;
    LoginRecipe *recipe = [[LoginRecipeStore sharedStore] recipeWithID:recipeID];
    if (recipe) {
        [self cancelPendingAutoLogin];
        [self runRecipe:recipe];
    }
}

- (void)openSettings:(id)sender {
    (void)sender;
    [self presentSettingsEditingRecipeID:nil];
}

- (void)runRecipe:(LoginRecipe *)recipe {
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

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.name isEqualToString:@"loginAssistPick"]) {
        return;
    }
    [LoginElementPicker handleScriptMessageBody:message.body];
}

@end
