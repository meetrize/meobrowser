#import "LoginFieldSaveCoordinator.h"
#import "BrowserWindowController.h"
#import "LoginRecipe.h"
#import "LoginRecipeStore.h"
#import "LoginCredentialStore.h"
#import "BrowserTransientToast.h"
#import "BrowserRiskHostPolicy.h"

@interface LoginFieldSaveCoordinator ()
@property (nonatomic, weak) BrowserWindowController *windowController;
@property (nonatomic, assign) BOOL promptVisible;
@end

@implementation LoginFieldSaveCoordinator

- (instancetype)initWithWindowController:(BrowserWindowController *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
    }
    return self;
}

- (NSString *)hostKeyForURL:(NSURL *)url {
    if (!url) {
        return @"";
    }
    if (url.isFileURL) {
        return @"file";
    }
    return url.host.lowercaseString ?: @"";
}

- (nullable NSString *)pathPrefixForURL:(NSURL *)url {
    if (!url || url.isFileURL) {
        if (url.isFileURL) {
            NSString *last = url.lastPathComponent;
            return last.length > 0 ? last : nil;
        }
        return nil;
    }
    NSString *path = url.path ?: @"";
    if (path.length == 0 || [path isEqualToString:@"/"]) {
        return nil;
    }
    return path;
}

- (NSURL *)resolveURL:(WKWebView *)webView body:(NSDictionary *)body {
    NSURL *url = webView.URL;
    if (!url && [body[@"href"] isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)body[@"href"]];
    }
    return url;
}

- (LoginRecipe *)recipeForURL:(NSURL *)url host:(NSString *)host createIfNeeded:(BOOL)create created:(BOOL *)createdOut {
    LoginRecipeStore *store = [LoginRecipeStore sharedStore];
    LoginRecipe *recipe = [store defaultRecipeMatchingURL:url];
    if (!recipe) {
        recipe = [store recipesMatchingURL:url].firstObject;
    }
    BOOL created = NO;
    if (!recipe && create) {
        created = YES;
        recipe = [LoginRecipe recipeWithHost:host title:host];
        recipe.pathPrefix = [self pathPrefixForURL:url];
        recipe.isDefault = YES;
        recipe.autoLogin = NO;
        recipe.mode = LoginRecipeModePassword;
        recipe.submitByEnter = YES;
    } else if (recipe) {
        recipe = [recipe copy];
    }
    if (createdOut) {
        *createdOut = created;
    }
    return recipe;
}

- (LoginCredentials *)loadOrEmptyCredentialsForRecipeID:(NSString *)recipeID {
    LoginCredentials *creds = [[LoginCredentialStore sharedStore] loadCredentialsForRecipeID:recipeID error:nil];
    if (!creds) {
        creds = [[LoginCredentials alloc] init];
        creds.username = @"";
        creds.password = @"";
        creds.phone = @"";
    }
    return creds;
}

- (BOOL)applySlot:(NSString *)slot
            value:(NSString *)value
         selector:(NSString *)selector
            label:(NSString *)label
         toRecipe:(LoginRecipe *)recipe
      credentials:(LoginCredentials *)credentials {
    if (slot.length == 0 || selector.length == 0) {
        return NO;
    }
    if ([slot isEqualToString:@"username"]) {
        recipe.usernameSelector = selector;
        credentials.username = value;
        return YES;
    }
    if ([slot isEqualToString:@"password"]) {
        recipe.passwordSelector = selector;
        credentials.password = value;
        return YES;
    }
    if ([slot isEqualToString:@"phone"]) {
        recipe.phoneSelector = selector;
        credentials.phone = value;
        return YES;
    }
    if ([slot isEqualToString:@"extra"]) {
        NSMutableArray<LoginRecipeExtraField *> *fields = [NSMutableArray arrayWithCapacity:recipe.extraFields.count + 1];
        BOOL updated = NO;
        for (LoginRecipeExtraField *ef in recipe.extraFields) {
            LoginRecipeExtraField *copy = [ef copy];
            if (!updated && [copy.selector isEqualToString:selector]) {
                copy.value = value;
                if (label.length > 0) {
                    copy.label = label;
                }
                copy.enabled = YES;
                updated = YES;
            }
            [fields addObject:copy];
        }
        if (!updated) {
            [fields addObject:[LoginRecipeExtraField fieldWithLabel:label.length ? label : @"字段"
                                                           selector:selector
                                                              value:value]];
        }
        recipe.extraFields = fields;
        return YES;
    }
    return NO;
}

- (BOOL)commitRecipe:(LoginRecipe *)recipe
         credentials:(LoginCredentials *)credentials
               error:(NSError **)error {
    // 先凭证再 upsert，避免列表刷新冲掉未写入的 Keychain。
    if (![[LoginCredentialStore sharedStore] saveCredentials:credentials forRecipeID:recipe.recipeID error:error]) {
        return NO;
    }
    recipe.updatedAt = [NSDate date].timeIntervalSince1970;
    if (![[LoginRecipeStore sharedStore] upsertRecipe:recipe error:error]) {
        return NO;
    }
    if (recipe.isDefault) {
        [[LoginRecipeStore sharedStore] setDefaultRecipeID:recipe.recipeID error:nil];
    }
    return YES;
}

- (void)handleSaveFieldMessage:(NSDictionary *)body
                   fromWebView:(WKWebView *)webView
                    completion:(LoginFieldSaveCompletion)completion {
    [self confirmSaveFieldOrWholeFormFromBody:body fromWebView:webView completion:completion];
}

- (void)confirmSaveFieldOrWholeFormFromBody:(NSDictionary *)body
                                fromWebView:(WKWebView *)webView
                                 completion:(LoginFieldSaveCompletion)completion {
    if (self.promptVisible) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    NSURL *url = [self resolveURL:webView body:body];
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSString *slot = body[@"slot"];
    NSString *selector = body[@"selector"];
    NSString *label = body[@"label"];
    NSString *value = body[@"value"];
    if (![slot isKindOfClass:[NSString class]] || [slot isEqualToString:@"otp"]) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    if (![selector isKindOfClass:[NSString class]] || selector.length == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    if (![value isKindOfClass:[NSString class]]) {
        value = @"";
    }
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        [BrowserTransientToast showMessage:@"请先填写再保存"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        if (completion) {
            completion(NO);
        }
        return;
    }
    if (![label isKindOfClass:[NSString class]] || label.length == 0) {
        label = slot;
    }

    NSString *host = [self hostKeyForURL:url];
    if (host.length == 0) {
        [BrowserTransientToast showMessage:@"无法保存：缺少主机"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSWindow *window = self.windowController.window;
    if (!window) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    self.promptVisible = YES;
    __weak typeof(self) weakSelf = self;
    NSString *formId = [body[@"formId"] isKindOfClass:[NSString class]] ? body[@"formId"] : @"";
    NSString *collectJS = [NSString stringWithFormat:
                           @"(function(){ try {"
                           @"  if (window.__meoLoginAssistCollectFormFields) {"
                           @"    var a = window.__meoLoginAssistCollectFormFields(%@);"
                           @"    if (a && a.length) return a;"
                           @"  }"
                           @"  if (window.top && window.top !== window && window.top.__meoLoginAssistCollectFormFields) {"
                           @"    return window.top.__meoLoginAssistCollectFormFields(%@);"
                           @"  }"
                           @"  try {"
                           @"    for (var i = 0; i < window.frames.length; i++) {"
                           @"      var f = window.frames[i];"
                           @"      if (f && f.__meoLoginAssistCollectFormFields) {"
                           @"        var b = f.__meoLoginAssistCollectFormFields(%@);"
                           @"        if (b && b.length) return b;"
                           @"      }"
                           @"    }"
                           @"  } catch (e2) {}"
                           @"  return [];"
                           @"} catch(e) { return []; } })();",
                           [self jsonStringLiteral:formId],
                           [self jsonStringLiteral:formId],
                           [self jsonStringLiteral:formId]];

    // 先收集本表字段，再用应用级模态确认（sheet 在 WK 点击后中间按钮经常点不动）。
    void (^presentConfirm)(NSArray *) = ^(NSArray *precollectedFields) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(NO);
            }
            return;
        }
        NSWindow *hostWindow = strongSelf.windowController.window ?: window;
        if (hostWindow) {
            [hostWindow makeKeyAndOrderFront:nil];
        }

        NSMutableArray *fields = [NSMutableArray array];
        if ([precollectedFields isKindOfClass:[NSArray class]]) {
            for (id item in precollectedFields) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [fields addObject:item];
                }
            }
        }
        // 确保包含当前触发保存的字段
        BOOL hasCurrent = NO;
        for (NSDictionary *f in fields) {
            if ([f[@"selector"] isKindOfClass:[NSString class]] &&
                [f[@"selector"] isEqualToString:selector]) {
                hasCurrent = YES;
                break;
            }
        }
        if (!hasCurrent) {
            [fields insertObject:@{
                @"slot": slot ?: @"",
                @"selector": selector ?: @"",
                @"label": label ?: @"",
                @"value": value ?: @"",
            } atIndex:0];
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = @"保存到登录助手？";
        alert.informativeText = [NSString stringWithFormat:
                                 @"将「%@」保存到本站登录配置（帐密存应用内部）。\n也可一次保存本表已填写的全部合格字段（当前可保存 %lu 项）。",
                                 label,
                                 (unsigned long)fields.count];
        NSButton *saveFieldBtn = [alert addButtonWithTitle:@"保存此字段"];
        NSButton *saveFormBtn = [alert addButtonWithTitle:@"保存本表已填项"];
        [alert addButtonWithTitle:@"取消"];
        saveFieldBtn.keyEquivalent = @"\r";
        saveFormBtn.keyEquivalent = @"s";
        saveFormBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;

        // 应用级模态：避免 beginSheet 在 WKWebView 触发后第二按钮无命中。
        NSModalResponse returnCode = [alert runModal];
        strongSelf.promptVisible = NO;

        if (returnCode == NSAlertFirstButtonReturn) {
            BOOL ok = [strongSelf commitSingleSlot:slot
                                             value:value
                                          selector:selector
                                             label:label
                                              body:body
                                               url:url
                                              host:host];
            if (completion) {
                completion(ok);
            }
            return;
        }
        if (returnCode == NSAlertSecondButtonReturn) {
            NSDictionary *payload = @{
                @"formId": formId ?: @"",
                @"fields": fields,
                @"skipConfirm": @YES,
                @"usernameSelector": body[@"usernameSelector"] ?: @"",
                @"passwordSelector": body[@"passwordSelector"] ?: @"",
                @"phoneSelector": body[@"phoneSelector"] ?: @"",
                @"submitSelector": body[@"submitSelector"] ?: @"",
                @"href": body[@"href"] ?: (url.absoluteString ?: @""),
            };
            [strongSelf handleSaveFormMessage:payload fromWebView:webView completion:completion];
            return;
        }
        if (completion) {
            completion(NO);
        }
    };

    // 等鼠标抬起进入下一圈 runloop，再收集 + 弹窗。
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(NO);
            }
            return;
        }
        if (!webView) {
            presentConfirm(@[]);
            return;
        }
        [webView evaluateJavaScript:collectJS completionHandler:^(id result, NSError *error) {
            (void)error;
            NSArray *fields = [result isKindOfClass:[NSArray class]] ? (NSArray *)result : @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                presentConfirm(fields);
            });
        }];
    });
}

- (BOOL)commitSingleSlot:(NSString *)slot
                   value:(NSString *)value
                selector:(NSString *)selector
                   label:(NSString *)label
                    body:(NSDictionary *)body
                     url:(NSURL *)url
                    host:(NSString *)host {
    BOOL created = NO;
    LoginRecipe *recipe = [self recipeForURL:url host:host createIfNeeded:YES created:&created];
    if (!recipe) {
        return NO;
    }
    if ([body[@"submitSelector"] isKindOfClass:[NSString class]] && [(NSString *)body[@"submitSelector"] length] > 0) {
        recipe.submitSelector = body[@"submitSelector"];
    }
    if ([body[@"usernameSelector"] isKindOfClass:[NSString class]] && recipe.usernameSelector.length == 0) {
        recipe.usernameSelector = body[@"usernameSelector"];
    }
    if ([body[@"passwordSelector"] isKindOfClass:[NSString class]] && recipe.passwordSelector.length == 0) {
        recipe.passwordSelector = body[@"passwordSelector"];
    }
    if ([body[@"phoneSelector"] isKindOfClass:[NSString class]] && recipe.phoneSelector.length == 0) {
        recipe.phoneSelector = body[@"phoneSelector"];
    }

    LoginCredentials *creds = [self loadOrEmptyCredentialsForRecipeID:recipe.recipeID];
    if (![self applySlot:slot value:value selector:selector label:label toRecipe:recipe credentials:creds]) {
        return NO;
    }
    NSError *error = nil;
    if (![self commitRecipe:recipe credentials:creds error:&error]) {
        [BrowserTransientToast showMessage:error.localizedDescription ?: @"保存失败"
                                  inWindow:self.windowController.window
                                  duration:2.5];
        return NO;
    }
    [BrowserTransientToast showMessage:created ? @"已新建登录配置并保存字段" : @"已保存到登录助手"
                              inWindow:self.windowController.window
                              duration:2.0];
    return YES;
}

- (void)saveWholeFormFromWebView:(WKWebView *)webView
                            body:(NSDictionary *)body
                             url:(NSURL *)url
                            host:(NSString *)host
                      completion:(LoginFieldSaveCompletion)completion {
    NSString *formId = [body[@"formId"] isKindOfClass:[NSString class]] ? body[@"formId"] : @"";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){ try { return window.__meoLoginAssistCollectFormFields(%@); } catch(e) { return []; } })();",
                    [self jsonStringLiteral:formId]];
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        (void)error;
        NSArray *fields = [result isKindOfClass:[NSArray class]] ? (NSArray *)result : @[];
        // 保证至少包含触发保存的当前字段
        if (fields.count == 0 && [body[@"value"] isKindOfClass:[NSString class]]) {
            fields = @[ @{
                @"slot": body[@"slot"] ?: @"",
                @"selector": body[@"selector"] ?: @"",
                @"label": body[@"label"] ?: @"",
                @"value": body[@"value"] ?: @"",
            } ];
        }
        NSDictionary *payload = @{
            @"formId": formId ?: @"",
            @"fields": fields,
            @"usernameSelector": body[@"usernameSelector"] ?: @"",
            @"passwordSelector": body[@"passwordSelector"] ?: @"",
            @"phoneSelector": body[@"phoneSelector"] ?: @"",
            @"submitSelector": body[@"submitSelector"] ?: @"",
            @"href": body[@"href"] ?: @"",
        };
        [strongSelf handleSaveFormMessage:payload fromWebView:webView completion:completion];
    }];
}

- (NSString *)jsonStringLiteral:(NSString *)string {
    // NSJSONSerialization 顶层只能是数组/字典；裸 NSString 会抛异常导致崩溃。
    NSString *safe = string ?: @"";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[safe] options:0 error:&error];
    if (!data || data.length < 2) {
        return @"\"\"";
    }
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayJSON.length < 2) {
        return @"\"\"";
    }
    // ["..."] → "..."
    return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
}

- (void)handleSaveFormMessage:(NSDictionary *)body
                  fromWebView:(WKWebView *)webView
                   completion:(LoginFieldSaveCompletion)completion {
    NSURL *url = [self resolveURL:webView body:body];
    if ([BrowserRiskHostPolicy URLShouldSuppressLoginAssist:url]) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    NSString *host = [self hostKeyForURL:url];
    if (host.length == 0) {
        [BrowserTransientToast showMessage:@"无法保存：缺少主机"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSArray *fields = body[@"fields"];
    if (![fields isKindOfClass:[NSArray class]] || fields.count == 0) {
        [BrowserTransientToast showMessage:@"本表没有可保存的已填字段"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        if (completion) {
            completion(NO);
        }
        return;
    }

    // 若从菜单直接调 saveForm 且尚未确认，再确认一次
    if (!self.promptVisible && body[@"skipConfirm"] == nil) {
        // 来自「保存此字段」sheet 的第二按钮时已确认；带 skipConfirm 或已在 sheet 内。
    }

    BOOL created = NO;
    LoginRecipe *recipe = [self recipeForURL:url host:host createIfNeeded:YES created:&created];
    if (!recipe) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    if ([body[@"submitSelector"] isKindOfClass:[NSString class]] && [(NSString *)body[@"submitSelector"] length] > 0) {
        recipe.submitSelector = body[@"submitSelector"];
    }
    if ([body[@"usernameSelector"] isKindOfClass:[NSString class]] && [(NSString *)body[@"usernameSelector"] length] > 0) {
        recipe.usernameSelector = body[@"usernameSelector"];
    }
    if ([body[@"passwordSelector"] isKindOfClass:[NSString class]] && [(NSString *)body[@"passwordSelector"] length] > 0) {
        recipe.passwordSelector = body[@"passwordSelector"];
    }
    if ([body[@"phoneSelector"] isKindOfClass:[NSString class]] && [(NSString *)body[@"phoneSelector"] length] > 0) {
        recipe.phoneSelector = body[@"phoneSelector"];
    }

    LoginCredentials *creds = [self loadOrEmptyCredentialsForRecipeID:recipe.recipeID];
    NSInteger applied = 0;
    for (id item in fields) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *f = (NSDictionary *)item;
        NSString *slot = f[@"slot"];
        NSString *selector = f[@"selector"];
        NSString *label = f[@"label"];
        NSString *value = f[@"value"];
        if (![slot isKindOfClass:[NSString class]] || [slot isEqualToString:@"otp"]) {
            continue;
        }
        if (![selector isKindOfClass:[NSString class]] || selector.length == 0) {
            continue;
        }
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length == 0) {
            continue;
        }
        if (![label isKindOfClass:[NSString class]]) {
            label = slot;
        }
        if ([self applySlot:slot value:value selector:selector label:label toRecipe:recipe credentials:creds]) {
            applied++;
        }
    }
    if (applied == 0) {
        [BrowserTransientToast showMessage:@"本表没有可保存的已填字段"
                                  inWindow:self.windowController.window
                                  duration:2.0];
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSError *error = nil;
    if (![self commitRecipe:recipe credentials:creds error:&error]) {
        [BrowserTransientToast showMessage:error.localizedDescription ?: @"保存失败"
                                  inWindow:self.windowController.window
                                  duration:2.5];
        if (completion) {
            completion(NO);
        }
        return;
    }
    [BrowserTransientToast showMessage:[NSString stringWithFormat:@"已保存本表 %ld 个字段", (long)applied]
                              inWindow:self.windowController.window
                              duration:2.0];
    if (completion) {
        completion(YES);
    }
}

@end
