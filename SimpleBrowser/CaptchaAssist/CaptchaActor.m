#import "CaptchaActor.h"

@implementation CaptchaActor

+ (NSString *)escapedJSString:(NSString *)s {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
}

+ (void)fillText:(NSString *)text
    inputSelector:(NSString *)inputSelector
        inWebView:(WKWebView *)webView
       completion:(CaptchaActorCompletion)completion {
    if (!webView || inputSelector.length == 0 || text.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"CaptchaActor"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"缺少 WebView、选择器或文本"}]);
        }
        return;
    }

    NSString *sel = [self escapedJSString:inputSelector];
    NSString *val = [self escapedJSString:text];
    NSString *js = [NSString stringWithFormat:
        @"(function() {\n"
         "  function qs(s) { try { return document.querySelector(s); } catch (e) { return null; } }\n"
         "  const el = qs('%@');\n"
         "  if (!el) return { ok: false, error: '未找到输入框' };\n"
         "  el.focus();\n"
         "  const proto = window.HTMLInputElement && window.HTMLInputElement.prototype;\n"
         "  const setter = proto && Object.getOwnPropertyDescriptor(proto, 'value');\n"
         "  if (setter && setter.set) { setter.set.call(el, '%@'); }\n"
         "  else { el.value = '%@'; }\n"
         "  el.dispatchEvent(new Event('input', { bubbles: true }));\n"
         "  el.dispatchEvent(new Event('change', { bubbles: true }));\n"
         "  return { ok: true, value: el.value };\n"
         "})();",
        sel, val, val];

    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)result;
            if ([dict[@"ok"] boolValue]) {
                if (completion) {
                    completion(YES, nil);
                }
                return;
            }
            NSString *msg = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : @"填入失败";
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"CaptchaActor" code:2 userInfo:@{NSLocalizedDescriptionKey: msg}]);
            }
            return;
        }
        if (completion) {
            completion(YES, nil);
        }
    }];
}

+ (void)readValueForSelector:(NSString *)selector
                   inWebView:(WKWebView *)webView
                  completion:(void (^)(NSString *, NSError *))completion {
    if (!webView || selector.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"CaptchaActor" code:3 userInfo:@{NSLocalizedDescriptionKey: @"缺少参数"}]);
        }
        return;
    }
    NSString *sel = [self escapedJSString:selector];
    NSString *js = [NSString stringWithFormat:
        @"(function() {\n"
         "  try {\n"
         "    const el = document.querySelector('%@');\n"
         "    if (!el) return null;\n"
         "    return (el.value || '').trim();\n"
         "  } catch (e) { return null; }\n"
         "})();", sel];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        if ([result isKindOfClass:[NSString class]]) {
            if (completion) {
                completion((NSString *)result, nil);
            }
            return;
        }
        if (completion) {
            completion(@"", nil);
        }
    }];
}

+ (void)extractMathTextNearSelector:(NSString *)containerSelector
                          inWebView:(WKWebView *)webView
                         completion:(void (^)(NSString *, NSError *))completion {
    NSString *container = containerSelector.length > 0 ? [self escapedJSString:containerSelector] : @"[data-meo-captcha=\"math\"]";
    NSString *js = [NSString stringWithFormat:
        @"(function() {\n"
         "  try {\n"
         "    const root = document.querySelector('%@') || document.querySelector('[data-meo-captcha=\"math\"]');\n"
         "    if (!root) return null;\n"
         "    const t = (root.innerText || root.textContent || '').replace(/\\s+/g, ' ').trim();\n"
         "    return t;\n"
         "  } catch (e) { return null; }\n"
         "})();", container];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        if ([result isKindOfClass:[NSString class]] && [(NSString *)result length] > 0) {
            if (completion) {
                completion((NSString *)result, nil);
            }
            return;
        }
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"CaptchaActor" code:4 userInfo:@{NSLocalizedDescriptionKey: @"未找到算术题文本"}]);
        }
    }];
}

+ (void)exportImageDataURLForSelector:(NSString *)imageSelector
                            inWebView:(WKWebView *)webView
                           completion:(void (^)(NSString *, NSError *))completion {
    if (!webView || imageSelector.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"CaptchaActor" code:5 userInfo:@{NSLocalizedDescriptionKey: @"缺少图片选择器"}]);
        }
        return;
    }
    NSString *sel = [self escapedJSString:imageSelector];
    NSString *js = [NSString stringWithFormat:
        @"(function() {\n"
         "  try {\n"
         "    const img = document.querySelector('%@');\n"
         "    if (!img) return { ok: false, error: '未找到验证码图片' };\n"
         "    if (img.src && img.src.indexOf('data:') === 0) return { ok: true, dataURL: img.src };\n"
         "    const c = document.createElement('canvas');\n"
         "    const w = img.naturalWidth || img.width || 120;\n"
         "    const h = img.naturalHeight || img.height || 40;\n"
         "    c.width = w; c.height = h;\n"
         "    const ctx = c.getContext('2d');\n"
         "    ctx.drawImage(img, 0, 0, w, h);\n"
         "    return { ok: true, dataURL: c.toDataURL('image/png') };\n"
         "  } catch (e) { return { ok: false, error: String(e) }; }\n"
         "})();", sel];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)result;
            if ([dict[@"ok"] boolValue] && [dict[@"dataURL"] isKindOfClass:[NSString class]]) {
                if (completion) {
                    completion(dict[@"dataURL"], nil);
                }
                return;
            }
            NSString *msg = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : @"导出图片失败";
            if (completion) {
                completion(nil, [NSError errorWithDomain:@"CaptchaActor" code:6 userInfo:@{NSLocalizedDescriptionKey: msg}]);
            }
            return;
        }
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"CaptchaActor" code:7 userInfo:@{NSLocalizedDescriptionKey: @"导出图片返回异常"}]);
        }
    }];
}

@end
