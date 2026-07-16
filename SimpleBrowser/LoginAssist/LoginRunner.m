#import "LoginRunner.h"
#import "LoginRecipe.h"
#import "LoginCredentialStore.h"
#import "OTPInbox.h"

static NSInteger gLoginRunnerGeneration = 0;

@implementation LoginRunner

+ (void)cancelAll {
    gLoginRunnerGeneration += 1;
    [[OTPInbox sharedInbox] cancelWait];
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

    BOOL needsOTP = [recipe requiresOTPWait];
    BOOL smsOnly = [recipe.mode isEqualToString:LoginRecipeModeSMSOTP];
    BOOL hasUserPass = recipe.usernameSelector.length > 0 && recipe.passwordSelector.length > 0;
    if (!needsOTP && !hasUserPass) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"请先配置用户名与密码选择器"}]);
        }
        return;
    }
    if (needsOTP && recipe.otpSelector.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:6
                                           userInfo:@{NSLocalizedDescriptionKey: @"短信模式请配置验证码选择器"}]);
        }
        return;
    }
    if (smsOnly && recipe.phoneSelector.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:8
                                           userInfo:@{NSLocalizedDescriptionKey: @"短信登录请配置手机号选择器"}]);
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

    // Phase 1: fill username/password/phone + optional send-code click（不提交登录）
    [self evaluateStepsInWebView:webView
                           recipe:recipe
                      credentials:credentials
                        fillOTP:nil
                       doSubmit:NO
                   waitTimeoutMs:waitTimeout
                      generation:generation
                      completion:^(BOOL ok, NSError *error) {
        if (generation != gLoginRunnerGeneration) {
            return;
        }
        if (!ok) {
            finish(NO, error);
            return;
        }
        if (!needsOTP) {
            if (!willSubmit) {
                finish(YES, nil);
                return;
            }
            [self evaluateStepsInWebView:webView
                                   recipe:recipe
                              credentials:credentials
                                fillOTP:nil
                               doSubmit:YES
                           waitTimeoutMs:waitTimeout
                              generation:generation
                              completion:finish];
            return;
        }

        NSTimeInterval otpTimeout = recipe.otpMaxWaitMs > 0 ? (recipe.otpMaxWaitMs / 1000.0) : 120.0;
        [[OTPInbox sharedInbox] waitForCodeWithTimeout:otpTimeout completion:^(NSString *code, NSError *waitError) {
            if (generation != gLoginRunnerGeneration) {
                return;
            }
            if (!code) {
                finish(NO, waitError ?: [NSError errorWithDomain:@"LoginRunner"
                                                            code:7
                                                        userInfo:@{NSLocalizedDescriptionKey: @"等待验证码超时"}]);
                return;
            }
            [self evaluateStepsInWebView:webView
                                   recipe:recipe
                              credentials:credentials
                                fillOTP:code
                               doSubmit:willSubmit
                           waitTimeoutMs:waitTimeout
                              generation:generation
                              completion:finish];
        }];
    }];
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
                        fillOTP:nil
                       doSubmit:shouldSubmit
                   waitTimeoutMs:8000
                      generation:generation
                      completion:completion];
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
         "const phoneSel = phoneSelArg;\n"
         "const otpSel = otpSelArg;\n"
         "const sendSel = sendSelArg;\n"
         "const submitSel = submitSelArg;\n"
         "const submitByEnter = submitByEnterArg;\n"
         "const doSubmit = doSubmitArg;\n"
         "const fillPhase = fillPhaseArg;\n"
         "const skipUserPass = skipUserPassArg;\n"
         "const username = usernameArg;\n"
         "const password = passwordArg;\n"
         "const phone = phoneArg;\n"
         "const otp = otpArg;\n"
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
         "function pressEnter(el) {\n"
         "  el.focus();\n"
         "  const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };\n"
         "  el.dispatchEvent(new KeyboardEvent('keydown', opts));\n"
         "  el.dispatchEvent(new KeyboardEvent('keypress', opts));\n"
         "  el.dispatchEvent(new KeyboardEvent('keyup', opts));\n"
         "  if (el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }\n"
         "}\n"
         "if (fillPhase === 'pre') {\n"
         "  if (!skipUserPass) {\n"
         "    if (userSel) { const userEl = await waitFor(userSel); setValue(userEl, username); }\n"
         "    if (passSel) { const passEl = await waitFor(passSel); setValue(passEl, password); }\n"
         "  }\n"
         "  if (phoneSel) { const phoneEl = await waitFor(phoneSel); setValue(phoneEl, phone); }\n"
         "  if (sendSel) { const sendBtn = await waitFor(sendSel); sendBtn.click(); }\n"
         "  await new Promise(r => setTimeout(r, 80));\n"
         "  return 'pre-ok';\n"
         "}\n"
         "if (fillPhase === 'otp') {\n"
         "  const otpEl = await waitFor(otpSel);\n"
         "  setValue(otpEl, otp);\n"
         "  await new Promise(r => setTimeout(r, 80));\n"
         "  if (doSubmit) {\n"
         "    if (submitByEnter) { pressEnter(otpEl); }\n"
         "    else {\n"
         "      const btn = await waitFor(submitSel);\n"
         "      btn.click();\n"
         "    }\n"
         "  }\n"
         "  return 'otp-ok';\n"
         "}\n"
         "// password-only submit\n"
         "let passEl = null;\n"
         "if (userSel) { const userEl = await waitFor(userSel); setValue(userEl, username); }\n"
         "if (passSel) { passEl = await waitFor(passSel); setValue(passEl, password); }\n"
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
                        fillOTP:(NSString *)otp
                       doSubmit:(BOOL)doSubmit
                   waitTimeoutMs:(NSInteger)timeoutMs
                      generation:(NSInteger)generation
                      completion:(LoginRunnerCompletion)completion {
    NSString *fillPhase = @"password";
    if ([recipe requiresOTPWait]) {
        fillPhase = (otp.length > 0) ? @"otp" : @"pre";
    } else if (!doSubmit) {
        // password fillOnly
        fillPhase = @"password";
    }

    BOOL submitByEnter = recipe.submitByEnter;
    NSString *submitSel = doSubmit ? (recipe.submitSelector ?: @"") : @"";
    BOOL skipUserPass = [recipe.mode isEqualToString:LoginRecipeModeSMSOTP];
    NSString *userSel = skipUserPass ? @"" : (recipe.usernameSelector ?: @"");
    NSString *passSel = skipUserPass ? @"" : (recipe.passwordSelector ?: @"");

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

    NSDictionary *args = @{
        @"timeoutMsArg": @(timeoutMs),
        @"userSelArg": userSel,
        @"passSelArg": passSel,
        @"phoneSelArg": recipe.phoneSelector ?: @"",
        @"otpSelArg": recipe.otpSelector ?: @"",
        @"sendSelArg": recipe.sendCodeSelector ?: @"",
        @"submitSelArg": submitSel ?: @"",
        @"submitByEnterArg": @(submitByEnter),
        @"doSubmitArg": @(doSubmit),
        @"fillPhaseArg": fillPhase,
        @"skipUserPassArg": @(skipUserPass),
        @"usernameArg": credentials.username ?: @"",
        @"passwordArg": credentials.password ?: @"",
        @"phoneArg": credentials.phone ?: @"",
        @"otpArg": otp ?: @"",
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
         "  const phoneSelArg = a.phoneSelArg;\n"
         "  const otpSelArg = a.otpSelArg;\n"
         "  const sendSelArg = a.sendSelArg;\n"
         "  const submitSelArg = a.submitSelArg;\n"
         "  const submitByEnterArg = a.submitByEnterArg;\n"
         "  const doSubmitArg = a.doSubmitArg;\n"
         "  const fillPhaseArg = a.fillPhaseArg;\n"
         "  const skipUserPassArg = a.skipUserPassArg;\n"
         "  const usernameArg = a.usernameArg;\n"
         "  const passwordArg = a.passwordArg;\n"
         "  const phoneArg = a.phoneArg;\n"
         "  const otpArg = a.otpArg;\n"
         "  %@\n"
         "})()",
        argsJSON,
        [self asyncStepsScript]];
    [webView evaluateJavaScript:script completionHandler:handleResult];
}

@end
