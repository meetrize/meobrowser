#import "FormMemoRunner.h"
#import "FormMemo.h"

@implementation FormMemoFillFailure
@end

@implementation FormMemoFillResult

- (BOOL)allSucceeded {
    return self.attemptedCount > 0 && self.failures.count == 0;
}

- (BOOL)anySucceeded {
    return self.successCount > 0;
}

- (NSString *)summaryMessage {
    if (self.attemptedCount == 0) {
        return @"没有可填入的字段（请检查选择器是否已配置）。";
    }
    if (self.allSucceeded) {
        return [NSString stringWithFormat:@"已填入 %lu 项。", (unsigned long)self.successCount];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (FormMemoFillFailure *failure in self.failures) {
        NSString *name = failure.label.length > 0 ? failure.label : @"未命名字段";
        [names addObject:name];
    }
    NSString *failed = [names componentsJoinedByString:@"、"];
    if (self.anySucceeded) {
        return [NSString stringWithFormat:@"已填入 %lu 项；失败：%@（选择器未找到或类型不支持）。",
                (unsigned long)self.successCount, failed];
    }
    return [NSString stringWithFormat:@"未找到任何目标字段。失败：%@。", failed];
}

@end

static NSInteger gFormMemoRunnerGeneration = 0;

@implementation FormMemoRunner

+ (void)cancelAll {
    gFormMemoRunnerGeneration += 1;
}

+ (NSString *)fillScript {
    return
        @"const timeoutMs = timeoutMsArg;\n"
         "const fields = fieldsArg || [];\n"
         "function qs(sel) { try { return document.querySelector(sel); } catch (e) { return null; } }\n"
         "async function waitFor(sel) {\n"
         "  if (!sel) return null;\n"
         "  const start = Date.now();\n"
         "  while (Date.now() - start < timeoutMs) {\n"
         "    const el = qs(sel);\n"
         "    if (el) { return el; }\n"
         "    await new Promise(r => setTimeout(r, 100));\n"
         "  }\n"
         "  return null;\n"
         "}\n"
         "function setValue(el, value) {\n"
         "  if (!el) return false;\n"
         "  const tag = (el.tagName || '').toUpperCase();\n"
         "  if (tag !== 'INPUT' && tag !== 'TEXTAREA') {\n"
         "    return false;\n"
         "  }\n"
         "  el.focus();\n"
         "  const proto = tag === 'TEXTAREA'\n"
         "    ? window.HTMLTextAreaElement.prototype\n"
         "    : window.HTMLInputElement.prototype;\n"
         "  const setter = Object.getOwnPropertyDescriptor(proto, 'value');\n"
         "  if (setter && setter.set) { setter.set.call(el, value); }\n"
         "  else { el.value = value; }\n"
         "  el.dispatchEvent(new Event('input', { bubbles: true }));\n"
         "  el.dispatchEvent(new Event('change', { bubbles: true }));\n"
         "  return true;\n"
         "}\n"
         "const results = [];\n"
         "for (const field of fields) {\n"
         "  const fieldID = field.fieldID || '';\n"
         "  const label = field.label || '';\n"
         "  const selector = field.selector || '';\n"
         "  const value = field.value == null ? '' : String(field.value);\n"
         "  if (!selector) {\n"
         "    results.push({ fieldID, label, ok: false, reason: '缺少选择器' });\n"
         "    continue;\n"
         "  }\n"
         "  const el = await waitFor(selector);\n"
         "  if (!el) {\n"
         "    results.push({ fieldID, label, ok: false, reason: '选择器未找到' });\n"
         "    continue;\n"
         "  }\n"
         "  const ok = setValue(el, value);\n"
         "  if (!ok) {\n"
         "    results.push({ fieldID, label, ok: false, reason: '仅支持 input/textarea' });\n"
         "    continue;\n"
         "  }\n"
         "  results.push({ fieldID, label, ok: true, reason: '' });\n"
         "}\n"
         "await new Promise(r => setTimeout(r, 40));\n"
         "return results;\n";
}

+ (BOOL)isBenignJavaScriptBridgeError:(NSError *)error {
    if (!error) {
        return NO;
    }
    NSString *desc = error.localizedDescription ?: @"";
    if ([desc containsString:@"JavaScript execution returned a result of an unsupported type"] ||
        [desc containsString:@"unsupported type"]) {
        return YES;
    }
    return NO;
}

+ (void)fillFields:(NSArray<FormMemoField *> *)fields
         inWebView:(WKWebView *)webView
       waitTimeout:(NSInteger)timeoutMs
        completion:(FormMemoRunnerCompletion)completion {
    if (!webView) {
        FormMemoFillResult *result = [[FormMemoFillResult alloc] init];
        result.attemptedCount = 0;
        result.successCount = 0;
        result.failures = @[];
        if (completion) {
            completion(result);
        }
        return;
    }

    NSInteger generation = ++gFormMemoRunnerGeneration;
    NSInteger timeout = timeoutMs > 0 ? timeoutMs : 8000;

    NSMutableArray *payload = [NSMutableArray array];
    for (FormMemoField *field in fields) {
        if (!field.enabled) {
            continue;
        }
        [payload addObject:@{
            @"fieldID": field.fieldID ?: @"",
            @"label": field.label ?: @"",
            @"selector": field.selector ?: @"",
            @"value": field.value ?: @"",
        }];
    }

    void (^finishWithRaw)(id) = ^(id raw) {
        if (generation != gFormMemoRunnerGeneration) {
            return;
        }
        FormMemoFillResult *result = [[FormMemoFillResult alloc] init];
        NSMutableArray<FormMemoFillFailure *> *failures = [NSMutableArray array];
        NSUInteger success = 0;
        NSArray *rows = [raw isKindOfClass:[NSArray class]] ? raw : @[];
        result.attemptedCount = rows.count > 0 ? rows.count : payload.count;
        for (id row in rows) {
            if (![row isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *dict = (NSDictionary *)row;
            BOOL ok = [dict[@"ok"] boolValue];
            if (ok) {
                success += 1;
                continue;
            }
            FormMemoFillFailure *failure = [[FormMemoFillFailure alloc] init];
            failure.fieldID = [dict[@"fieldID"] isKindOfClass:[NSString class]] ? dict[@"fieldID"] : @"";
            failure.label = [dict[@"label"] isKindOfClass:[NSString class]] ? dict[@"label"] : @"";
            failure.reason = [dict[@"reason"] isKindOfClass:[NSString class]] ? dict[@"reason"] : @"失败";
            [failures addObject:failure];
        }
        if (rows.count == 0 && payload.count > 0) {
            // 脚本无结果时视为全部失败，避免 silent success。
            for (NSDictionary *item in payload) {
                FormMemoFillFailure *failure = [[FormMemoFillFailure alloc] init];
                failure.fieldID = item[@"fieldID"] ?: @"";
                failure.label = item[@"label"] ?: @"";
                failure.reason = @"执行无结果";
                [failures addObject:failure];
            }
            result.attemptedCount = payload.count;
        }
        result.successCount = success;
        result.failures = failures;
        if (completion) {
            completion(result);
        }
    };

    void (^handleResult)(id, NSError *) = ^(id jsResult, NSError *evalError) {
        if (generation != gFormMemoRunnerGeneration) {
            return;
        }
        if (evalError && ![self isBenignJavaScriptBridgeError:evalError]) {
            FormMemoFillResult *result = [[FormMemoFillResult alloc] init];
            result.attemptedCount = payload.count;
            result.successCount = 0;
            NSMutableArray<FormMemoFillFailure *> *failures = [NSMutableArray array];
            for (NSDictionary *item in payload) {
                FormMemoFillFailure *failure = [[FormMemoFillFailure alloc] init];
                failure.fieldID = item[@"fieldID"] ?: @"";
                failure.label = item[@"label"] ?: @"";
                NSString *jsMessage = evalError.userInfo[@"WKJavaScriptExceptionMessage"];
                failure.reason = ([jsMessage isKindOfClass:[NSString class]] && jsMessage.length > 0)
                    ? jsMessage
                    : (evalError.localizedDescription ?: @"执行失败");
                [failures addObject:failure];
            }
            result.failures = failures;
            if (completion) {
                completion(result);
            }
            return;
        }
        finishWithRaw(jsResult);
    };

    NSDictionary *args = @{
        @"timeoutMsArg": @(timeout),
        @"fieldsArg": payload,
    };

    if (@available(macOS 11.0, *)) {
        [webView callAsyncJavaScript:[self fillScript]
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
         "  const fieldsArg = a.fieldsArg;\n"
         "  %@\n"
         "})()",
        argsJSON,
        [self fillScript]];
    [webView evaluateJavaScript:script completionHandler:handleResult];
}

@end
