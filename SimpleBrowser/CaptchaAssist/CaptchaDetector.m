#import "CaptchaDetector.h"
#import "LoginAssistScriptMessageProxy.h"

NSString * const CaptchaAssistHandlerName = @"captchaAssist";

@implementation CaptchaDetector

+ (void)installOnConfiguration:(WKWebViewConfiguration *)configuration
               messageHandler:(id<WKScriptMessageHandler>)handler {
    if (!configuration || !handler) {
        return;
    }

    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }

    [ucc removeScriptMessageHandlerForName:CaptchaAssistHandlerName];
    LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
    proxy.target = handler;
    [ucc addScriptMessageHandler:proxy name:CaptchaAssistHandlerName];

    // CA-0：始终注入检测脚本（偏好仅控制点亮/后续自动求解；避免开关后须重建 configuration）
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self userScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)userScriptSource {
    return @
    "(function() {\n"
    "  if (window.__meoCaptchaDetectorInstalled) { return; }\n"
    "  window.__meoCaptchaDetectorInstalled = true;\n"
    "\n"
    "  function post(payload) {\n"
    "    try {\n"
    "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.captchaAssist) {\n"
    "        window.webkit.messageHandlers.captchaAssist.postMessage(payload);\n"
    "      }\n"
    "    } catch (e) {}\n"
    "  }\n"
    "\n"
    "  function rectOf(el) {\n"
    "    try {\n"
    "      var r = el.getBoundingClientRect();\n"
    "      if (!r || r.width < 2 || r.height < 2) return null;\n"
    "      return { x: r.left, y: r.top, w: r.width, h: r.height };\n"
    "    } catch (e) { return null; }\n"
    "  }\n"
    "\n"
    "  function pickVisible(selector) {\n"
    "    var nodes = document.querySelectorAll(selector);\n"
    "    for (var i = 0; i < nodes.length; i++) {\n"
    "      var el = nodes[i];\n"
    "      var style = window.getComputedStyle(el);\n"
    "      if (style && (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0')) continue;\n"
    "      var r = rectOf(el);\n"
    "      if (r) return { el: el, rect: r };\n"
    "    }\n"
    "    return null;\n"
    "  }\n"
    "\n"
    "  function scan() {\n"
    "    var findings = [];\n"
    "\n"
    "    if (typeof window.initGeetest === 'function' || window.Geetest || document.querySelector('.geetest_holder, .geetest_panel, .geetest_btn, [class*=\"geetest\"]')) {\n"
    "      var g = pickVisible('.geetest_panel, .geetest_holder, .geetest_btn, [class*=\"geetest\"]') || { rect: null };\n"
    "      findings.push({ vendor: 'geetest', kind: 'slider_or_click', confidence: 0.85, rect: g.rect, frame: 'main', detail: 'geetest fingerprint' });\n"
    "    }\n"
    "\n"
    "    if (window.AWSC || document.querySelector('.nc-container, .nc_iconfont, #nc_1_n1z, [id^=\"nc_\"]')) {\n"
    "      var a = pickVisible('.nc-container, #nc_1_n1z, [class*=\"nc-\"]') || { rect: null };\n"
    "      findings.push({ vendor: 'aliyun', kind: 'slider', confidence: 0.8, rect: a.rect, frame: 'main', detail: 'aliyun AWSC/nc' });\n"
    "    }\n"
    "\n"
    "    if (document.querySelector('.yidun, .yidun_panel, .yidun_bgimg')) {\n"
    "      var y = pickVisible('.yidun_panel, .yidun') || { rect: null };\n"
    "      findings.push({ vendor: 'yidun', kind: 'slider_or_click', confidence: 0.8, rect: y.rect, frame: 'main', detail: 'netease yidun' });\n"
    "    }\n"
    "\n"
    "    if (typeof window.TencentCaptcha === 'function' || document.querySelector('#tcaptcha_transform_dy, .tc-captcha')) {\n"
    "      var t = pickVisible('#tcaptcha_transform_dy, .tc-captcha') || { rect: null };\n"
    "      findings.push({ vendor: 'tencent', kind: 'slider_or_click', confidence: 0.75, rect: t.rect, frame: 'main', detail: 'tencent captcha' });\n"
    "    }\n"
    "\n"
    "    if (window.grecaptcha || document.querySelector('.g-recaptcha, iframe[src*=\"recaptcha\"]')) {\n"
    "      var r = pickVisible('.g-recaptcha, iframe[src*=\"recaptcha\"]') || { rect: null };\n"
    "      findings.push({ vendor: 'recaptcha', kind: 'checkbox_or_image', confidence: 0.9, rect: r.rect, frame: 'iframe', detail: 'grecaptcha' });\n"
    "    }\n"
    "\n"
    "    if (document.querySelector('iframe[src*=\"hcaptcha\"], .h-captcha')) {\n"
    "      var h = pickVisible('.h-captcha, iframe[src*=\"hcaptcha\"]') || { rect: null };\n"
    "      findings.push({ vendor: 'hcaptcha', kind: 'checkbox_or_image', confidence: 0.85, rect: h.rect, frame: 'iframe', detail: 'hcaptcha' });\n"
    "    }\n"
    "\n"
    "    if (document.querySelector('iframe[src*=\"challenges.cloudflare\"], #cf-turnstile, .cf-turnstile')) {\n"
    "      var c = pickVisible('#cf-turnstile, .cf-turnstile, iframe[src*=\"challenges.cloudflare\"]') || { rect: null };\n"
    "      findings.push({ vendor: 'turnstile', kind: 'behavioral', confidence: 0.9, rect: c.rect, frame: 'iframe', detail: 'cloudflare turnstile' });\n"
    "    }\n"
    "\n"
    "    var ocrRoot = document.querySelector('[data-meo-captcha=\"ocr\"], #meo-captcha-ocr');\n"
    "    var ocrImg = document.querySelector('img.captcha-image, img[alt*=\"验证码\"], img[alt*=\"captcha\" i]');\n"
    "    if (ocrRoot || ocrImg) {\n"
    "      var root = ocrRoot || (ocrImg && ocrImg.closest ? ocrImg.closest('.panel') : null) || document.body;\n"
    "      var imgEl = (root.querySelector && root.querySelector('img.captcha-image, img[alt*=\"验证码\"], img[alt*=\"captcha\" i]')) || ocrImg;\n"
    "      var inputEl = root.querySelector ? root.querySelector('input[type=\"text\"], input:not([type])') : null;\n"
    "      var ocrRect = imgEl ? rectOf(imgEl) : (ocrRoot ? rectOf(ocrRoot) : null);\n"
    "      findings.push({ vendor: 'generic', kind: 'text_ocr', confidence: 0.82, rect: ocrRect, frame: 'main', detail: 'ocr image',\n"
    "        inputSelector: inputEl && inputEl.id ? ('#' + inputEl.id) : '#ocrInput',\n"
    "        imageSelector: 'img.captcha-image',\n"
    "        containerSelector: '#meo-captcha-ocr' });\n"
    "    }\n"
    "\n"
    "    var mathRoot = document.querySelector('[data-meo-captcha=\"math\"], #meo-captcha-math');\n"
    "    if (mathRoot) {\n"
    "      var mathInput = mathRoot.querySelector('input');\n"
    "      var prompt = mathRoot.querySelector('.math-prompt');\n"
    "      var mathText = prompt ? (prompt.innerText || prompt.textContent || '') : (mathRoot.innerText || mathRoot.textContent || '');\n"
    "      mathText = mathText.replace(/\\s+/g, ' ').trim();\n"
    "      findings.push({ vendor: 'generic', kind: 'math', confidence: 0.85, rect: rectOf(mathRoot), frame: 'main', detail: 'math challenge',\n"
    "        mathText: mathText,\n"
    "        inputSelector: mathInput && mathInput.id ? ('#' + mathInput.id) : '#mathInput',\n"
    "        containerSelector: '#meo-captcha-math' });\n"
    "    }\n"
    "\n"
    "    var slider = pickVisible('[data-meo-captcha=\"slider\"], #meo-captcha-slider, .captcha-slider');\n"
    "    if (slider) {\n"
    "      findings.push({ vendor: 'generic', kind: 'slider_puzzle', confidence: 0.7, rect: slider.rect, frame: 'main', detail: 'generic slider' });\n"
    "    }\n"
    "\n"
    "    if (findings.length === 0) {\n"
    "      post({ event: 'cleared' });\n"
    "      return;\n"
    "    }\n"
    "    post({ event: 'detected', findings: findings });\n"
    "  }\n"
    "\n"
    "  var timer = null;\n"
    "  function schedule() {\n"
    "    if (timer) clearTimeout(timer);\n"
    "    timer = setTimeout(scan, 280);\n"
    "  }\n"
    "\n"
    "  scan();\n"
    "  try {\n"
    "    var mo = new MutationObserver(schedule);\n"
    "    mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true });\n"
    "  } catch (e) {}\n"
    "  window.addEventListener('load', schedule, { once: true });\n"
    "})();\n";
}

@end
