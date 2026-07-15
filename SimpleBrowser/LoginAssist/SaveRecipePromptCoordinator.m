#import "SaveRecipePromptCoordinator.h"
#import "BrowserWindowController.h"
#import "LoginAssistPreferences.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"

@interface SaveRecipePromptCoordinator ()
@property (nonatomic, weak) BrowserWindowController *windowController;
@property (nonatomic, assign) BOOL sawCredentialsDraft;
@property (nonatomic, assign) BOOL sawFormSubmitted;
@property (nonatomic, assign) BOOL promptVisible;
@property (nonatomic, copy, nullable) NSString *lastPromptedSignature;
@end

@implementation SaveRecipePromptCoordinator

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
    }
    return self;
}

- (void)noteCredentialsDraftOnPage {
    self.sawCredentialsDraft = YES;
}

- (void)noteFormSubmitted {
    self.sawFormSubmitted = YES;
}

- (NSString *)hostKeyForURL:(NSURL *)url {
    if (url.isFileURL) {
        return @"file";
    }
    return url.host.lowercaseString ?: @"";
}

- (void)noteNavigationFinishedInWebView:(WKWebView *)webView URL:(NSURL *)url {
    if (![LoginAssistPreferences promptSaveOnSuccess]) {
        return;
    }
    if (!self.sawCredentialsDraft || !self.sawFormSubmitted) {
        return;
    }
    if (self.promptVisible) {
        return;
    }

    NSString *host = [self hostKeyForURL:url];
    if ([LoginAssistPreferences shouldSuppressSavePromptForHost:host]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf promptSaveFromWebView:webView preferredHost:host existingFormInfo:nil forced:NO];
    });
}

- (void)promptSaveFromWebView:(WKWebView *)webView
               preferredHost:(NSString *)host
            existingFormInfo:(NSDictionary *)info {
    [self promptSaveFromWebView:webView preferredHost:host existingFormInfo:info forced:YES];
}

- (void)promptSaveFromWebView:(WKWebView *)webView
               preferredHost:(NSString *)host
            existingFormInfo:(NSDictionary *)info
                      forced:(BOOL)forced {
    if (self.promptVisible || !webView) {
        return;
    }

    BOOL isAutomatic = !forced;
    if (isAutomatic && ![LoginAssistPreferences promptSaveOnSuccess]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^handleDraft)(NSDictionary *) = ^(NSDictionary *draft) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (![draft isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSString *username = draft[@"username"];
        NSString *password = draft[@"password"];
        if (![username isKindOfClass:[NSString class]] || username.length == 0) {
            return;
        }
        if (![password isKindOfClass:[NSString class]] || password.length == 0) {
            return;
        }

        NSString *resolvedHost = host.length > 0 ? host : [strongSelf hostKeyForURL:webView.URL];
        if (resolvedHost.length == 0) {
            resolvedHost = @"localhost";
        }
        if (isAutomatic && [LoginAssistPreferences shouldSuppressSavePromptForHost:resolvedHost]) {
            return;
        }

        NSString *signature = [NSString stringWithFormat:@"%@|%@", resolvedHost, username];
        if (isAutomatic && [signature isEqualToString:strongSelf.lastPromptedSignature]) {
            return;
        }

        LoginRecipe *existing = nil;
        NSURL *matchURL = webView.URL;
        if (!matchURL) {
            matchURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", resolvedHost]];
        }
        for (LoginRecipe *recipe in [[LoginRecipeStore sharedStore] recipesMatchingURL:matchURL]) {
            NSString *storedUser = nil;
            [[LoginCredentialStore sharedStore] loadUsername:&storedUser password:NULL forRecipeID:recipe.recipeID error:nil];
            if ([storedUser isEqualToString:username]) {
                existing = recipe;
                break;
            }
        }

        strongSelf.promptVisible = YES;
        strongSelf.lastPromptedSignature = signature;
        strongSelf.sawFormSubmitted = NO;
        strongSelf.sawCredentialsDraft = NO;

        NSAlert *alert = [[NSAlert alloc] init];
        if (existing) {
            alert.messageText = @"更新登录助手配置？";
            alert.informativeText = [NSString stringWithFormat:@"站点 %@ 已有用户「%@」的配置。是否用当前密码与选择器更新？", resolvedHost, username];
        } else {
            alert.messageText = @"保存登录助手配置？";
            alert.informativeText = [NSString stringWithFormat:@"是否将「%@」上的帐号「%@」保存到登录助手？（密码不会显示）", resolvedHost, username];
        }
        [alert addButtonWithTitle:existing ? @"更新" : @"保存"];
        [alert addButtonWithTitle:@"不保存"];
        [alert addButtonWithTitle:@"本站不再询问"];

        NSWindow *window = strongSelf.windowController.window;
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            strongSelf.promptVisible = NO;
            if (returnCode == NSAlertThirdButtonReturn) {
                [LoginAssistPreferences setSuppressSavePrompt:YES forHost:resolvedHost];
                return;
            }
            if (returnCode != NSAlertFirstButtonReturn) {
                return;
            }

            LoginRecipe *recipe = existing ? [existing copy] : [LoginRecipe recipeWithHost:resolvedHost title:resolvedHost];
            recipe.title = resolvedHost;
            recipe.host = resolvedHost.lowercaseString;
            recipe.usernameSelector = [draft[@"usernameSelector"] isKindOfClass:[NSString class]] ? draft[@"usernameSelector"] : @"";
            recipe.passwordSelector = [draft[@"passwordSelector"] isKindOfClass:[NSString class]] ? draft[@"passwordSelector"] : @"";
            recipe.submitSelector = [draft[@"submitSelector"] isKindOfClass:[NSString class]] ? draft[@"submitSelector"] : @"";
            recipe.submitByEnter = [draft[@"submitByEnter"] boolValue] || recipe.submitSelector.length == 0;
            recipe.autoLogin = NO;
            if (!existing) {
                recipe.isDefault = YES;
            }
            recipe.mode = LoginRecipeModePassword;

            [[LoginRecipeStore sharedStore] upsertRecipe:recipe error:nil];
            [[LoginCredentialStore sharedStore] saveUsername:username
                                                    password:password
                                                 forRecipeID:recipe.recipeID
                                                       error:nil];
        }];
    };

    if ([info isKindOfClass:[NSDictionary class]] && info.count > 0) {
        handleDraft(info);
        return;
    }

    // 优先 consume；若为空则尝试 read 任一草稿（手动保存）
    [webView evaluateJavaScript:@"(function(){ if(window.__meoLoginAssistConsumeDraftForSave){ var d=window.__meoLoginAssistConsumeDraftForSave(); if(d) return d; } for (var id in (window.__meoLoginAssistDrafts||{})){} return window.__meoLoginAssistReadDraft ? window.__meoLoginAssistReadDraft(Object.keys(window.__meoLoginAssist && {})) : null; })();"
              completionHandler:^(id result, NSError *error) {
        (void)error;
        if ([result isKindOfClass:[NSDictionary class]]) {
            handleDraft(result);
            return;
        }
        // 简化：直接吃 consume 已覆盖常见路径；再试扫描全部 formId 不现实，改为第二次脚本
        [webView evaluateJavaScript:
         @"(function(){"
          "  if (!window.__meoLoginAssistReadDraft) return null;"
          "  var btns = document.querySelectorAll('button.meo-login-assist-btn');"
          "  for (var i=0;i<btns.length;i++){"
          "    var id = btns[i].getAttribute('data-meo-login-assist');"
          "    var d = window.__meoLoginAssistReadDraft(id);"
          "    if (d) return d;"
          "  }"
          "  return null;"
          "})();"
                  completionHandler:^(id result2, NSError *error2) {
            (void)error2;
            if ([result2 isKindOfClass:[NSDictionary class]]) {
                handleDraft(result2);
            }
        }];
    }];
}

@end
