#import "BrowserScraperElementPicker.h"
#import "LoginAssistScriptMessageProxy.h"

static NSString * const kScraperPickHandlerName = @"meoScraperPick";
static BrowserScraperPickCompletion gScraperPickCompletion = nil;
static __weak WKWebView *gScraperPickWebView = nil;

@implementation BrowserScraperElementPicker

+ (NSString *)jsonStringLiteral:(NSString *)string {
    NSString *safe = [string isKindOfClass:[NSString class]] ? string : @"";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:&error];
    if (!data) return @"\"\"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"\"\"";
}

+ (void)registerMessageHandlerOnConfiguration:(WKWebViewConfiguration *)configuration
                                      handler:(id<WKScriptMessageHandler>)handler {
    if (!configuration || !handler) return;
    WKUserContentController *ucc = configuration.userContentController;
    if (!ucc) {
        ucc = [[WKUserContentController alloc] init];
        configuration.userContentController = ucc;
    }
    [ucc removeScriptMessageHandlerForName:kScraperPickHandlerName];
    LoginAssistScriptMessageProxy *proxy = [[LoginAssistScriptMessageProxy alloc] init];
    proxy.target = handler;
    [ucc addScriptMessageHandler:proxy name:kScraperPickHandlerName];
}

+ (void)cancelActivePick {
    WKWebView *webView = gScraperPickWebView;
    gScraperPickWebView = nil;
    BrowserScraperPickCompletion completion = gScraperPickCompletion;
    gScraperPickCompletion = nil;
    if (webView) {
        [webView evaluateJavaScript:@"window.__meoScraperStopPick && window.__meoScraperStopPick();"
                  completionHandler:nil];
    }
    if (completion) {
        completion(nil, YES);
    }
}

+ (void)startPickingInWebView:(WKWebView *)webView
                         mode:(BrowserScraperPickMode)mode
                   completion:(BrowserScraperPickCompletion)completion {
    [self startPickingInWebView:webView mode:mode containerPath:nil rowPath:nil completion:completion];
}

+ (void)startPickingInWebView:(WKWebView *)webView
                         mode:(BrowserScraperPickMode)mode
                containerPath:(NSString *)containerPath
                      rowPath:(NSString *)rowPath
                   completion:(BrowserScraperPickCompletion)completion {
    [self cancelActivePick];
    if (!webView) {
        if (completion) completion(nil, YES);
        return;
    }
    gScraperPickWebView = webView;
    gScraperPickCompletion = [completion copy];
    NSString *modeStr = @"container";
    if (mode == BrowserScraperPickModeField) modeStr = @"field";
    else if (mode == BrowserScraperPickModePagination) modeStr = @"pagination";

    NSString *containerJSON = [self jsonStringLiteral:containerPath ?: @""];
    NSString *rowJSON = [self jsonStringLiteral:rowPath ?: @""];

    NSString *script = [NSString stringWithFormat:
        @"(function() {\n"
         "  if (window.__meoScraperStopPick) { window.__meoScraperStopPick(); }\n"
         "  var pickMode = '%@';\n"
         "  var loopContainerPath = %@;\n"
         "  var loopRowPath = %@;\n"
         "  function escIdent(value) {\n"
         "    if (window.CSS && CSS.escape) { return CSS.escape(value); }\n"
         "    return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');\n"
         "  }\n"
         "  function cssPath(el) {\n"
         "    if (!el || el.nodeType !== 1) { return ''; }\n"
         "    if (el.id) {\n"
         "      var idSel = '#' + escIdent(el.id);\n"
         "      if (document.querySelectorAll(idSel).length === 1) { return idSel; }\n"
         "    }\n"
         "    var parts = [];\n"
         "    var node = el;\n"
         "    while (node && node.nodeType === 1 && node !== document.body && parts.length < 6) {\n"
         "      var part = node.tagName.toLowerCase();\n"
         "      var parent = node.parentElement;\n"
         "      if (parent) {\n"
         "        var siblings = Array.from(parent.children).filter(function(c) { return c.tagName === node.tagName; });\n"
         "        if (siblings.length > 1) {\n"
         "          part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';\n"
         "        }\n"
         "      }\n"
         "      parts.unshift(part);\n"
         "      node = parent;\n"
         "    }\n"
         "    return parts.join(' > ');\n"
         "  }\n"
         "  function qa(root, sel){\n"
         "    try {\n"
         "      if(!sel) return [];\n"
         "      if(sel.indexOf(':scope')===0){\n"
         "        var rest=sel.replace(/^:scope\\s*>\\s*/,'').trim();\n"
         "        return Array.from(root.children).filter(function(c){\n"
         "          try { return c.matches(rest); } catch(e){ return c.tagName && c.tagName.toLowerCase()===rest; }\n"
         "        });\n"
         "      }\n"
         "      return Array.from(root.querySelectorAll(sel));\n"
         "    } catch(e){ return []; }\n"
         "  }\n"
         "  function findLoopRows(){\n"
         "    if(pickMode!=='field' || !loopRowPath) return [];\n"
         "    var root = loopContainerPath ? document.querySelector(loopContainerPath) : document.body;\n"
         "    if(!root) return [];\n"
         "    return qa(root, loopRowPath);\n"
         "  }\n"
         "  function findOwningRow(el, rows){\n"
         "    if(!el || !rows || !rows.length) return null;\n"
         "    for(var i=0;i<rows.length;i++){\n"
         "      var row=rows[i];\n"
         "      if(row===el || (row.contains && row.contains(el))) return row;\n"
         "    }\n"
         "    return null;\n"
         "  }\n"
         "  // 相对循环行的可复用选择器（各卡片同构）\n"
         "  function relativePathInRow(row, el){\n"
         "    if(!row || !el || !(row===el || row.contains(el))) return '';\n"
         "    if(row===el) return '';\n"
         "    var tag=el.tagName.toLowerCase();\n"
         "    var allCls=Array.from(el.classList||[]);\n"
         "    for(var ci=0;ci<allCls.length;ci++){\n"
         "      var cm=allCls[ci].match(/^([A-Za-z_][\\w]*)--[\\w-]+$/);\n"
         "      if(cm){\n"
         "        var modSel='[class*=\"'+cm[1]+'--\"]';\n"
         "        try{ if(row.querySelectorAll(modSel).length===1) return modSel; }catch(e){}\n"
         "      }\n"
         "      var um=allCls[ci].match(/^_([A-Za-z][\\w]*)_/);\n"
         "      if(um){\n"
         "        var uSel='[class*=\"_'+um[1]+'_\"]';\n"
         "        try{ if(row.querySelectorAll(uSel).length===1) return uSel; }catch(e){}\n"
         "      }\n"
         "    }\n"
         "    var skip=/^(active|hover|selected|open|show|is-|js-|group-hover)/i;\n"
         "    var cls=allCls.filter(function(c){return c&&!skip.test(c);}).slice(0,3);\n"
         "    if(cls.length){\n"
         "      var sel=tag+'.'+cls.map(escIdent).join('.');\n"
         "      try{ if(row.querySelectorAll(sel).length===1) return sel; }catch(e){}\n"
         "    }\n"
         "    if(/^h[1-6]$/.test(tag) && row.querySelectorAll(tag).length===1) return tag;\n"
         "    if(tag==='img' && row.querySelectorAll('img').length===1) return 'img';\n"
         "    if(tag==='a' && row.querySelectorAll('a').length===1) return 'a';\n"
         "    if(tag==='time' && row.querySelectorAll('time').length===1) return 'time';\n"
         "    if(tag==='p' && row.querySelectorAll('p').length===1) return 'p';\n"
         "    var parts=[], node=el;\n"
         "    while(node && node!==row && parts.length<6){\n"
         "      var part=node.tagName.toLowerCase();\n"
         "      var p=node.parentElement;\n"
         "      if(p){\n"
         "        var sib=Array.from(p.children).filter(function(c){return c.tagName===node.tagName;});\n"
         "        if(sib.length>1) part+=':nth-of-type('+(sib.indexOf(node)+1)+')';\n"
         "      }\n"
         "      parts.unshift(part);\n"
         "      node=node.parentElement;\n"
         "    }\n"
         "    return parts.join(' > ');\n"
         "  }\n"
         "  function inferFieldMeta(el, row, relPath){\n"
         "    var tag=el && el.tagName ? el.tagName.toLowerCase() : '';\n"
         "    var kind='text', attr='', nameHint='';\n"
         "    var clsBlob=el ? Array.from(el.classList||[]).join(' ') : '';\n"
         "    // 淘宝价格区\n"
         "    if(/priceInt--|priceFloat--|innerPriceWrapper--/.test(clsBlob) && row){\n"
         "      var priceBox=el.closest ? el.closest('[class*=\"innerPriceWrapper--\"]') : null;\n"
         "      if(!priceBox && /priceInt--|priceFloat--/.test(clsBlob)) priceBox=el.parentElement;\n"
         "      if(priceBox && row.contains(priceBox)){\n"
         "        return { kind:'text', attribute:'', nameHint:'价格', path:relativePathInRow(row, priceBox) };\n"
         "      }\n"
         "      nameHint='价格';\n"
         "    }\n"
         "    // 京东价格 _price_\n"
         "    if(/_price_/.test(clsBlob) || (el.closest && el.closest('[class*=\"_price_\"]') && /_yen_/.test(clsBlob))){\n"
         "      var jdPrice=el.closest ? el.closest('[class*=\"_price_\"]') : (/_price_/.test(clsBlob)?el:null);\n"
         "      if(jdPrice && row && row.contains(jdPrice)){\n"
         "        return { kind:'text', attribute:'', nameHint:'价格', path:relativePathInRow(row, jdPrice) };\n"
         "      }\n"
         "      nameHint='价格';\n"
         "    }\n"
         "    if(/realSales--/.test(clsBlob)) nameHint='付款人数';\n"
         "    if(/_goods_volume_/.test(clsBlob)) nameHint='销量';\n"
         "    if(/shopNameText--|shopName--/.test(clsBlob)) nameHint='店名';\n"
         "    if(/_limit_/.test(clsBlob) || (/_name_/.test(clsBlob) && !/_newIcon_/.test(clsBlob))){\n"
         "      var shopNode=el;\n"
         "      if(el.querySelector){ var lim=el.querySelector('[class*=\"_limit_\"]'); if(lim) shopNode=lim; }\n"
         "      if(/_limit_/.test(clsBlob) || shopNode!==el){\n"
         "        return { kind:'text', attribute:'', nameHint:'店名', path:relativePathInRow(row, shopNode) };\n"
         "      }\n"
         "    }\n"
         "    if(/title--|(_goods_title|_newStyle_)/.test(clsBlob) && el.getAttribute && el.getAttribute('title')){\n"
         "      return { kind:'attribute', attribute:'title', nameHint:'标题', path:relPath };\n"
         "    }\n"
         "    var hrefEl=null;\n"
         "    try{ if(el && el.matches && el.matches('a[href]')) hrefEl=el; }catch(e){}\n"
         "    if(!hrefEl && tag==='a' && el.getAttribute && el.getAttribute('href')) hrefEl=el;\n"
         "    if(!hrefEl && row && relPath==='' ){\n"
         "      try{ if(row.matches && row.matches('a[href]')) hrefEl=row; }catch(e){}\n"
         "      if(!hrefEl && row.tagName && row.tagName.toLowerCase()==='a' && row.getAttribute('href')) hrefEl=row;\n"
         "    }\n"
         "    if(hrefEl){\n"
         "      kind='href'; attr='href'; nameHint='链接';\n"
         "      if(hrefEl===row) relPath='';\n"
         "      else if(!relPath) relPath=relativePathInRow(row, hrefEl) || 'a';\n"
         "    } else if(tag==='img' || (el && el.getAttribute && el.getAttribute('src'))){\n"
         "      kind='src'; attr='src'; nameHint=nameHint||'图片';\n"
         "    } else if(/^h[1-6]$/.test(tag)){\n"
         "      nameHint=nameHint||'标题';\n"
         "    }\n"
         "    return { kind:kind, attribute:attr, nameHint:nameHint, path:relPath };\n"
         "  }\n"
         "  function suggestFields(el) {\n"
         "    var fields = [];\n"
         "    if (!el) return fields;\n"
         "    var tag = el.tagName.toLowerCase();\n"
         "    if (tag === 'table') {\n"
         "      var heads = Array.from(el.querySelectorAll('thead th')).map(function(th){ return (th.textContent||'').trim(); });\n"
         "      if (!heads.length) {\n"
         "        var first = el.querySelector('tr');\n"
         "        if (first) heads = Array.from(first.children).map(function(c){ return (c.textContent||'').trim() || ('列'+(fields.length+1)); });\n"
         "      }\n"
         "      heads.forEach(function(name, i) {\n"
         "        fields.push({ name: name || ('列'+(i+1)), kind: 'text', path: 'td:nth-child('+(i+1)+')' });\n"
         "      });\n"
         "      return fields;\n"
         "    }\n"
         "    var selfA=null;\n"
         "    try{ if(el.matches && el.matches('a[href]')) selfA=el; }catch(e){}\n"
         "    var link = selfA || el.closest('a[href]') || el.querySelector('a[href]');\n"
         "    fields.push({ name: '名称', kind: 'text', path: '' });\n"
         "    fields.push({ name: '值', kind: 'text', path: '' });\n"
         "    if (link) fields.push({ name: '链接', kind: 'href', path: link === el ? '' : 'a', attribute: 'href' });\n"
         "    return fields;\n"
         "  }\n"
         "  var style = document.createElement('style');\n"
         "  style.id = '__meoScraperPickStyle';\n"
         "  style.textContent = '.__meoScraperHover{outline:2px solid #ff9f0a!important;cursor:crosshair!important;background:rgba(255,159,10,0.08)!important;}';\n"
         "  document.documentElement.appendChild(style);\n"
         "  var last = null;\n"
         "  function onMove(e) {\n"
         "    var t = e.target;\n"
         "    if (last === t) return;\n"
         "    if (last) last.classList.remove('__meoScraperHover');\n"
         "    last = t;\n"
         "    if (t && t.classList) t.classList.add('__meoScraperHover');\n"
         "  }\n"
         "  function cleanup() {\n"
         "    document.removeEventListener('mousemove', onMove, true);\n"
         "    document.removeEventListener('click', onClick, true);\n"
         "    document.removeEventListener('keydown', onKey, true);\n"
         "    if (last) last.classList.remove('__meoScraperHover');\n"
         "    var s = document.getElementById('__meoScraperPickStyle');\n"
         "    if (s) s.remove();\n"
         "    window.__meoScraperStopPick = null;\n"
         "  }\n"
         "  function onKey(e) {\n"
         "    if (e.key === 'Escape') {\n"
         "      e.preventDefault(); e.stopPropagation();\n"
         "      cleanup();\n"
         "      try { window.webkit.messageHandlers.meoScraperPick.postMessage({ cancelled: true }); } catch (err) {}\n"
         "    }\n"
         "  }\n"
         "  function onClick(e) {\n"
         "    e.preventDefault(); e.stopPropagation();\n"
         "    var t = e.target;\n"
         "    var absPath = cssPath(t);\n"
         "    var rows = findLoopRows();\n"
         "    var row = findOwningRow(t, rows);\n"
         "    var relPath = row ? relativePathInRow(row, t) : '';\n"
         "    var meta = row ? inferFieldMeta(t, row, relPath) : { kind:'text', attribute:'', nameHint:'', path:absPath };\n"
         "    var usePath = row ? meta.path : absPath;\n"
         "    var payload = {\n"
         "      cancelled: false,\n"
         "      mode: pickMode,\n"
         "      cssPath: usePath,\n"
         "      absolutePath: absPath,\n"
         "      relativePath: row ? meta.path : '',\n"
         "      loopAware: !!row,\n"
         "      fieldKind: meta.kind || 'text',\n"
         "      attribute: meta.attribute || '',\n"
         "      nameHint: meta.nameHint || '',\n"
         "      tagName: t && t.tagName ? t.tagName.toLowerCase() : '',\n"
         "      textSample: t && t.textContent ? String(t.textContent).trim().slice(0, 120) : '',\n"
         "      suggestedFields: suggestFields(t)\n"
         "    };\n"
         "    if (t && t.tagName && t.tagName.toLowerCase() === 'table') {\n"
         "      payload.rowPath = 'tbody tr';\n"
         "      if (!t.querySelector('tbody tr')) payload.rowPath = 'tr';\n"
         "    }\n"
         "    cleanup();\n"
         "    try { window.webkit.messageHandlers.meoScraperPick.postMessage(payload); } catch (err) {}\n"
         "  }\n"
         "  window.__meoScraperStopPick = cleanup;\n"
         "  document.addEventListener('mousemove', onMove, true);\n"
         "  document.addEventListener('click', onClick, true);\n"
         "  document.addEventListener('keydown', onKey, true);\n"
         "})();", modeStr, containerJSON, rowJSON];

    [webView evaluateJavaScript:script completionHandler:nil];
}

+ (void)handleScriptMessageBody:(id)body {
    BrowserScraperPickCompletion completion = gScraperPickCompletion;
    gScraperPickCompletion = nil;
    gScraperPickWebView = nil;
    if (!completion) return;
    if (![body isKindOfClass:[NSDictionary class]]) {
        completion(nil, YES);
        return;
    }
    NSDictionary *dict = (NSDictionary *)body;
    if ([dict[@"cancelled"] boolValue]) {
        completion(nil, YES);
        return;
    }
    completion(dict, NO);
}

@end
