#import "LoginRunner.h"
#import "LoginRecipe.h"
#import "LoginCredentialStore.h"

static NSInteger gLoginRunnerGeneration = 0;

@implementation LoginRunner

+ (void)cancelAll {
    gLoginRunnerGeneration += 1;
}

+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
         username:(NSString *)username
         password:(NSString *)password
       completion:(LoginRunnerCompletion)completion {
    [self runRecipe:recipe
          inWebView:webView
           username:username
           password:password
           fillOnly:NO
         completion:completion];
}

+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
         username:(NSString *)username
         password:(NSString *)password
         fillOnly:(BOOL)fillOnly
       completion:(LoginRunnerCompletion)completion {
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = username ?: @"";
    credentials.password = password ?: @"";
    [self runRecipe:recipe
          inWebView:webView
        credentials:credentials
           fillOnly:fillOnly
         completion:completion];
}

+ (void)runRecipe:(LoginRecipe *)recipe
        inWebView:(WKWebView *)webView
      credentials:(LoginCredentials *)credentials
         fillOnly:(BOOL)fillOnly
       completion:(LoginRunnerCompletion)completion {
    if (!recipe || !webView) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"无法执行登录：页面不可用"}]);
        }
        return;
    }

    BOOL hasUserPass = recipe.usernameSelector.length > 0 && recipe.passwordSelector.length > 0;
    if (!hasUserPass) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"请先配置用户名与密码选择器"}]);
        }
        return;
    }

    BOOL willSubmit = !fillOnly;
    if (willSubmit && !recipe.submitByEnter && recipe.submitSelector.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:3
                                           userInfo:@{NSLocalizedDescriptionKey: @"请配置提交按钮选择器，或改为回车提交"}]);
        }
        return;
    }

    NSInteger generation = ++gLoginRunnerGeneration;
    NSInteger waitTimeout = recipe.waitTimeoutMs > 0 ? recipe.waitTimeoutMs : 8000;

    void (^finish)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        if (generation != gLoginRunnerGeneration) {
            return;
        }
        if (completion) {
            completion(success, error);
        }
    };

    if (!willSubmit) {
        [self evaluateStepsInWebView:webView
                               recipe:recipe
                          credentials:credentials
                             doSubmit:NO
                         waitTimeoutMs:waitTimeout
                            generation:generation
                            completion:finish];
        return;
    }

    [self evaluateStepsInWebView:webView
                           recipe:recipe
                      credentials:credentials
                         doSubmit:YES
                     waitTimeoutMs:waitTimeout
                        generation:generation
                        completion:finish];
}

+ (void)fillInWebView:(WKWebView *)webView
     usernameSelector:(NSString *)usernameSelector
     passwordSelector:(NSString *)passwordSelector
             username:(NSString *)username
             password:(NSString *)password
       submitSelector:(NSString *)submitSelector
         shouldSubmit:(BOOL)shouldSubmit
           completion:(LoginRunnerCompletion)completion {
    LoginRecipe *tmp = [LoginRecipe recipeWithHost:@"tmp" title:@"tmp"];
    tmp.usernameSelector = usernameSelector;
    tmp.passwordSelector = passwordSelector;
    tmp.submitSelector = submitSelector;
    tmp.submitByEnter = NO;
    tmp.waitTimeoutMs = 8000;
    LoginCredentials *credentials = [[LoginCredentials alloc] init];
    credentials.username = username ?: @"";
    credentials.password = password ?: @"";
    NSInteger generation = ++gLoginRunnerGeneration;
    [self evaluateStepsInWebView:webView
                           recipe:tmp
                      credentials:credentials
                         doSubmit:shouldSubmit
                     waitTimeoutMs:8000
                        generation:generation
                        completion:completion];
}

+ (void)fillSelector:(NSString *)selector
               value:(NSString *)value
           inWebView:(WKWebView *)webView
          completion:(LoginRunnerCompletion)completion {
    if (!webView || selector.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:10
                                           userInfo:@{NSLocalizedDescriptionKey: @"缺少页面或选择器"}]);
        }
        return;
    }
    NSDictionary *payload = @{
        @"selector": selector ?: @"",
        @"value": value ?: @"",
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (json.length == 0) {
        if (completion) {
            completion(NO, jsonError ?: [NSError errorWithDomain:@"LoginRunner"
                                                            code:12
                                                        userInfo:@{NSLocalizedDescriptionKey: @"无法编码填入参数"}]);
        }
        return;
    }
    NSString *script = [@[
        @"(function(){",
        @"  var p = ", json, @";",
        @"  var sel = p.selector || '';",
        @"  var value = (p.value != null) ? String(p.value) : '';",
        @"  function tryFill(w, fromParent) {",
        @"    try {",
        @"      if (w && w.__meoLoginAssistFillSelector) {",
        @"        return w.__meoLoginAssistFillSelector(sel, value, !!fromParent);",
        @"      }",
        @"    } catch (e) {}",
        @"    try {",
        @"      var el = w.document.querySelector(sel);",
        @"      if (!el) return 'missing';",
        @"      el.focus();",
        @"      var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;",
        @"      var d = Object.getOwnPropertyDescriptor(proto, 'value');",
        @"      if (d && d.set) d.set.call(el, value); else el.value = value;",
        @"      el.dispatchEvent(new Event('input', { bubbles: true }));",
        @"      el.dispatchEvent(new Event('change', { bubbles: true }));",
        @"      return 'ok';",
        @"    } catch (e2) { return 'error'; }",
        @"  }",
        @"  var r = tryFill(window, false);",
        @"  if (r === 'ok') return 'ok';",
        @"  try {",
        @"    for (var i = 0; i < window.frames.length; i++) {",
        @"      r = tryFill(window.frames[i], true);",
        @"      if (r === 'ok') return 'ok';",
        @"    }",
        @"  } catch (e3) {}",
        @"  return r || 'missing';",
        @"})();"
    ] componentsJoinedByString:@""];
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        BOOL ok = [result isKindOfClass:[NSString class]] && [result isEqualToString:@"ok"];
        if (completion) {
            if (ok) {
                completion(YES, nil);
            } else {
                completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                                   code:11
                                               userInfo:@{NSLocalizedDescriptionKey: @"未找到字段，请在侧栏修正选择器"}]);
            }
        }
    }];
}

+ (BOOL)isBenignJavaScriptBridgeError:(NSError *)error {
    if (!error) {
        return NO;
    }
    NSMutableString *blob = [NSMutableString string];
    if (error.localizedDescription.length > 0) {
        [blob appendString:error.localizedDescription];
    }
    id jsMessage = error.userInfo[@"WKJavaScriptExceptionMessage"];
    if ([jsMessage isKindOfClass:[NSString class]]) {
        [blob appendFormat:@" %@", jsMessage];
    }
    id underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:[NSError class]]) {
        NSString *u = [(NSError *)underlying localizedDescription];
        if (u.length > 0) {
            [blob appendFormat:@" %@", u];
        }
    }
    NSString *lower = blob.lowercaseString;
    return [lower containsString:@"unsupported type"]
        || [lower containsString:@"returned a result of an unsupported type"]
        || [lower containsString:@"script execution cancelled"]
        || [lower containsString:@"javaScript execution resulted in a failure"]
        || error.code == WKErrorJavaScriptResultTypeIsUnsupported;
}

+ (NSString *)asyncStepsScript {
    return
        @"const timeoutMs = timeoutMsArg;\n"
         "const userSel = userSelArg;\n"
         "const passSel = passSelArg;\n"
         "const submitSel = submitSelArg;\n"
         "const submitByEnter = submitByEnterArg;\n"
         "const doSubmit = doSubmitArg;\n"
         "const username = usernameArg;\n"
         "const password = passwordArg;\n"
         "const extraFields = Array.isArray(extraFieldsArg) ? extraFieldsArg : [];\n"
         "function qs(sel) { try { return document.querySelector(sel); } catch (e) { return null; } }\n"
         "async function waitFor(sel) {\n"
         "  if (!sel) return null;\n"
         "  const start = Date.now();\n"
         "  while (Date.now() - start < timeoutMs) {\n"
         "    const el = qs(sel);\n"
         "    if (el) { return el; }\n"
         "    await new Promise(r => setTimeout(r, 100));\n"
         "  }\n"
         "  throw new Error('等待元素超时: ' + sel);\n"
         "}\n"
         "function setValue(el, value) {\n"
         "  if (!el) return;\n"
         "  el.focus();\n"
         "  const proto = window.HTMLInputElement.prototype;\n"
         "  const setter = Object.getOwnPropertyDescriptor(proto, 'value');\n"
         "  if (setter && setter.set) { setter.set.call(el, value); }\n"
         "  else { el.value = value; }\n"
         "  el.dispatchEvent(new Event('input', { bubbles: true }));\n"
         "  el.dispatchEvent(new Event('change', { bubbles: true }));\n"
         "}\n"
         "async function fillExtraFieldsSoft() {\n"
         "  for (const f of extraFields) {\n"
         "    const sel = f && f.selector ? String(f.selector) : '';\n"
         "    if (!sel) continue;\n"
         "    try {\n"
         "      const el = await waitFor(sel);\n"
         "      setValue(el, f.value != null ? String(f.value) : '');\n"
         "    } catch (e) { /* 软失败：继续后续字段 */ }\n"
         "  }\n"
         "}\n"
         "function pressEnter(el) {\n"
         "  el.focus();\n"
         "  const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };\n"
         "  el.dispatchEvent(new KeyboardEvent('keydown', opts));\n"
         "  el.dispatchEvent(new KeyboardEvent('keypress', opts));\n"
         "  el.dispatchEvent(new KeyboardEvent('keyup', opts));\n"
         "  if (el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }\n"
         "}\n"
         "let passEl = null;\n"
         "if (userSel) { const userEl = await waitFor(userSel); setValue(userEl, username); }\n"
         "if (passSel) { passEl = await waitFor(passSel); setValue(passEl, password); }\n"
         "await fillExtraFieldsSoft();\n"
         "await new Promise(r => setTimeout(r, 80));\n"
         "if (doSubmit) {\n"
         "  if (submitByEnter && passEl) { pressEnter(passEl); }\n"
         "  else {\n"
         "    const btn = await waitFor(submitSel);\n"
         "    btn.click();\n"
         "  }\n"
         "}\n"
         "return 'ok';\n";
}

+ (void)evaluateStepsInWebView:(WKWebView *)webView
                         recipe:(LoginRecipe *)recipe
                    credentials:(LoginCredentials *)credentials
                       doSubmit:(BOOL)doSubmit
                   waitTimeoutMs:(NSInteger)timeoutMs
                      generation:(NSInteger)generation
                      completion:(LoginRunnerCompletion)completion {
    BOOL submitByEnter = recipe.submitByEnter;
    NSString *submitSel = doSubmit ? (recipe.submitSelector ?: @"") : @"";
    NSString *userSel = recipe.usernameSelector ?: @"";
    NSString *passSel = recipe.passwordSelector ?: @"";

    void (^handleResult)(id, NSError *) = ^(id result, NSError *evalError) {
        (void)result;
        if (generation != gLoginRunnerGeneration) {
            return;
        }
        if (evalError) {
            if ([self isBenignJavaScriptBridgeError:evalError]) {
                if (completion) {
                    completion(YES, nil);
                }
                return;
            }
            NSString *message = evalError.localizedDescription ?: @"执行失败";
            NSString *jsMessage = evalError.userInfo[@"WKJavaScriptExceptionMessage"];
            if ([jsMessage isKindOfClass:[NSString class]] && jsMessage.length > 0) {
                message = jsMessage;
            }
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                                   code:4
                                               userInfo:@{NSLocalizedDescriptionKey: message}]);
            }
            return;
        }
        if (completion) {
            completion(YES, nil);
        }
    };

    NSMutableArray<NSDictionary *> *extraPayload = [NSMutableArray array];
    for (LoginRecipeExtraField *field in [recipe enabledExtraFields]) {
        [extraPayload addObject:@{
            @"selector": field.selector ?: @"",
            @"value": field.value ?: @"",
        }];
    }

    NSDictionary *args = @{
        @"timeoutMsArg": @(timeoutMs),
        @"userSelArg": userSel,
        @"passSelArg": passSel,
        @"submitSelArg": submitSel ?: @"",
        @"submitByEnterArg": @(submitByEnter),
        @"doSubmitArg": @(doSubmit),
        @"usernameArg": credentials.username ?: @"",
        @"passwordArg": credentials.password ?: @"",
        @"extraFieldsArg": extraPayload,
    };

    if (@available(macOS 11.0, *)) {
        [webView callAsyncJavaScript:[self asyncStepsScript]
                           arguments:args
                             inFrame:nil
                      inContentWorld:[WKContentWorld pageWorld]
                   completionHandler:handleResult];
        return;
    }

    NSData *argsData = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    NSString *argsJSON = [[NSString alloc] initWithData:argsData encoding:NSUTF8StringEncoding] ?: @"{}";
    NSString *script = [NSString stringWithFormat:
        @"(async function() {\n"
         "  const a = %@;\n"
         "  const timeoutMsArg = a.timeoutMsArg;\n"
         "  const userSelArg = a.userSelArg;\n"
         "  const passSelArg = a.passSelArg;\n"
         "  const submitSelArg = a.submitSelArg;\n"
         "  const submitByEnterArg = a.submitByEnterArg;\n"
         "  const doSubmitArg = a.doSubmitArg;\n"
         "  const usernameArg = a.usernameArg;\n"
         "  const passwordArg = a.passwordArg;\n"
         "  const extraFieldsArg = a.extraFieldsArg;\n"
         "  %@\n"
         "})()",
        argsJSON,
        [self asyncStepsScript]];
    [webView evaluateJavaScript:script completionHandler:handleResult];
}

@end
