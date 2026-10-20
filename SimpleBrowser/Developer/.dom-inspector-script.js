(function() {
  if (window.__meoDomInspectorImpl) { return; }
  var FRAMES_MAX = 4;
  var FRAMES_DEPTH = 0;
  if (FRAMES_DEPTH > FRAMES_MAX) { return; }
  var HOVER = 'meo-dom-inspector-hover';
  var PINNED = 'meo-dom-inspector-pinned';
  var STYLE_ID = '__meo_dom_inspector_style';
  var DEBOUNCE_MS = 40;
  var MAX_VALUE_LEN = 160;
  var lastHovered = null;
  var pinnedEl = null;
  var hoverTimer = null;
  var pendingEl = null;
  var frame = null;
  var rafFallback = null;
  var observer = null;
  var observerPending = false;
  function frameOffset() {
    var dx = 0, dy = 0, win = window;
    try {
      while (win !== win.top && win.frameElement) {
        var r = win.frameElement.getBoundingClientRect();
        dx += r.left; dy += r.top;
        win = win.parent;
      }
    } catch (e) {
      // 跨源时无法向上累加，退回 0 偏移（气泡会定位在 iframe 原点附近）。
    }
    return { dx: dx, dy: dy };
  }
  function deliver(msg) {
    if (window.top !== window) {
      window.top.postMessage({__meo:'dom-inspector-payload', payload: msg}, '*');
      return;
    }
    window.webkit.messageHandlers.meoDomInspector.postMessage(msg);
  }
  function post(payload) {
    try {
      // JSON 往返：去掉不可序列化字段，并避免原地改 geometry 污染后续快照。
      var msg = JSON.parse(JSON.stringify(payload));
      var p = msg.payload;
      if (p && p.geometry) {
        var off = frameOffset();
        if (off.dx || off.dy) {
          p.geometry.x += off.dx; p.geometry.y += off.dy;
        }
      }
      // 跨源 iframe 里 WebKit 不会把消息路由到原生 handler，
      // 只能先 postMessage 给顶层窗口，由主框架代为转发。
      try {
        deliver(msg);
      } catch (e1) {
        // 全量快照过大时 WK 可能拒收：去掉 properties 再试一次。
        if (msg.payload && msg.payload.properties) {
          msg.payload.properties = [];
          if (msg.payload.counts) { msg.payload.counts.properties = 0; }
          try { deliver(msg); } catch (e2) {}
        }
      }
    } catch (e) {}
  }
  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) { return; }
    var s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent =
      '.' + HOVER + '{outline:2px solid #2F7BFF!important;outline-offset:-2px!important;cursor:crosshair!important;}\n' +
      '.' + PINNED + '{outline:2px dashed #FF7A1A!important;outline-offset:-2px!important;cursor:crosshair!important;}';
    (document.documentElement || document.head).appendChild(s);
  }
  function clearHover() {
    if (lastHovered && lastHovered.classList) { lastHovered.classList.remove(HOVER); }
    lastHovered = null;
  }
  function unpin() {
    if (pinnedEl && pinnedEl.classList) { pinnedEl.classList.remove(PINNED); }
    pinnedEl = null;
  }
  function escIdent(v) {
    if (window.CSS && CSS.escape) { return CSS.escape(v); }
    return String(v).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
  }
  function cssPath(el) {
    if (!el || el.nodeType !== 1) { return ''; }
    if (el.id) {
      var idSel = '#' + escIdent(el.id);
      try { if (document.querySelectorAll(idSel).length === 1) { return idSel; } } catch (e) {}
    }
    var parts = [], node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < 6) {
      if (node.id) { parts.unshift('#' + escIdent(node.id)); break; }
      var part = node.tagName.toLowerCase();
      var parent = node.parentElement;
      if (parent) {
        var sibs = Array.prototype.filter.call(parent.children, function (c) { return c.tagName === node.tagName; });
        if (sibs.length > 1) { part += ':nth-of-type(' + (sibs.indexOf(node) + 1) + ')'; }
      }
      parts.unshift(part);
      node = parent;
    }
    return parts.join(' > ');
  }
  function xpath(el) {
    if (!el || el.nodeType !== 1) { return ''; }
    var parts = [], node = el;
    while (node && node.nodeType === 1) {
      var idx = 1, sib = node.previousElementSibling;
      while (sib) { if (sib.tagName === node.tagName) { idx++; } sib = sib.previousElementSibling; }
      parts.unshift(node.tagName.toLowerCase() + '[' + idx + ']');
      node = node.parentElement;
    }
    return '/' + parts.join('/');
  }
  function clip(v, n) {
    var s = (v === null || v === undefined) ? '' : String(v);
    var limit = n || MAX_VALUE_LEN;
    return { text: s.length > limit ? s.slice(0, limit) + '…' : s,
             truncated: s.length > limit, length: s.length };
  }
  function attrKind(name) {
    if (name.indexOf('data-') === 0) { return 'data'; }
    if (name.indexOf('aria-') === 0) { return 'aria'; }
    if (name.indexOf('on') === 0) { return 'handler'; }
    if (name === 'class' || name === 'style' || name === 'id') { return 'identity'; }
    return 'attribute';
  }
  function collectAttributes(el, full) {
    var out = [], list = el.attributes;
    for (var i = 0; i < list.length; i++) {
      var a = list[i];
      var raw = a.value;
      if (a.name === 'class') { raw = scrubClasses(el); }
      var c = clip(raw, full ? 4000 : MAX_VALUE_LEN);
      out.push({ name: a.name, value: c.text, truncated: c.truncated, kind: attrKind(a.name) });
    }
    return out;
  }
  var SKIP_PROPS = { attributes:1, children:1, childNodes:1, parentNode:1, parentElement:1,
    firstChild:1, lastChild:1, nextSibling:1, previousSibling:1, ownerDocument:1, nodeValue:1,
    textContent:1, innerText:1, innerHTML:1, outerHTML:1, style:1, classList:1, dataset:1,
    clientWidth:1, clientHeight:1, scrollWidth:1, scrollHeight:1, offsetWidth:1, offsetHeight:1,
    offsetTop:1, offsetLeft:1, offsetParent:1, slot:1, shadowRoot:1, assignedSlot:1 };
  function collectProperties(el) {
    // 控制体量：过大时 WKScriptMessage 会静默丢弃，钉住侧栏永远打不开。
    var out = [], names = Object.getOwnPropertyNames(el).slice(0, 120);
    for (var i = 0; i < names.length && out.length < 80; i++) {
      var n = names[i];
      if (SKIP_PROPS[n]) { continue; }
      var v;
      try { v = el[n]; } catch (err) { v = undefined; }
      if (typeof v === 'function') { continue; }
      if (v && typeof v === 'object') {
        try { v = JSON.stringify(v); } catch (err2) { v = String(v); }
      }
      var c = clip(v, 500);
      out.push({ name: n, value: c.text, truncated: c.truncated, kind: 'property' });
    }
    return out;
  }
  var STYLE_KEYS = ['display','position','visibility','opacity','zIndex','overflow',
    'color','backgroundColor','fontSize','fontWeight','lineHeight','textAlign',
    'whiteSpace','pointerEvents','cursor'];
  // 快照前剔除探针自己的高亮 class，避免污染用户看到的 class 属性。
  function scrubClasses(el) {
    var cls = (typeof el.className === 'string') ? el.className : '';
    return cls.split(/\s+/).filter(function (c) {
      return c && c !== HOVER && c !== PINNED;
    }).join(' ');
  }
  function styleSummary(el) {
    var out = {}, cs;
    try { cs = window.getComputedStyle(el); } catch (e) { return out; }
    if (!cs) { return out; }
    for (var i = 0; i < STYLE_KEYS.length; i++) {
      var v = cs[STYLE_KEYS[i]];
      if (v) { out[STYLE_KEYS[i]] = String(v); }
    }
    return out;
  }
  // body → … → el（不含 html），供气泡洋葱导航。
  function collectAncestors(el) {
    var chain = [];
    var node = el;
    var guard = 0;
    while (node && node.nodeType === 1 && guard++ < 48) {
      var tag = node.tagName ? node.tagName.toLowerCase() : '';
      if (!tag || tag === 'html') { break; }
      chain.unshift({
        tagName: tag,
        id: node.id || '',
        className: scrubClasses(node),
        selector: cssPath(node),
        attributes: collectAttributes(node, false)
      });
      if (tag === 'body') { break; }
      node = node.parentElement;
    }
    return chain;
  }
  function snapshot(el, full) {
    var r = el.getBoundingClientRect();
    var own = '';
    try { own = String(el.textContent || '').trim(); } catch (e) {}
    var t = clip(own, full ? 2000 : 120);
    var attrs = collectAttributes(el, full);
    var props = full ? collectProperties(el) : [];
    var ancestors = collectAncestors(el);
    return {
      tagName: el.tagName ? el.tagName.toLowerCase() : '',
      selector: cssPath(el),
      xpath: xpath(el),
      id: el.id || '',
      className: scrubClasses(el),
      attributes: attrs,
      properties: props,
      ancestors: ancestors,
      geometry: {
        x: Math.round(r.left), y: Math.round(r.top),
        width: Math.round(r.width), height: Math.round(r.height),
        inViewport: r.bottom > 0 && r.right > 0 && r.top < (window.innerHeight || 0) &&
                    r.left < (window.innerWidth || 0),
        scrollWidth: el.scrollWidth, scrollHeight: el.scrollHeight,
        scrollTop: el.scrollTop, scrollLeft: el.scrollLeft
      },
      text: { own: t.text, truncated: t.truncated, length: t.length },
      styleSummary: styleSummary(el),
      a11y: { role: el.getAttribute('role') || '',
              label: el.getAttribute('aria-label') || '',
              alt: el.getAttribute('alt') || '',
              hidden: !!el.hidden },
      counts: { attributes: attrs.length, properties: props.length, ancestors: ancestors.length }
    };
  }
  function flushHover() {
    frame = null;
    if (rafFallback) { clearTimeout(rafFallback); rafFallback = null; }
    var el = pendingEl;
    pendingEl = null;
    if (!el || el.nodeType !== 1) { return; }
    if (el === lastHovered) {
      // 若在本次绘制期间又产生了新的待处理元素，继续下一轮，不要丢弃。
      if (pendingEl && !frame) {
        frame = window.requestAnimationFrame ? window.requestAnimationFrame(flushHover) : 0;
        if (!frame) { flushHover(); }
      }
      return;
    }
    clearHover();
    lastHovered = el;
    el.classList.add(HOVER);
    post({ type: 'hover', payload: snapshot(el, false) });
  }
  function onOver(e) {
    if (!e) { return; }
    var el = e.target;
    if (el && el.nodeType === 1 &&
        (el === document.documentElement || el === document.body)) {
      // 命中容器时改用坐标采样，取更有信息量的内层元素。
      if (typeof e.clientX === 'number') { el = pickElementAt(e.clientX, e.clientY); }
    }
    consider(el);
  }
  // 独立通道：靠坐标采样定位元素，不依赖事件在 DOM 树上传播。
  // 页面若用 stopImmediatePropagation 抢占 mouseover，只有这条通道仍然有效。
  function onPointerMove(e) {
    if (!e || typeof e.clientX !== 'number') { return; }
    var el = null;
    try { el = pickElementAt(e.clientX, e.clientY); } catch (err) { el = null; }
    consider(el);
  }
  // 从命中点向上挑选最有信息量的元素：跳过 body/html 等容器，
  // 否则表格表头这类由多层 div 包裹的结构只会取到最外层 <th>/<table>。
  function pickElementAt(x, y) {
    var list = null;
    try { list = document.elementsFromPoint(x, y); } catch (e) { list = null; }
    if (!list || !list.length) {
      try { return document.elementFromPoint(x, y); } catch (e2) { return null; }
    }
    var best = null;
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (!c || c.nodeType !== 1) { continue; }
      if (c === document.documentElement || c === document.body) { continue; }
      if (c.id === STYLE_ID || (c.tagName && c.tagName.toLowerCase() === 'style')) { continue; }
      best = c;
      break;
    }
    if (best) { return best; }
    // 全是容器时退回最深的那个（list 已按从深到浅排序）。
    return list[0];
  }
  function consider(el) {
    // 气泡已钉住：不再跟随其它元素，也不再发 hover。
    if (pinnedEl) { return; }
    if (!el || el.nodeType !== 1 || el === lastHovered) { return; }
    if (el === document.documentElement || el === document.body) { return; }
    pendingEl = el;
    if (hoverTimer) { clearTimeout(hoverTimer); }
    hoverTimer = setTimeout(function () {
      hoverTimer = null;
      if (!pendingEl) { return; }
      if (frame) { return; }
      // 标签页在后台时 requestAnimationFrame 会被暂停，导致 hover 永久卡死，
      // 因此额外挂一个定时器兜底。
      frame = window.requestAnimationFrame ? window.requestAnimationFrame(flushHover) : 0;
      if (frame) {
        rafFallback = setTimeout(function () {
          if (frame) { frame = null; flushHover(); }
        }, 120);
      } else {
        flushHover();
      }
    }, DEBOUNCE_MS);
  }
  var pinGuardUntil = 0;
  function pinElement(el) {
    if (!el || el.nodeType !== 1) { return false; }
    var now = Date.now();
    if (now < pinGuardUntil) { return true; }
    // 已钉住同一元素：忽略重复点击。
    if (pinnedEl === el) { return true; }
    pinGuardUntil = now + 250;
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
    if (rafFallback) { clearTimeout(rafFallback); rafFallback = null; }
    pendingEl = null;
    clearHover();
    unpin();
    pinnedEl = el;
    lastHovered = el;
    el.classList.add(PINNED);
    // 钉住气泡：只发轻量快照（原生侧固定 HUD，不再开侧栏）。
    post({ type: 'pinned', payload: snapshot(el, false) });
    return true;
  }
  function resolvePinTarget(e) {
    // 未钉住：优先当前悬停目标。已钉住：按点击位置换钉。
    if (!pinnedEl && lastHovered && lastHovered.nodeType === 1) { return lastHovered; }
    var el = null;
    if (e && typeof e.clientX === 'number') {
      try { el = pickElementAt(e.clientX, e.clientY); } catch (err) { el = null; }
    }
    if ((!el || el.nodeType !== 1) && e) { el = e.target; }
    if (el === document.documentElement || el === document.body) { return null; }
    return el;
  }
  function onPinGesture(e) {
    if (!e) { return; }
    if (typeof e.button === 'number' && e.button !== 0) { return; }
    var el = resolvePinTarget(e);
    if (!el) { return; } // 钉不住时不吞事件
    e.preventDefault();
    e.stopImmediatePropagation();
    pinElement(el);
  }
  function onKey(e) {
    if (e.key !== 'Escape') { return; }
    e.preventDefault();
    e.stopImmediatePropagation();
    post({ type: 'cancelled' });
    cleanup();
  }
  function cleanup() {
    window.removeEventListener('mouseover', onOver, true);
    window.removeEventListener('mousedown', onPinGesture, true);
    window.removeEventListener('pointerdown', onPinGesture, true);
    window.removeEventListener('click', onPinGesture, true);
    window.removeEventListener('mouseover', onOver, false);
    window.removeEventListener('mousedown', onPinGesture, false);
    window.removeEventListener('pointerdown', onPinGesture, false);
    window.removeEventListener('click', onPinGesture, false);
    window.removeEventListener('pointermove', onPointerMove, true);
    window.removeEventListener('pointermove', onPointerMove, false);
    window.removeEventListener('mousemove', onPointerMove, true);
    window.removeEventListener('mousemove', onPointerMove, false);
    window.removeEventListener('keydown', onKey, true);
    document.removeEventListener('mouseover', onOver, true);
    document.removeEventListener('mousedown', onPinGesture, true);
    document.removeEventListener('pointerdown', onPinGesture, true);
    document.removeEventListener('click', onPinGesture, true);
    document.removeEventListener('keydown', onKey, true);
    if (observer) { try { observer.disconnect(); } catch (e) {} observer = null; }
    if (rafFallback) { clearTimeout(rafFallback); rafFallback = null; }
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
    clearHover();
    unpin();
    var s = document.getElementById(STYLE_ID);
    if (s) { s.remove(); }
    window.__meoDomInspectorStop = null;
  }
  // 原生气泡「关闭」：解除钉住，恢复悬停跟随。
  window.__meoDomInspectorUnpin = function () {
    if (!window.__meoDomInspectorStop) { return; }
    unpin();
    clearHover();
    lastHovered = null;
    pendingEl = null;
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
    if (rafFallback) { clearTimeout(rafFallback); rafFallback = null; }
    frame = null;
  };
  // 原生气泡点「复制」：钉住当前悬停元素，停止跟随。
  window.__meoDomInspectorPinLast = function () {
    if (!window.__meoDomInspectorStop) { return false; }
    var el = pinnedEl || lastHovered;
    if (!el || el.nodeType !== 1) { return false; }
    return pinElement(el);
  };
  // 注册入口：可被反复调用（幂等），供原生侧开/关探针时复用。
  window.__meoDomInspectorStart = function () {
    if (window.__meoDomInspectorStop) { return; }
    ensureStyle();
    // 挂在 window 的捕获阶段：捕获传播自 window 开始，早于 document。
    // 真实站点（bootstrap-table 等）常在 document 上用捕获监听器 +
    // stopImmediatePropagation 抢占事件，若探针也注册在 document 上会被直接跳过。
    window.addEventListener('mouseover', onOver, true);
    // pointerdown / mousedown / click：覆盖站点吞事件与兼容路径。
    window.addEventListener('pointerdown', onPinGesture, true);
    window.addEventListener('mousedown', onPinGesture, true);
    window.addEventListener('click', onPinGesture, true);
    window.addEventListener('keydown', onKey, true);
    // pointermove 采样通道：页面即使吞掉 mouseover/mousedown 也能工作。
    window.addEventListener('pointermove', onPointerMove, true);
    window.addEventListener('pointermove', onPointerMove, false);
    window.addEventListener('mousemove', onPointerMove, true);
    window.addEventListener('mousemove', onPointerMove, false);
    document.addEventListener('mouseover', onOver, true);
    document.addEventListener('pointerdown', onPinGesture, true);
    document.addEventListener('mousedown', onPinGesture, true);
    document.addEventListener('click', onPinGesture, true);
    document.addEventListener('keydown', onKey, true);
    // 自愈：SPA / bootstrap-table 这类会持续重绘并可能清掉探针注入的 <style>。
    // 监听器挂在 window 上不受重绘影响，但样式节点可能被移除，
    // 这里检测到样式丢失就补回去，保证高亮始终可见。
    if (window.MutationObserver && !observer) {
      observer = new MutationObserver(function () {
        if (observerPending) { return; }
        observerPending = true;
        setTimeout(function () {
          observerPending = false;
          if (!window.__meoDomInspectorStop) { return; }
          if (!document.getElementById(STYLE_ID)) { ensureStyle(); }
        }, 250);
      });
      try {
        observer.observe(document.documentElement || document, {childList:true, subtree:true});
      } catch (e) { observer = null; }
    }
    window.__meoDomInspectorStop = cleanup;
  };
  window.__meoDomInspectorImpl = true;
})();