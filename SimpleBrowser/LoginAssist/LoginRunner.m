#import "LoginRunner.h"
#import "LoginRecipe.h"

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
    if (!recipe || !webView) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"无法执行登录：页面不可用"}]);
        }
        return;
    }
    if (recipe.usernameSelector.length == 0 || recipe.passwordSelector.length == 0) {
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

    NSString *submitSel = willSubmit ? (recipe.submitSelector ?: @"") : @"";
    BOOL submitByEnter = willSubmit && recipe.submitByEnter;
    [self executeFillInWebView:webView
              usernameSelector:recipe.usernameSelector
              passwordSelector:recipe.passwordSelector
                      username:username
                      password:password
                submitSelector:submitSel
                 submitByEnter:submitByEnter
                  waitTimeoutMs:recipe.waitTimeoutMs
                    completion:completion];
}

+ (void)fillInWebView:(WKWebView *)webView
     usernameSelector:(NSString *)usernameSelector
     passwordSelector:(NSString *)passwordSelector
             username:(NSString *)username
             password:(NSString *)password
       submitSelector:(NSString *)submitSelector
         shouldSubmit:(BOOL)shouldSubmit
           completion:(LoginRunnerCompletion)completion {
    [self executeFillInWebView:webView
              usernameSelector:usernameSelector
              passwordSelector:passwordSelector
                      username:username
                      password:password
                submitSelector:shouldSubmit ? (submitSelector ?: @"") : @""
                 submitByEnter:NO
                  waitTimeoutMs:8000
                    completion:completion];
}

+ (void)executeFillInWebView:(WKWebView *)webView
            usernameSelector:(NSString *)userSel
            passwordSelector:(NSString *)passSel
                    username:(NSString *)username
                    password:(NSString *)password
              submitSelector:(NSString *)submitSel
               submitByEnter:(BOOL)submitByEnter
                waitTimeoutMs:(NSInteger)timeoutMs
                  completion:(LoginRunnerCompletion)completion {
    if (!webView || userSel.length == 0 || passSel.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"LoginRunner"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"无法填充表单"}]);
        }
        return;
    }
    if (timeoutMs <= 0) {
        timeoutMs = 8000;
    }

    NSInteger generation = ++gLoginRunnerGeneration;
    BOOL doSubmit = (submitByEnter || submitSel.length > 0);
    NSString *userJSON = [self jsonStringFromString:username ?: @""];
    NSString *passJSON = [self jsonStringFromString:password ?: @""];
    NSString *userSelJSON = [self jsonStringFromString:userSel];
    NSString *passSelJSON = [self jsonStringFromString:passSel];
    NSString *submitSelJSON = [self jsonStringFromString:submitSel ?: @""];

    NSString *script = [NSString stringWithFormat:
        @"(async function() {\n"
         "  const timeoutMs = %ld;\n"
         "  const userSel = %@;\n"
         "  const passSel = %@;\n"
         "  const submitSel = %@;\n"
         "  const submitByEnter = %@;\n"
         "  const doSubmit = %@;\n"
         "  const username = %@;\n"
         "  const password = %@;\n"
         "  function qs(sel) { try { return document.querySelector(sel); } catch (e) { return null; } }\n"
         "  async function waitFor(sel) {\n"
         "    const start = Date.now();\n"
         "    while (Date.now() - start < timeoutMs) {\n"
         "      const el = qs(sel);\n"
         "      if (el) { return el; }\n"
         "      await new Promise(r => setTimeout(r, 100));\n"
         "    }\n"
         "    throw new Error('等待元素超时: ' + sel);\n"
         "  }\n"
         "  function setValue(el, value) {\n"
         "    el.focus();\n"
         "    const proto = window.HTMLInputElement.prototype;\n"
         "    const setter = Object.getOwnPropertyDescriptor(proto, 'value');\n"
         "    if (setter && setter.set) { setter.set.call(el, value); }\n"
         "    else { el.value = value; }\n"
         "    el.dispatchEvent(new Event('input', { bubbles: true }));\n"
         "    el.dispatchEvent(new Event('change', { bubbles: true }));\n"
         "  }\n"
         "  function pressEnter(el) {\n"
         "    el.focus();\n"
         "    const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };\n"
         "    el.dispatchEvent(new KeyboardEvent('keydown', opts));\n"
         "    el.dispatchEvent(new KeyboardEvent('keypress', opts));\n"
         "    el.dispatchEvent(new KeyboardEvent('keyup', opts));\n"
         "    if (el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }\n"
         "  }\n"
         "  const userEl = await waitFor(userSel);\n"
         "  const passEl = await waitFor(passSel);\n"
         "  setValue(userEl, username);\n"
         "  setValue(passEl, password);\n"
         "  await new Promise(r => setTimeout(r, 80));\n"
         "  if (doSubmit) {\n"
         "    if (submitByEnter) { pressEnter(passEl); }\n"
         "    else {\n"
         "      const btn = await waitFor(submitSel);\n"
         "      btn.click();\n"
         "    }\n"
         "  }\n"
         "  return 'ok';\n"
         "})()",
        (long)timeoutMs,
        userSelJSON,
        passSelJSON,
        submitSelJSON,
        submitByEnter ? @"true" : @"false",
        doSubmit ? @"true" : @"false",
        userJSON,
        passJSON];

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *evalError) {
        (void)result;
        if (generation != gLoginRunnerGeneration) {
            return;
        }
        if (evalError) {
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
    }];
}

+ (NSString *)jsonStringFromString:(NSString *)string {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[ string ?: @"" ] options:0 error:nil];
    NSString *arrayJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayJSON.length < 2) {
        return @"\"\"";
    }
    return [arrayJSON substringWithRange:NSMakeRange(1, arrayJSON.length - 2)];
}

@end
