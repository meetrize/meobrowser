#import "BrowserScraperCandidateOverlay.h"

@implementation BrowserScraperCandidateOverlay

+ (NSString *)jsonStringFromObject:(id)object {
    if (!object) return @"null";
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data) return @"null";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"null";
}

+ (void)clearInWebView:(WKWebView *)webView {
    if (!webView) return;
    [webView evaluateJavaScript:
        @"(function(){ try { window.__meoScraperClearCandidateOverlay && window.__meoScraperClearCandidateOverlay(); } catch(e){} })();"
              completionHandler:nil];
}

+ (void)setVisible:(BOOL)visible inWebView:(WKWebView *)webView {
    if (!webView) return;
    NSString *script = [NSString stringWithFormat:
        @"(function(){ try { window.__meoScraperSetCandidateOverlayVisible && window.__meoScraperSetCandidateOverlayVisible(%@); } catch(e){} })();",
                        visible ? @"true" : @"false"];
    [webView evaluateJavaScript:script completionHandler:nil];
}

+ (void)setSelectedIndex:(NSInteger)selectedIndex inWebView:(WKWebView *)webView {
    if (!webView) return;
    NSString *script = [NSString stringWithFormat:
        @"(function(){ try { window.__meoScraperSelectCandidate && window.__meoScraperSelectCandidate(%ld); } catch(e){} })();",
                        (long)selectedIndex];
    [webView evaluateJavaScript:script completionHandler:nil];
}

+ (void)setAdoptedIndex:(NSInteger)adoptedIndex inWebView:(WKWebView *)webView {
    if (!webView) return;
    NSString *script = [NSString stringWithFormat:
        @"(function(){ try { window.__meoScraperAdoptCandidate && window.__meoScraperAdoptCandidate(%ld); } catch(e){} })();",
                        (long)adoptedIndex];
    [webView evaluateJavaScript:script completionHandler:nil];
}

+ (void)setOnlySelected:(BOOL)onlySelected inWebView:(WKWebView *)webView {
    if (!webView) return;
    NSString *script = [NSString stringWithFormat:
        @"(function(){ try { window.__meoScraperSetCandidateOnlySelected && window.__meoScraperSetCandidateOnlySelected(%@); } catch(e){} })();",
                        onlySelected ? @"true" : @"false"];
    [webView evaluateJavaScript:script completionHandler:nil];
}

+ (void)showCandidates:(NSArray<NSDictionary *> *)candidates
             inWebView:(WKWebView *)webView
         selectedIndex:(NSInteger)selectedIndex
          adoptedIndex:(NSInteger)adoptedIndex
          onlySelected:(BOOL)onlySelected
            completion:(void (^)(NSArray<NSNumber *> *missingIndexes))completion {
    if (!webView) {
        if (completion) completion(@[]);
        return;
    }
    NSMutableArray *payload = [NSMutableArray arrayWithCapacity:candidates.count];
    NSInteger i = 0;
    for (NSDictionary *c in candidates) {
        if (![c isKindOfClass:[NSDictionary class]]) { i++; continue; }
        NSString *path = [c[@"containerPath"] isKindOfClass:[NSString class]] ? c[@"containerPath"] : @"";
        if (path.length == 0) { i++; continue; }
        BOOL recommended = [c[@"recommended"] boolValue] || (i == 0);
        NSString *type = [c[@"type"] isKindOfClass:[NSString class]] ? c[@"type"] : @"";
        NSString *title = [c[@"title"] isKindOfClass:[NSString class]] ? c[@"title"] : @"";
        id score = c[@"score"] ?: @0;
        id rows = c[@"estimatedRows"] ?: @0;
        [payload addObject:@{
            @"index": @(i),
            @"display": @(i + 1),
            @"path": path,
            @"recommended": @(recommended),
            @"type": type,
            @"title": title,
            @"score": score,
            @"rows": rows,
        }];
        i++;
    }
    NSString *json = [self jsonStringFromObject:payload];
    NSString *script = [NSString stringWithFormat:
        @"(function(){\n"
         "  var items = %@;\n"
         "  var initialSelected = %ld;\n"
         "  var initialAdopted = %ld;\n"
         "  var onlySelected = %@;\n"
         "  function clear(){\n"
         "    document.removeEventListener('click', onOverlayClick, true);\n"
         "    document.removeEventListener('keydown', onOverlayKey, true);\n"
         "    var nodes = document.querySelectorAll('.__meoCandHL');\n"
         "    Array.from(nodes).forEach(function(el){\n"
         "      el.classList.remove('__meoCandHL','__meoCandSelected','__meoCandRecommended','__meoCandAdopted');\n"
         "      var prev = el.getAttribute('data-meo-cand-prev-pos');\n"
         "      if(prev !== null){\n"
         "        if(prev === '') el.style.removeProperty('position');\n"
         "        else el.style.position = prev;\n"
         "        el.removeAttribute('data-meo-cand-prev-pos');\n"
         "      }\n"
         "      el.removeAttribute('data-meo-cand-index');\n"
         "      var badge = el.querySelector('.__meoCandBadge');\n"
         "      if(badge && badge.parentElement === el) badge.remove();\n"
         "    });\n"
         "    var st = document.getElementById('__meoScraperCandidateStyle');\n"
         "    if(st) st.remove();\n"
         "    document.documentElement.classList.remove('__meoCandOverlayHidden','__meoCandOnlySelected');\n"
         "    window.__meoScraperClearCandidateOverlay = null;\n"
         "    window.__meoScraperSelectCandidate = null;\n"
         "    window.__meoScraperAdoptCandidate = null;\n"
         "    window.__meoScraperSetCandidateOverlayVisible = null;\n"
         "    window.__meoScraperSetCandidateOnlySelected = null;\n"
         "    window.__meoScraperCandidateOverlayActive = false;\n"
         "    window.__meoScraperCandidateMissing = null;\n"
         "  }\n"
         "  if(window.__meoScraperClearCandidateOverlay) window.__meoScraperClearCandidateOverlay();\n"
         "  if(!items || !items.length){\n"
         "    window.__meoScraperCandidateMissing = [];\n"
         "    return JSON.stringify([]);\n"
         "  }\n"
         "  var style = document.createElement('style');\n"
         "  style.id = '__meoScraperCandidateStyle';\n"
         "  style.textContent = [\n"
         "    '.__meoCandHL{outline:2px solid #3B82F6!important;outline-offset:2px!important;',\n"
         "    'box-shadow:inset 0 0 0 9999px rgba(59,130,246,0.06)!important;cursor:pointer!important;}',\n"
         "    '.__meoCandHL.__meoCandRecommended{',\n"
         "    'box-shadow:inset 0 0 0 9999px rgba(59,130,246,0.08),0 0 0 1px rgba(59,130,246,0.35)!important;}',\n"
         "    '.__meoCandHL.__meoCandSelected{outline:3px solid #F59E0B!important;outline-offset:2px!important;',\n"
         "    'box-shadow:inset 0 0 0 9999px rgba(245,158,11,0.12)!important;}',\n"
         "    '.__meoCandHL.__meoCandAdopted{outline:2px solid #10B981!important;outline-offset:2px!important;',\n"
         "    'box-shadow:inset 0 0 0 9999px rgba(16,185,129,0.10)!important;}',\n"
         "    '.__meoCandHL.__meoCandAdopted.__meoCandSelected{outline:3px solid #F59E0B!important;',\n"
         "    'box-shadow:inset 0 0 0 9999px rgba(245,158,11,0.12),0 0 0 1px #10B981!important;}',\n"
         "    '.__meoCandBadge{position:absolute;top:4px;left:4px;z-index:2147483646;',\n"
         "    'min-width:22px;height:22px;padding:0 6px;border-radius:6px;',\n"
         "    'background:#3B82F6;color:#fff;font:600 12px/22px -apple-system,BlinkMacSystemFont,sans-serif;',\n"
         "    'text-align:center;box-shadow:0 1px 3px rgba(0,0,0,.25);pointer-events:auto;',\n"
         "    'user-select:none;-webkit-user-select:none;white-space:nowrap;}',\n"
         "    '.__meoCandSelected > .__meoCandBadge{background:#F59E0B;}',\n"
         "    '.__meoCandAdopted > .__meoCandBadge{background:#10B981;}',\n"
         "    '.__meoCandAdopted.__meoCandSelected > .__meoCandBadge{background:#F59E0B;}',\n"
         "    '.__meoCandBadge.__meoCandBadgeRec::after{content:\"荐\";margin-left:3px;font-size:10px;opacity:.95;}',\n"
         "    '.__meoCandBadge.__meoCandBadgeAdopt::after{content:\"✓\";margin-left:3px;font-size:10px;}',\n"
         "    'html.__meoCandOverlayHidden .__meoCandHL{outline:none!important;box-shadow:none!important;}',\n"
         "    'html.__meoCandOverlayHidden .__meoCandBadge{display:none!important;}',\n"
         "    'html.__meoCandOnlySelected .__meoCandHL:not(.__meoCandSelected):not(.__meoCandAdopted){',\n"
         "    'outline:none!important;box-shadow:none!important;}',\n"
         "    'html.__meoCandOnlySelected .__meoCandHL:not(.__meoCandSelected):not(.__meoCandAdopted) > .__meoCandBadge{display:none!important;}'\n"
         "  ].join('');\n"
         "  document.documentElement.appendChild(style);\n"
         "  document.documentElement.classList.remove('__meoCandOverlayHidden');\n"
         "  if(onlySelected) document.documentElement.classList.add('__meoCandOnlySelected');\n"
         "  else document.documentElement.classList.remove('__meoCandOnlySelected');\n"
         "  var bound = [];\n"
         "  var missing = [];\n"
         "  var selectedIdx = initialSelected;\n"
         "  var adoptedIdx = initialAdopted;\n"
         "  function typeLabel(t){\n"
         "    if(t==='table') return '表格';\n"
         "    if(t==='list') return '列表';\n"
         "    if(t==='cards') return '卡片';\n"
         "    return t || '候选';\n"
         "  }\n"
         "  function refreshBadge(b){\n"
         "    var badge = b.el.querySelector('.__meoCandBadge');\n"
         "    if(!badge) return;\n"
         "    var rec = b.recommended && b.index !== adoptedIdx;\n"
         "    var ad = b.index === adoptedIdx;\n"
         "    badge.className = '__meoCandBadge'\n"
         "      + (rec ? ' __meoCandBadgeRec' : '')\n"
         "      + (ad ? ' __meoCandBadgeAdopt' : '');\n"
         "    badge.textContent = String(b.display);\n"
         "  }\n"
         "  items.forEach(function(it){\n"
         "    var el = null;\n"
         "    try { el = document.querySelector(it.path); } catch(e){ el = null; }\n"
         "    if(!el || el.nodeType !== 1){ missing.push(it.index); return; }\n"
         "    var cs = window.getComputedStyle(el);\n"
         "    if(cs.position === 'static'){\n"
         "      el.setAttribute('data-meo-cand-prev-pos', el.style.position || '');\n"
         "      el.style.position = 'relative';\n"
         "    }\n"
         "    el.classList.add('__meoCandHL');\n"
         "    if(it.recommended) el.classList.add('__meoCandRecommended');\n"
         "    el.setAttribute('data-meo-cand-index', String(it.index));\n"
         "    var badge = document.createElement('div');\n"
         "    badge.setAttribute('data-meo-cand-index', String(it.index));\n"
         "    var tip = '#' + it.display + ' · ' + typeLabel(it.type);\n"
         "    if(it.rows) tip += ' · 约' + it.rows + '项';\n"
         "    if(it.score != null) tip += ' · 分' + it.score;\n"
         "    if(it.title) tip += ' · ' + String(it.title).slice(0,40);\n"
         "    badge.title = tip;\n"
         "    el.insertBefore(badge, el.firstChild);\n"
         "    var b = {el:el, index:it.index, display:it.display, recommended:!!it.recommended};\n"
         "    bound.push(b);\n"
         "    refreshBadge(b);\n"
         "  });\n"
         "  function applyAdopted(){\n"
         "    bound.forEach(function(b){\n"
         "      if(b.index === adoptedIdx) b.el.classList.add('__meoCandAdopted');\n"
         "      else b.el.classList.remove('__meoCandAdopted');\n"
         "      refreshBadge(b);\n"
         "    });\n"
         "  }\n"
         "  function selectIndex(idx){\n"
         "    selectedIdx = idx;\n"
         "    bound.forEach(function(b){\n"
         "      if(b.index === idx) b.el.classList.add('__meoCandSelected');\n"
         "      else b.el.classList.remove('__meoCandSelected');\n"
         "    });\n"
         "    var hit = bound.filter(function(b){ return b.index === idx; })[0];\n"
         "    if(hit && hit.el && hit.el.scrollIntoView){\n"
         "      try { hit.el.scrollIntoView({block:'nearest', inline:'nearest', behavior:'smooth'}); } catch(e){\n"
         "        try { hit.el.scrollIntoView(false); } catch(e2){}\n"
         "      }\n"
         "    }\n"
         "  }\n"
         "  function adoptIndex(idx){\n"
         "    adoptedIdx = idx;\n"
         "    applyAdopted();\n"
         "  }\n"
         "  function findIndexFromEventTarget(t){\n"
         "    var n = t;\n"
         "    while(n && n !== document.documentElement){\n"
         "      if(n.getAttribute){\n"
         "        var v = n.getAttribute('data-meo-cand-index');\n"
         "        if(v != null && v !== '') return parseInt(v, 10);\n"
         "      }\n"
         "      n = n.parentElement;\n"
         "    }\n"
         "    return -1;\n"
         "  }\n"
         "  function postSelect(idx){\n"
         "    try {\n"
         "      window.webkit.messageHandlers.meoScraperPick.postMessage({\n"
         "        action: 'selectCandidate', index: idx\n"
         "      });\n"
         "    } catch(err){}\n"
         "  }\n"
         "  function onOverlayClick(e){\n"
         "    if(document.documentElement.classList.contains('__meoCandOverlayHidden')) return;\n"
         "    if(window.__meoScraperStopPick) return;\n"
         "    var idx = findIndexFromEventTarget(e.target);\n"
         "    if(idx < 0 || isNaN(idx)) return;\n"
         "    e.preventDefault(); e.stopPropagation();\n"
         "    selectIndex(idx);\n"
         "    postSelect(idx);\n"
         "  }\n"
         "  function onOverlayKey(e){\n"
         "    if(window.__meoScraperStopPick) return;\n"
         "    if(document.documentElement.classList.contains('__meoCandOverlayHidden')) return;\n"
         "    if(e.key === 'Escape'){\n"
         "      e.preventDefault(); e.stopPropagation();\n"
         "      try {\n"
         "        window.webkit.messageHandlers.meoScraperPick.postMessage({ action: 'clearCandidateOverlay' });\n"
         "      } catch(err){}\n"
         "      return;\n"
         "    }\n"
         "    if(e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;\n"
         "    if(!bound.length) return;\n"
         "    e.preventDefault(); e.stopPropagation();\n"
         "    var order = bound.map(function(b){ return b.index; }).sort(function(a,c){ return a-c; });\n"
         "    var pos = order.indexOf(selectedIdx);\n"
         "    if(pos < 0) pos = 0;\n"
         "    if(e.key === 'ArrowDown') pos = Math.min(order.length-1, pos+1);\n"
         "    else pos = Math.max(0, pos-1);\n"
         "    var next = order[pos];\n"
         "    selectIndex(next);\n"
         "    postSelect(next);\n"
         "  }\n"
         "  document.addEventListener('click', onOverlayClick, true);\n"
         "  document.addEventListener('keydown', onOverlayKey, true);\n"
         "  window.__meoScraperClearCandidateOverlay = clear;\n"
         "  window.__meoScraperSelectCandidate = selectIndex;\n"
         "  window.__meoScraperAdoptCandidate = adoptIndex;\n"
         "  window.__meoScraperSetCandidateOverlayVisible = function(v){\n"
         "    if(v) document.documentElement.classList.remove('__meoCandOverlayHidden');\n"
         "    else document.documentElement.classList.add('__meoCandOverlayHidden');\n"
         "  };\n"
         "  window.__meoScraperSetCandidateOnlySelected = function(v){\n"
         "    if(v) document.documentElement.classList.add('__meoCandOnlySelected');\n"
         "    else document.documentElement.classList.remove('__meoCandOnlySelected');\n"
         "  };\n"
         "  window.__meoScraperCandidateOverlayActive = true;\n"
         "  window.__meoScraperCandidateMissing = missing;\n"
         "  applyAdopted();\n"
         "  if(initialSelected >= 0) selectIndex(initialSelected);\n"
         "  return JSON.stringify(missing);\n"
         "})();",
        json, (long)selectedIndex, (long)adoptedIndex, onlySelected ? @"true" : @"false"];

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (!completion) return;
        NSMutableArray<NSNumber *> *missing = [NSMutableArray array];
        NSString *jsonResult = nil;
        if ([result isKindOfClass:[NSString class]]) jsonResult = (NSString *)result;
        if (jsonResult.length > 0) {
            NSData *data = [jsonResult dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([parsed isKindOfClass:[NSArray class]]) {
                for (id n in (NSArray *)parsed) {
                    if ([n respondsToSelector:@selector(integerValue)]) {
                        [missing addObject:@([n integerValue])];
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([missing copy]);
        });
        (void)error;
    }];
}

+ (BOOL)isSelectCandidateMessage:(id)body {
    if (![body isKindOfClass:[NSDictionary class]]) return NO;
    NSString *action = [body[@"action"] isKindOfClass:[NSString class]] ? body[@"action"] : @"";
    return [action isEqualToString:@"selectCandidate"] || [action isEqualToString:@"clearCandidateOverlay"];
}

+ (NSInteger)indexFromSelectCandidateMessage:(id)body {
    if (![body isKindOfClass:[NSDictionary class]]) return -1;
    id idx = body[@"index"];
    if ([idx respondsToSelector:@selector(integerValue)]) return [idx integerValue];
    return -1;
}

@end
