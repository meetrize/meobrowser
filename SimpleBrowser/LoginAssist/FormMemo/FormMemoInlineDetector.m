#import "FormMemoInlineDetector.h"
#import "LoginAssistScriptMessageProxy.h"
#import "FormMemoPreferences.h"
#import "BrowserRiskHostPolicy.h"
#import "FormMemo.h"

NSString * const FormMemoInlineHandlerName = @"formMemoInline";

@implementation FormMemoInlineDetector

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

    [ucc removeScriptMessageHandlerForName:FormMemoInlineHandlerName];
    LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
    proxy.target = handler;
    [ucc addScriptMessageHandler:proxy name:FormMemoInlineHandlerName];

    BOOL saveEnabled = [FormMemoPreferences inlineSaveEnabled];
    NSString *source = [NSString stringWithFormat:@"window.__meoFormMemoInlineEnabled=%@;\n%@",
                        saveEnabled ? @"true" : @"false",
                        [self userScriptSource]];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
}

+ (NSString *)javaScriptSettingFillTargets:(NSArray<NSDictionary *> *)targets hasMemo:(BOOL)hasMemo {
    NSArray *safe = targets ?: @[];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:&error];
    NSString *json = (!data || error) ? @"[]" : ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]");
    return [NSString stringWithFormat:
            @"(function(){ var t=%@; var m={hasMemo:%@};"
            " window.__meoFormMemoPendingFillTargets=t;"
            " window.__meoFormMemoPendingFillMeta=m;"
            " if (window.__meoFormMemoSetFillTargets) { window.__meoFormMemoSetFillTargets(t, m); }"
            " })();",
            json,
            hasMemo ? @"true" : @"false"];
}

+ (NSString *)javaScriptSettingFillTargets:(NSArray<NSDictionary *> *)targets {
    return [self javaScriptSettingFillTargets:targets hasMemo:(targets.count > 0)];
}

+ (NSArray<NSDictionary *> *)fillTargetDictionariesFromMemo:(FormMemo *)memo {
    if (!memo) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];
    // 启用字段优先；若全被禁用仍带上全部有 selector 的字段，保证能显示图标
    NSArray<FormMemoField *> *fields = [memo enabledFields];
    if (fields.count == 0) {
        fields = memo.fields;
    }
    for (FormMemoField *field in fields) {
        if (field.selector.length == 0) {
            continue;
        }
        [targets addObject:@{
            @"selector": field.selector,
            @"label": field.label.length > 0 ? field.label : @"字段",
        }];
    }
    return targets;
}

+ (NSString *)userScriptSource {
    NSString *suppressFn = [BrowserRiskHostPolicy javaScriptShouldSuppressPageAutomationFunctionNamed:@"meoShouldSuppress"];
    NSString *prefix = [NSString stringWithFormat:
        @"(function() {\n"
        "  if (window.__meoFormMemoInlineInstalled) { return; }\n"
        "%@"
        "  if (meoShouldSuppress()) { return; }\n"
        "  window.__meoFormMemoInlineInstalled = true;\n",
        suppressFn];

    return [prefix stringByAppendingString:[self userScriptSourceBody]];
}

+ (NSString *)userScriptSourceBody {
    return @
"  const HANDLER = 'formMemoInline';\n"
"  const SAVE_BTN_ID = 'meo-form-memo-save-btn';\n"
"  const FILL_BTN_CLASS = 'meo-form-memo-fill-btn';\n"
"  const MIN_LEN = 1;\n"
"  let activeEl = null;\n"
"  let fillTargets = [];\n"
"  let hasMemoFlag = false;\n"
"  let fillBound = false;\n"
"  let saveBound = false;\n"
"  let mutateTimer = null;\n"
"\n"
"  function post(payload) {\n"
"    try { window.webkit.messageHandlers[HANDLER].postMessage(payload); } catch (e) {}\n"
"  }\n"
"  function visible(el) {\n"
"    if (!el || el.disabled) return false;\n"
"    const st = window.getComputedStyle(el);\n"
"    if (st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return false;\n"
"    const r = el.getBoundingClientRect();\n"
"    return r.width > 0 && r.height > 0;\n"
"  }\n"
"  function visibleForFill(el) {\n"
"    if (!el || el.disabled) return false;\n"
"    const st = window.getComputedStyle(el);\n"
"    if (st.display === 'none' || st.visibility === 'hidden' || Number(st.opacity) === 0) return false;\n"
"    const r = el.getBoundingClientRect();\n"
"    return r.width > 0 && r.height > 0;\n"
"  }\n"
"  function textBlob(el) {\n"
"    return [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.autocomplete]\n"
"      .filter(Boolean).join(' ').toLowerCase();\n"
"  }\n"
"  function isPasswordField(el) {\n"
"    if (!el || el.tagName !== 'INPUT') return false;\n"
"    const t = (el.type || '').toLowerCase();\n"
"    if (t === 'password') return true;\n"
"    const ac = (el.autocomplete || '').toLowerCase();\n"
"    return ac.indexOf('current-password') >= 0 || ac.indexOf('new-password') >= 0;\n"
"  }\n"
"  function isOTPField(el) {\n"
"    if (!el || el.tagName !== 'INPUT') return false;\n"
"    const ac = (el.autocomplete || '').toLowerCase();\n"
"    if (ac.indexOf('one-time-code') >= 0) return true;\n"
"    return /(otp|code|验证码|校验码|auth.?code)/i.test(textBlob(el));\n"
"  }\n"
"  function isAccountField(el) {\n"
"    if (!el || el.tagName !== 'INPUT' || !visible(el)) return false;\n"
"    const t = (el.type || 'text').toLowerCase();\n"
"    if (t === 'password' || t === 'hidden' || t === 'submit' || t === 'button' || t === 'checkbox' || t === 'radio' || t === 'search' || t === 'file') return false;\n"
"    if (t === 'email' || t === 'tel') return true;\n"
"    if (t !== 'text' && t !== '') return false;\n"
"    const ac = (el.autocomplete || '').toLowerCase();\n"
"    if (/(username|email|tel|nickname|name)/.test(ac)) return true;\n"
"    return /(user|login|account|email|mail|手机|帐号|账号|邮箱|phone)/i.test(textBlob(el));\n"
"  }\n"
"  function rootFor(el) {\n"
"    return (el && el.closest && el.closest('form')) || document.body;\n"
"  }\n"
"  function formHasPassword(root) {\n"
"    if (!root) return false;\n"
"    return Array.from(root.querySelectorAll('input')).some(isPasswordField);\n"
"  }\n"
"  function isLoginContextField(el) {\n"
"    if (isPasswordField(el) || isOTPField(el)) return true;\n"
"    const root = rootFor(el);\n"
"    if (!formHasPassword(root)) return false;\n"
"    return isAccountField(el);\n"
"  }\n"
"  function isEligibleField(el) {\n"
"    if (!el || !visible(el) || el.readOnly) return false;\n"
"    const tag = el.tagName;\n"
"    if (tag === 'TEXTAREA') return true;\n"
"    if (tag !== 'INPUT') return false;\n"
"    const t = (el.type || 'text').toLowerCase();\n"
"    if (['password','hidden','search','file','checkbox','radio','submit','button','reset','image','range','color','date','datetime-local','month','time','week'].indexOf(t) >= 0) return false;\n"
"    const ac = (el.autocomplete || '').toLowerCase();\n"
"    if (/(^|-)(cc-|card)/.test(ac) || ac.indexOf('cc-') >= 0) return false;\n"
"    if (isLoginContextField(el)) return false;\n"
"    return true;\n"
"  }\n"
"  function cssPath(el) {\n"
"    if (!el || el.nodeType !== 1) return '';\n"
"    function esc(v) {\n"
"      if (window.CSS && CSS.escape) return CSS.escape(v);\n"
"      return String(v).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');\n"
"    }\n"
"    if (el.id) {\n"
"      const s = '#' + esc(el.id);\n"
"      try { if (document.querySelectorAll(s).length === 1) return s; } catch (e) {}\n"
"    }\n"
"    const name = el.getAttribute('name');\n"
"    if (name) {\n"
"      const s = el.tagName.toLowerCase() + '[name=\"' + name.replace(/\"/g, '\\\\\"') + '\"]';\n"
"      try { if (document.querySelectorAll(s).length === 1) return s; } catch (e) {}\n"
"    }\n"
"    const parts = [];\n"
"    let node = el;\n"
"    while (node && node.nodeType === 1 && node !== document.body && parts.length < 5) {\n"
"      let part = node.tagName.toLowerCase();\n"
"      const parent = node.parentElement;\n"
"      if (parent) {\n"
"        const siblings = Array.from(parent.children).filter(c => c.tagName === node.tagName);\n"
"        if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';\n"
"      }\n"
"      parts.unshift(part);\n"
"      node = parent;\n"
"    }\n"
"    return parts.join(' > ');\n"
"  }\n"
"  function fieldLabel(el) {\n"
"    try {\n"
"      if (el.id) {\n"
"        function esc(v) {\n"
"          if (window.CSS && CSS.escape) return CSS.escape(v);\n"
"          return String(v).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');\n"
"        }\n"
"        const lab = document.querySelector('label[for=\"' + esc(el.id) + '\"]');\n"
"        if (lab && lab.textContent) return lab.textContent.trim().replace(/\\s+/g, ' ').slice(0, 40);\n"
"      }\n"
"      const wrap = el.closest('label');\n"
"      if (wrap && wrap.textContent) {\n"
"        const t = wrap.textContent.trim().replace(/\\s+/g, ' ');\n"
"        if (t.length > 0 && t.length < 60) return t.slice(0, 40);\n"
"      }\n"
"    } catch (e) {}\n"
"    return (el.placeholder || el.getAttribute('aria-label') || el.name || el.id || '字段').toString().slice(0, 40);\n"
"  }\n"
"  function ensureStyle() {\n"
"    if (document.getElementById('meo-form-memo-inline-style')) return;\n"
"    const style = document.createElement('style');\n"
"    style.id = 'meo-form-memo-inline-style';\n"
"    style.textContent = '' +\n"
"      'input[data-meo-memo-host=\"1\"],textarea[data-meo-memo-host=\"1\"]{ padding-right: 34px !important; box-sizing: border-box !important; }' +\n"
"      'button#' + SAVE_BTN_ID + '{' +\n"
"      'position:absolute;z-index:2147483645;width:22px;height:22px;border:0;padding:0;' +\n"
"      'border-radius:5px;cursor:pointer;background:rgba(128,128,128,0.22);' +\n"
"      'color:inherit;font-size:14px;line-height:22px;text-align:center;' +\n"
"      'box-shadow:0 0 0 1px rgba(0,0,0,0.08);' +\n"
"      '}' +\n"
"      'button#' + SAVE_BTN_ID + ':hover{background:rgba(10,132,255,0.32);}' +\n"
"      'button.' + FILL_BTN_CLASS + '{' +\n"
"      'position:fixed;z-index:2147483646;width:24px;height:24px;border:0;padding:0;' +\n"
"      'border-radius:6px;cursor:pointer;' +\n"
"      'background:rgba(10,132,255,0.92);color:#fff;' +\n"
"      'display:flex;align-items:center;justify-content:center;' +\n"
"      'box-shadow:0 1px 3px rgba(0,0,0,0.18);' +\n"
"      '}' +\n"
"      'button.' + FILL_BTN_CLASS + ':hover{background:rgba(0,112,230,1);}' +\n"
"    document.documentElement.appendChild(style);\n"
"  }\n"
"  function hideSaveButton() {\n"
"    const btn = document.getElementById(SAVE_BTN_ID);\n"
"    if (btn) btn.style.display = 'none';\n"
"    activeEl = null;\n"
"  }\n"
"  function saveEnabled() { return window.__meoFormMemoInlineEnabled !== false; }\n"
"  function queryBySelector(sel) {\n"
"    if (!sel) return null;\n"
"    try { return document.querySelector(sel); } catch (e) { return null; }\n"
"  }\n"
"  function fieldHasFillTarget(el) {\n"
"    if (!el || !fillTargets.length) return false;\n"
"    for (let i = 0; i < fillTargets.length; i++) {\n"
"      const t = fillTargets[i];\n"
"      if (!t || !t.selector) continue;\n"
"      try { if (queryBySelector(t.selector) === el) return true; } catch (e) {}\n"
"    }\n"
"    return false;\n"
"  }\n"
"  function placeSaveButton(el) {\n"
"    if (!saveEnabled() || !isEligibleField(el)) { hideSaveButton(); return; }\n"
"    const value = (el.value || '').toString();\n"
"    if (value.trim().length < MIN_LEN) { hideSaveButton(); return; }\n"
"    ensureStyle();\n"
"    let btn = document.getElementById(SAVE_BTN_ID);\n"
"    if (!btn) {\n"
"      btn = document.createElement('button');\n"
"      btn.type = 'button';\n"
"      btn.id = SAVE_BTN_ID;\n"
"      btn.setAttribute('aria-label', '保存到站点备忘');\n"
"      btn.title = '保存到站点备忘';\n"
"      btn.textContent = '+';\n"
"      btn.addEventListener('mousedown', function(e) { e.preventDefault(); e.stopPropagation(); }, true);\n"
"      btn.addEventListener('click', function(e) {\n"
"        e.preventDefault(); e.stopPropagation();\n"
"        const target = activeEl;\n"
"        if (!target || !isEligibleField(target)) return;\n"
"        const v = (target.value || '').toString();\n"
"        if (v.trim().length < MIN_LEN) return;\n"
"        post({ type: 'saveField', selector: cssPath(target), label: fieldLabel(target), value: v, href: location.href || '' });\n"
"      }, true);\n"
"      document.documentElement.appendChild(btn);\n"
"    }\n"
"    activeEl = el;\n"
"    el.setAttribute('data-meo-memo-host', '1');\n"
"    const r = el.getBoundingClientRect();\n"
"    const offset = (fieldHasFillTarget(el) || document.querySelector('button.' + FILL_BTN_CLASS)) ? 58 : 28;\n"
"    btn.style.top = Math.round(r.top + window.scrollY + (r.height - 22) / 2) + 'px';\n"
"    btn.style.left = Math.round(r.left + window.scrollX + r.width - offset) + 'px';\n"
"    btn.style.display = 'block';\n"
"    if (!saveBound) {\n"
"      saveBound = true;\n"
"      window.addEventListener('scroll', function() { if (activeEl) placeSaveButton(activeEl); repositionFillButtons(); }, true);\n"
"      window.addEventListener('resize', function() { if (activeEl) placeSaveButton(activeEl); repositionFillButtons(); });\n"
"    }\n"
"  }\n"
"  function clearFillButtons() {\n"
"    document.querySelectorAll('button.' + FILL_BTN_CLASS).forEach(function(b) { b.remove(); });\n"
"  }\n"
"  function isFillAnchorCandidate(el) {\n"
"    if (!visibleForFill(el)) return false;\n"
"    const tag = el.tagName;\n"
"    if (tag === 'TEXTAREA') return true;\n"
"    if (tag !== 'INPUT') return false;\n"
"    const t = (el.type || 'text').toLowerCase();\n"
"    if (['hidden','submit','button','reset','image','checkbox','radio','file','password'].indexOf(t) >= 0) return false;\n"
"    return true;\n"
"  }\n"
"  function findFallbackFillAnchor() {\n"
"    return Array.from(document.querySelectorAll('input, textarea')).find(isFillAnchorCandidate) || null;\n"
"  }\n"
"  function placeFillButtonFor(el, idx, selector, label) {\n"
"    if (!el || !visibleForFill(el)) return false;\n"
"    ensureStyle();\n"
"    el.setAttribute('data-meo-memo-host', '1');\n"
"    let btn = document.querySelector('button.' + FILL_BTN_CLASS + '[data-meo-idx=\"' + idx + '\"]');\n"
"    if (!btn) {\n"
"      btn = document.createElement('button');\n"
"      btn.type = 'button';\n"
"      btn.className = FILL_BTN_CLASS;\n"
"      btn.setAttribute('data-meo-idx', String(idx));\n"
"      btn.setAttribute('aria-label', '填入站点备忘');\n"
"      btn.title = '填入站点备忘' + (label ? ('：' + label) : '');\n"
"      btn.innerHTML = '<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 16 16\" fill=\"none\" aria-hidden=\"true\">' +\n"
"        '<path d=\"M3 2.5h7.5L13 5v8.5H3V2.5z\" stroke=\"#fff\" stroke-width=\"1.4\" fill=\"none\"/>' +\n"
"        '<path d=\"M10 2.5V5h2.5\" stroke=\"#fff\" stroke-width=\"1.4\" fill=\"none\"/>' +\n"
"        '<path d=\"M8 7v4.5M8 11.5L6.2 9.7M8 11.5l1.8-1.8\" stroke=\"#fff\" stroke-width=\"1.4\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>' +\n"
"        '</svg>';\n"
"      btn.addEventListener('mousedown', function(e) { e.preventDefault(); e.stopPropagation(); }, true);\n"
"      btn.addEventListener('click', function(e) {\n"
"        e.preventDefault(); e.stopPropagation();\n"
"        post({ type: 'fillMemo', selector: selector || '', href: location.href || '' });\n"
"      }, true);\n"
"      document.documentElement.appendChild(btn);\n"
"    }\n"
"    const r = el.getBoundingClientRect();\n"
"    // fixed：相对视口，避免页面 transform / 内部滚动导致错位到框外\n"
"    btn.style.top = Math.round(r.top + (r.height - 24) / 2) + 'px';\n"
"    btn.style.left = Math.round(r.left + Math.max(8, r.width - 30)) + 'px';\n"
"    btn.style.display = (r.width > 0 && r.bottom > 0 && r.top < window.innerHeight) ? 'flex' : 'none';\n"
"    return true;\n"
"  }\n"
"  function repositionFillButtons() {\n"
"    clearFillButtons();\n"
"    let placed = 0;\n"
"    if (fillTargets && fillTargets.length) {\n"
"      fillTargets.forEach(function(t, idx) {\n"
"        if (!t || !t.selector) return;\n"
"        const el = queryBySelector(t.selector);\n"
"        if (el && placeFillButtonFor(el, idx, t.selector, t.label || '')) placed++;\n"
"      });\n"
"    }\n"
"    if (placed === 0 && (hasMemoFlag || (fillTargets && fillTargets.length > 0))) {\n"
"      const fallback = findFallbackFillAnchor();\n"
"      if (fallback) placeFillButtonFor(fallback, -1, '', '站点备忘');\n"
"    }\n"
"    if (activeEl) placeSaveButton(activeEl);\n"
"  }\n"
"  window.__meoFormMemoSetFillTargets = function(targets, meta) {\n"
"    fillTargets = Array.isArray(targets) ? targets : [];\n"
"    hasMemoFlag = !!(meta && meta.hasMemo) || fillTargets.length > 0;\n"
"    repositionFillButtons();\n"
"    if (!fillBound) {\n"
"      fillBound = true;\n"
"      window.addEventListener('scroll', repositionFillButtons, true);\n"
"      window.addEventListener('resize', repositionFillButtons);\n"
"      try {\n"
"        const mo = new MutationObserver(function() {\n"
"          if (meoShouldSuppress()) { try { mo.disconnect(); } catch (e) {} return; }\n"
"          if (mutateTimer) clearTimeout(mutateTimer);\n"
"          mutateTimer = setTimeout(repositionFillButtons, 200);\n"
"        });\n"
"        mo.observe(document.documentElement, { childList: true, subtree: true });\n"
"      } catch (e) {}\n"
"    }\n"
"  };\n"
"  function onFocusIn(e) {\n"
"    const el = e.target;\n"
"    if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) placeSaveButton(el);\n"
"  }\n"
"  function onFocusOut(e) {\n"
"    const related = e.relatedTarget;\n"
"    if (related && (related.id === SAVE_BTN_ID || (related.classList && related.classList.contains(FILL_BTN_CLASS)))) return;\n"
"    setTimeout(function() {\n"
"      const ae = document.activeElement;\n"
"      if (ae === activeEl) return;\n"
"      if (ae && (ae.id === SAVE_BTN_ID || (ae.classList && ae.classList.contains(FILL_BTN_CLASS)))) return;\n"
"      hideSaveButton();\n"
"    }, 120);\n"
"  }\n"
"  function onInput(e) {\n"
"    const el = e.target;\n"
"    if (el === document.activeElement && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) placeSaveButton(el);\n"
"  }\n"
"  document.addEventListener('focusin', onFocusIn, true);\n"
"  document.addEventListener('focusout', onFocusOut, true);\n"
"  document.addEventListener('input', onInput, true);\n"
"  if (window.__meoFormMemoPendingFillTargets) {\n"
"    window.__meoFormMemoSetFillTargets(window.__meoFormMemoPendingFillTargets, window.__meoFormMemoPendingFillMeta || {hasMemo:true});\n"
"    window.__meoFormMemoPendingFillTargets = null;\n"
"    window.__meoFormMemoPendingFillMeta = null;\n"
"  }\n"
"})();\n";
}

@end
