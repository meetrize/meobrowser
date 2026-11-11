/*
 * 彭博去付费墙（Page Pack）
 *
 * 设计目标：
 * - 只解除“页面已经拿到手”的显示限制：付费墙遮罩、订阅弹层、滚动锁、正文裁切、模糊与渐变遮罩；
 * - 不请求任何额外接口，也不伪造订阅状态；
 * - 对 Bloomberg 的 React 重渲染保持幂等，脚本保存后热更新可重复执行。
 *
 * 如果 Bloomberg 在服务端就只下发了前几段正文，本脚本无法补出后面的文字。
 */
(function () {
  'use strict';

  var HIDDEN_ATTR = 'data-meo-bloomberg-hidden';
  var NO_PSEUDO_ATTR = 'data-meo-bloomberg-no-pseudo-gradient';
  var NO_PSEUDO_CLASS = 'meo-bloomberg-no-pseudo-gradient';
  var ARTICLE_CLASS = 'meo-bloomberg-article';

  // 热更新 / 重复注入时先清理上一轮 observer 与 timers。
  var previous = window.__meoBloombergPaywallRemover;
  if (previous && typeof previous.destroy === 'function') {
    try { previous.destroy(); } catch (e) {}
  }

  var HIDE_SELECTORS = [
    '#paywall',
    '#paywall-container',
    '.paywall-overlay',
    '.paywall-modal',
    '.paywall-backdrop',
    '.paywall-gradient',
    '[data-testid="paywall"]',
    '[data-testid="Paywall"]',
    '[data-testid="paywall-container"]',
    '[data-testid="inline-paywall"]',
    '[data-testid="article-paywall"]',
    '[data-testid="paywall-modal"]',
    '[data-component="paywall"]',
    '[data-component="paywall-overlay"]',
    '[class*="paywall-overlay" i]',
    '[class*="paywall-modal" i]',
    '[class*="paywall-backdrop" i]',
    '[class*="paywall-gradient" i]',
    '[class*="PaywallOverlay"]',
    '[class*="PaywallModal"]',
    '[class*="PaywallBackdrop"]',
    '[class*="PaywallGradient"]',
    '[class*="regwall" i]',
    '[class*="reg-wall" i]',
    'tp-modal',
    'tp-backdrop',
    'tp-iframe-wrapper',
    'iframe[src*="tinypass"]',
    'iframe[src*="piano"]'
  ];

  // 属性名里出现这些词，基本可以判定为付费墙相关节点。
  var TOKEN_RE = /(paywall|pay-wall|metered|regwall|reg-wall|subscription-wall|subscribe-wall|piano|tinypass|tp-modal|tp-backdrop)/i;

  // 带这些词的 class/id 更可能是正文容器，而不是遮罩。
  var CONTENT_HINT_RE = /(content|article|body|story|paragraph|text|copy)/i;

  var CTA_RE = /(subscribe|subscription|already a subscriber|sign in|log in|create a (free )?account|continue reading|to continue reading|for subscribers|订阅|付费|登录|注册|继续阅读)/i;

  var LOCK_CLASS_RE = /(paywall|regwall|metered|no-?scroll|noscroll|lock-?scroll|scroll-?lock|modal-?open|overflow-?hidden)/i;

  var state = {
    observer: null,
    sweepTimer: null,
    timers: [],
    lastGradientScan: 0,
    lastBackdropScan: 0,
    lastDeepScan: 0,
    deepScanCount: 0,
    destroyed: false
  };

  window.__meoBloombergPaywallRemover = state;

  function queryAll(selector, root) {
    try {
      return Array.prototype.slice.call((root || document).querySelectorAll(selector));
    } catch (e) {
      return [];
    }
  }

  function computedStyle(el, pseudo) {
    try {
      return window.getComputedStyle ? window.getComputedStyle(el, pseudo || null) : null;
    } catch (e) {
      return null;
    }
  }

  function attrString(el) {
    var className = '';
    if (typeof el.className === 'string') {
      className = el.className;
    } else if (el.className && typeof el.className.baseVal === 'string') {
      className = el.className.baseVal;
    }
    return [
      el.tagName || '',
      el.id || '',
      className,
      el.getAttribute('data-testid') || '',
      el.getAttribute('data-component') || '',
      el.getAttribute('role') || '',
      el.getAttribute('aria-label') || '',
      el.getAttribute('name') || ''
    ].join(' ');
  }

  function findArticleRoot() {
    var candidates = [
      'main article',
      '.body-content',
      '[data-component="article-body"]',
      '[data-testid="article-body"]',
      '[data-testid="articleBody"]',
      '[data-testid="body-content"]',
      'article',
      'main'
    ];
    for (var i = 0; i < candidates.length; i++) {
      var el = document.querySelector(candidates[i]);
      if (el) {
        return el;
      }
    }
    return null;
  }

  function containsArticle(el, root) {
    return !!root && (el === root || el.contains(root));
  }

  function hideElement(el, root) {
    if (!el || el.nodeType !== 1) return;
    if (el === document.documentElement || el === document.body) return;
    // 绝不能把包含正文的容器整块隐藏。
    if (containsArticle(el, root)) return;
    if (el.getAttribute(HIDDEN_ATTR) === '1') return;
    el.setAttribute(HIDDEN_ATTR, '1');
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function hideKnown(root) {
    queryAll(HIDE_SELECTORS.join(',')).forEach(function (el) {
      hideElement(el, root);
    });

    // class / id / data-testid 里带 paywall 的节点，需要区分“遮罩”和“正文容器”。
    queryAll('[class*="paywall" i], [id*="paywall" i], [data-testid*="paywall" i], ' +
             '[class*="regwall" i], [class*="metered" i]').forEach(function (el) {
      if (!el || el.nodeType !== 1) return;
      if (el === root || el.contains(root)) return;
      if (el.getAttribute(HIDDEN_ATTR) === '1') return;

      var cs = computedStyle(el);
      if (!cs) return;

      // 浮层优先处理，哪怕它的 class 里带 content 字样。
      if (cs.position === 'fixed' || cs.position === 'absolute' || cs.position === 'sticky') {
        hideElement(el, root);
        return;
      }

      var text = '';
      try { text = (el.innerText || '').trim(); } catch (e) { text = ''; }

      // 静态容器如果包含正文段落/较长文本，不整块隐藏。
      if (text.length >= 200 && el.querySelector && el.querySelector('p')) return;

      // 有文字但不是订阅文案，更像是正文里的样式钩子，保留。
      if (text.length > 0 && !CTA_RE.test(text)) return;

      hideElement(el, root);
    });
  }

  function clearLockClasses(el) {
    if (!el || !el.classList) return;
    Array.prototype.slice.call(el.classList).forEach(function (token) {
      if (LOCK_CLASS_RE.test(token)) {
        el.classList.remove(token);
      }
    });
  }

  function unlockScroll(root) {
    [document.documentElement, document.body].forEach(function (el) {
      if (!el) return;
      clearLockClasses(el);
      // 一些滚动锁会把 html/body 设成 fixed + top:-Npx，或固定高度。
      // 文章页上直接恢复成正常文档流，最稳。
      el.style.setProperty('position', 'static', 'important');
      el.style.setProperty('top', 'auto', 'important');
      el.style.setProperty('left', 'auto', 'important');
      el.style.setProperty('right', 'auto', 'important');
      el.style.setProperty('bottom', 'auto', 'important');
      el.style.setProperty('height', 'auto', 'important');
      el.style.setProperty('max-height', 'none', 'important');
      el.style.setProperty('overflow', 'auto', 'important');
      el.style.setProperty('overflow-y', 'auto', 'important');
      el.style.setProperty('overscroll-behavior-y', 'auto', 'important');
      el.style.setProperty('touch-action', 'auto', 'important');
      el.style.setProperty('transform', 'none', 'important');

      // 有些“黑层”其实是 html/body 上的 brightness/contrast/grayscale 滤镜。
      var bodyStyle = computedStyle(el);
      if (bodyStyle && bodyStyle.filter && bodyStyle.filter !== 'none') {
        el.style.setProperty('filter', 'none', 'important');
      }
    });

    var node = root ? root.parentElement : null;
    var guard = 0;
    while (node && node !== document.body && node !== document.documentElement && guard < 24) {
      guard++;
      clearLockClasses(node);
      var cs = computedStyle(node);
      if (cs) {
        if (cs.overflowY === 'hidden') {
          node.style.setProperty('overflow-y', 'visible', 'important');
        }
        if (cs.maxHeight !== 'none' && (cs.overflowY === 'hidden' || cs.overflow === 'hidden')) {
          node.style.setProperty('max-height', 'none', 'important');
          node.style.setProperty('overflow', 'visible', 'important');
        }
        if (cs.filter && /(blur|brightness|contrast|grayscale|saturate)/i.test(cs.filter)) {
          node.style.setProperty('filter', 'none', 'important');
        }

        // 某些 paywall 会把正文塞进一个全屏 fixed/absolute 容器里，
        // 这个容器自己限制滚动；把它还原成普通文档流。
        if (cs.position === 'fixed' || cs.position === 'absolute') {
          var rect = node.getBoundingClientRect();
          var vw = window.innerWidth || 0;
          var vh = window.innerHeight || 0;
          if (rect.width >= vw * 0.9 && rect.height >= vh * 0.9) {
            node.style.setProperty('position', 'static', 'important');
            node.style.setProperty('top', 'auto', 'important');
            node.style.setProperty('left', 'auto', 'important');
            node.style.setProperty('right', 'auto', 'important');
            node.style.setProperty('bottom', 'auto', 'important');
            node.style.setProperty('height', 'auto', 'important');
            node.style.setProperty('max-height', 'none', 'important');
            node.style.setProperty('overflow', 'visible', 'important');
            node.style.setProperty('transform', 'none', 'important');
          }
        }
      }
      node = node.parentElement;
    }
  }

  function revealElement(el) {
    if (!el || el.nodeType !== 1) return;
    if (el.getAttribute(HIDDEN_ATTR) === '1') return;

    if (el.getAttribute('aria-hidden') === 'true') {
      el.removeAttribute('aria-hidden');
    }
    if (el.hasAttribute && el.hasAttribute('inert')) {
      el.removeAttribute('inert');
    }

    var cs = computedStyle(el);
    if (!cs) return;
    if (cs.display === 'none') {
      el.style.setProperty('display', 'block', 'important');
    }
    if (cs.visibility === 'hidden') {
      el.style.setProperty('visibility', 'visible', 'important');
    }
    if (parseFloat(cs.opacity) === 0) {
      el.style.setProperty('opacity', '1', 'important');
    }
    if (cs.maxHeight !== 'none' && (cs.overflowY === 'hidden' || cs.overflow === 'hidden')) {
      el.style.setProperty('max-height', 'none', 'important');
      el.style.setProperty('overflow', 'visible', 'important');
    }
    if (cs.filter && /(blur|brightness|contrast|grayscale|saturate)/i.test(cs.filter)) {
      el.style.setProperty('filter', 'none', 'important');
    }
  }

  function revealArticle(root) {
    if (!root) return;

    // 文章根节点及其祖先
    var chain = [];
    var node = root;
    var guard = 0;
    while (node && node !== document.documentElement && guard < 24) {
      chain.push(node);
      node = node.parentElement;
      guard++;
    }
    chain.forEach(revealElement);

    // 正文内部被隐藏的段落，以及它们被隐藏的中间层
    queryAll('p, h1, h2, h3, h4, h5, blockquote, figure, figcaption, ul, ol', root).forEach(function (el) {
      if (el.getAttribute(HIDDEN_ATTR) === '1') return;
      revealElement(el);

      var parent = el.parentElement;
      var depth = 0;
      while (parent && parent !== root && parent !== document.body && depth < 12) {
        depth++;
        revealElement(parent);
        parent = parent.parentElement;
      }
    });
  }

  function markArticlePage(root) {
    var html = document.documentElement;
    if (!html || !html.classList) return;
    if (root) {
      html.classList.add(ARTICLE_CLASS);
    } else {
      html.classList.remove(ARTICLE_CLASS);
    }
  }

  function rectsOverlap(a, b) {
    return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  }

  function backgroundHasGradient(cs) {
    var bg = (cs.backgroundImage || '') + ' ' + (cs.background || '');
    return bg.indexOf('gradient') >= 0;
  }

  function hasGradientPseudo(el) {
    if (!el || el.nodeType !== 1) return false;
    var pseudos = ['::before', '::after'];
    for (var i = 0; i < pseudos.length; i++) {
      var cs = computedStyle(el, pseudos[i]);
      if (!cs) continue;
      var content = cs.content;
      if (content === 'none' || content === 'normal') continue;
      if (cs.position !== 'absolute' && cs.position !== 'fixed') continue;
      if (backgroundHasGradient(cs)) return true;
    }
    return false;
  }

  // 检测“半透明黑 / 深色 / 模糊”的全屏伪元素遮罩。
  function hasDarkOverlayPseudo(el, allowStatic) {
    if (!el || el.nodeType !== 1) return false;
    var pseudos = ['::before', '::after'];
    for (var i = 0; i < pseudos.length; i++) {
      var cs = computedStyle(el, pseudos[i]);
      if (!cs) continue;
      var content = cs.content;
      if (content === 'none' || content === 'normal') continue;

      var positioned = cs.position === 'fixed' || cs.position === 'absolute';
      var staticish = cs.position === 'relative' || cs.position === 'static';
      if (!positioned && !(allowStatic && staticish)) continue;

      var bg = (cs.backgroundColor || '').toLowerCase();
      var img = (cs.backgroundImage || '').toLowerCase();
      var alpha = parseColorAlpha(bg);
      var dark = (alpha > 0 && alpha < 1) || /rgb\(\s*0\s*,\s*0\s*,\s*0/i.test(bg);
      var gradient = img.indexOf('gradient') >= 0;
      var blurred = !!(cs.backdropFilter && cs.backdropFilter !== 'none');
      if (!(dark || gradient || blurred)) continue;

      var vw = window.innerWidth || 0;
      var vh = window.innerHeight || 0;
      var pw = parseFloat(cs.width);
      var ph = parseFloat(cs.height);
      var insetFull = cs.top === '0px' && cs.right === '0px' && cs.bottom === '0px' && cs.left === '0px';
      var big = (pw >= vw * 0.8 && ph >= vh * 0.4) || (pw >= vw * 0.8 && ph >= 200);

      if (positioned && (insetFull || big)) return true;
      if (allowStatic && pw >= vw * 0.9 && ph >= vh * 0.5) return true;
    }
    return false;
  }

  // 有些实现把半透明黑背景直接放在 html/body 或正文祖先上。
  function clearDarkTranslucentBackground(el) {
    if (!el || el.nodeType !== 1) return;
    var cs = computedStyle(el);
    if (!cs) return;
    var bg = (cs.backgroundColor || '').toLowerCase();
    if (!bg || bg === 'transparent') return;
    var alpha = parseColorAlpha(bg);
    var dark = /rgba?\(\s*0\s*,\s*0\s*,\s*0/i.test(bg) || /#0{3,6}\b/i.test(bg);
    if (dark && alpha > 0 && alpha < 1) {
      el.style.setProperty('background-color', 'transparent', 'important');
    }
  }

  // 超大扩散半径的 box-shadow 常被用来伪造全屏遮罩。
  function removeHugeBoxShadow(el) {
    if (!el || el.nodeType !== 1) return;
    var cs = computedStyle(el);
    if (!cs) return;
    var shadow = cs.boxShadow || '';
    if (!shadow || shadow === 'none') return;

    var huge = false;
    var re = /(-?\d+(?:\.\d+)?)(px|rem|em|vh|vw|vmax|vmin)/g;
    var m;
    while ((m = re.exec(shadow))) {
      var n = Math.abs(parseFloat(m[1]));
      var unit = m[2];
      if (unit === 'px' && n >= 400) huge = true;
      if ((unit === 'rem' || unit === 'em') && n * 16 >= 400) huge = true;
      if ((unit === 'vmax' || unit === 'vw' || unit === 'vh') && n >= 50) huge = true;
    }
    if (huge || shadow.indexOf('100vmax') >= 0 || shadow.indexOf('9999') >= 0) {
      el.style.setProperty('box-shadow', 'none', 'important');
      el.style.setProperty('-webkit-box-shadow', 'none', 'important');
    }
  }

  // 原生 <dialog open> / top-layer 元素的 ::backdrop 常是黑色遮罩。
  function hideNativeDialogs(root) {
    function hideIfSafe(el) {
      if (!el) return;
      if (root && (el === root || el.contains(root))) return;
      hideElement(el, root);
    }
    queryAll('dialog[open]').forEach(hideIfSafe);
    queryAll(':modal').forEach(hideIfSafe);
    queryAll('[popover]:popover-open').forEach(hideIfSafe);
  }

  function markNoPseudoGradient(el) {
    if (!el || el.nodeType !== 1) return;
    if (el.getAttribute(NO_PSEUDO_ATTR) === '1') return;
    el.setAttribute(NO_PSEUDO_ATTR, '1');
    if (el.classList) {
      el.classList.add(NO_PSEUDO_CLASS);
    }
  }

  function isPaywallLike(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el === document.documentElement || el === document.body) return false;

    var attr = attrString(el);
    var text = '';
    try { text = (el.innerText || '').trim(); } catch (e) { text = ''; }
    if (text.length > 4000) return false;

    var hasToken = TOKEN_RE.test(attr);
    var hasCTA = CTA_RE.test(text);

    // 带 paywall 语义且不像正文容器的节点，直接判定。
    if (hasToken && !CONTENT_HINT_RE.test(attr)) return true;

    if (!text || !hasCTA) return false;

    var role = (el.getAttribute('role') || '').toLowerCase();
    if (role === 'dialog' || el.getAttribute('aria-modal') === 'true') {
      return true;
    }

    var cs = computedStyle(el);
    if (!cs) return false;
    if (cs.position !== 'fixed' && cs.position !== 'absolute') return false;

    var rect = el.getBoundingClientRect();
    var vw = window.innerWidth || 0;
    var vh = window.innerHeight || 0;
    if (rect.width < 120 || rect.height < 24) return false;

    // 大遮罩 / 居中弹窗
    if (rect.width >= vw * 0.4 && rect.height >= vh * 0.2) return true;

    // 底部固定订阅条
    if (rect.width >= vw * 0.6 && rect.top >= vh * 0.5) return true;

    // 顶部/中部较大的固定订阅条
    if (rect.width >= vw * 0.6 && rect.height >= vh * 0.12) return true;

    return false;
  }

  // 对没有稳定 selector 的弹层：从视口几个采样点向上找“像付费墙”的节点。
  function hideViewportOverlays(root) {
    if (!root || !document.elementsFromPoint) return;
    var vw = window.innerWidth || 0;
    var vh = window.innerHeight || 0;
    if (vw < 320 || vh < 320) return;

    var points = [
      [vw * 0.5, vh * 0.5],
      [vw * 0.5, vh * 0.25],
      [vw * 0.5, vh * 0.75],
      [vw * 0.2, vh * 0.5],
      [vw * 0.8, vh * 0.5]
    ];

    points.forEach(function (point) {
      var stack = [];
      try { stack = document.elementsFromPoint(point[0], point[1]) || []; } catch (e) { stack = []; }

      for (var i = 0; i < stack.length; i++) {
        var el = stack[i];
        if (!el || el.nodeType !== 1) continue;
        if (el === root) break;

        var node = el;
        var guard = 0;
        while (node && node !== document.body && node !== document.documentElement && guard < 12) {
          guard++;
          if (node === root) break;
          if (isBackdropLike(node, root) || isPaywallLike(node)) {
            hideElement(node, root);
            break;
          }
          node = node.parentElement;
        }

        // 采样点已经落到正文内容上，下面的 stack 不用再看了。
        if (root.contains(el)) break;
      }
    });
  }

  function parseColorAlpha(color) {
    var value = color || '';
    var match = /rgba?\(([^)]+)\)/i.exec(value);
    if (!match) return 1;
    var parts = match[1].split(',');
    if (parts.length < 4) return 1;
    var alpha = parseFloat(parts[3]);
    return isNaN(alpha) ? 1 : alpha;
  }

  // 识别没有 paywall 语义的全屏深色/半透明 backdrop。
  function isBackdropLike(el, root, allowStatic) {
    if (!el || el.nodeType !== 1) return false;
    if (el === document.documentElement || el === document.body) return false;
    if (root && (el === root || el.contains(root))) return false;
    if (el.getAttribute(HIDDEN_ATTR) === '1') return false;

    var cs = computedStyle(el);
    if (!cs) return false;
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;

    var rect = el.getBoundingClientRect();
    var vw = window.innerWidth || 0;
    var vh = window.innerHeight || 0;
    if (vw < 320 || vh < 320) return false;

    var tag = (el.tagName || '').toUpperCase();
    var isMedia = tag === 'IMG' || tag === 'VIDEO' || tag === 'CANVAS' || tag === 'IFRAME' || tag === 'SVG' || tag === 'PICTURE';
    // 正文里的封面图/视频/交互画布不要误伤。
    if (isMedia && root && root.contains(el)) return false;

    var positioned = cs.position === 'fixed' || cs.position === 'absolute' || cs.position === 'sticky';
    if (!positioned) {
      if (!allowStatic) return false;
      // 非定位元素只有在几乎完全覆盖视口时才当作遮罩。
      if (rect.width < vw * 0.95 || rect.height < vh * 0.95) return false;
    } else if (rect.width < vw * 0.85 || rect.height < vh * 0.85) {
      return false;
    }

    var z = parseInt(cs.zIndex, 10);
    if (!isNaN(z) && z < 0) return false;

    var text = '';
    try { text = (el.innerText || '').trim(); } catch (e) { text = ''; }

    var bg = (cs.backgroundColor || '').toLowerCase();
    var bgImage = (cs.backgroundImage || '').toLowerCase();
    var alpha = parseColorAlpha(bg);
    var semiTransparent = alpha > 0 && alpha < 1;
    var opaqueBlack = /rgb\(\s*0\s*,\s*0\s*,\s*0\s*\)/i.test(bg);
    var darkGradient = bgImage.indexOf('gradient') >= 0 && /rgba?\(\s*0\s*,\s*0\s*,\s*0/i.test(bgImage);
    var blurred = !!(cs.backdropFilter && cs.backdropFilter !== 'none');
    var loweredOpacity = parseFloat(cs.opacity) > 0 && parseFloat(cs.opacity) < 1;

    var hasDarkBackground = semiTransparent || opaqueBlack || darkGradient || blurred || loweredOpacity;
    if (!hasDarkBackground) {
      // 全屏的 top-layer 媒体/画布/iframe，通常是遮罩或背景层。
      if (allowStatic && isMedia && !text) return true;
      return false;
    }

    // 仅靠 opacity/backdrop-filter 的容器如果含大量文字，可能是一个完整的弹窗，
    // 交给 isPaywallLike 处理；纯色/半透明遮罩则即使包着弹窗也可以整块隐藏。
    if (!(semiTransparent || opaqueBlack || darkGradient) && text.length > 80) return false;

    return true;
  }

  function collectBackdropCandidates(root) {
    var list = [];
    var seen = [];
    function add(el) {
      if (!el || el.nodeType !== 1) return;
      if (seen.indexOf(el) >= 0) return;
      seen.push(el);
      list.push(el);
    }

    // body 及其 portal 容器的一到两层子节点（React portal 常把遮罩挂在这里）。
    if (document.body) {
      Array.prototype.slice.call(document.body.children).forEach(function (child) {
        add(child);
        Array.prototype.slice.call(child.children).forEach(add);
      });
    }

    // 正文祖先的兄弟节点。
    var node = root;
    var guard = 0;
    while (node && node !== document.body && node !== document.documentElement && guard < 8) {
      guard++;
      var parent = node.parentElement;
      if (parent) {
        Array.prototype.slice.call(parent.children).forEach(add);
      }
      node = parent;
    }

    // 常见遮罩语义 + 内联 fixed / 黑色背景。
    queryAll('[role="presentation"], [aria-hidden="true"], [class*="backdrop" i], ' +
             '[class*="overlay" i], [class*="scrim" i], [class*="mask" i], ' +
             '[class*="modal" i], [class*="paywall" i], ' +
             '[style*="position: fixed"], [style*="position:fixed"], ' +
             '[style*="rgba(0, 0, 0"], [style*="rgba(0,0,0"], ' +
             '[style*="background: #000"], [style*="background:#000"]').forEach(add);

    // React portal 里可能还有更深一层遮罩。
    queryAll('#portal, [id*="portal" i], [class*="portal" i]').forEach(function (portal) {
      queryAll('div, section, aside', portal).forEach(add);
    });

    return list;
  }

  function hideBackdrops(root) {
    if (!root || state.destroyed) return;
    var now = Date.now ? Date.now() : new Date().getTime();
    if (now - state.lastBackdropScan < 400) return;
    state.lastBackdropScan = now;

    // html/body 以及正文祖先：处理超大 box-shadow、半透明黑背景和伪元素遮罩。
    [document.documentElement, document.body].forEach(function (el) {
      if (!el) return;
      removeHugeBoxShadow(el);
      clearDarkTranslucentBackground(el);
      if (hasDarkOverlayPseudo(el)) markNoPseudoGradient(el);
    });

    var ancestor = root;
    var guard = 0;
    while (ancestor && guard < 24) {
      guard++;
      removeHugeBoxShadow(ancestor);
      clearDarkTranslucentBackground(ancestor);
      if (hasDarkOverlayPseudo(ancestor)) markNoPseudoGradient(ancestor);
      ancestor = ancestor.parentElement;
    }

    var candidates = collectBackdropCandidates(root);
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      removeHugeBoxShadow(el);

      if (isBackdropLike(el, root)) {
        hideElement(el, root);
      } else if (hasDarkOverlayPseudo(el)) {
        // 遮罩是伪元素时无法隐藏元素本身（会误伤内容），改用 class 清掉伪元素背景。
        markNoPseudoGradient(el);
      }
    }

    // 兜底：深层匿名遮罩/伪元素不在候选里时，前几轮做有限次全页深扫。
    if (state.deepScanCount < 3 && now - state.lastDeepScan >= 2500) {
      state.lastDeepScan = now;
      state.deepScanCount++;
      deepScanBackdrops(root);
    }
  }

  function deepScanBackdrops(root) {
    if (!root || state.destroyed) return;
    var all = queryAll('div, section, aside, header, footer, main, article, form, dialog, ' +
                       'span, iframe, video, img, picture, canvas, svg, [role]', document);
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (!el || el.nodeType !== 1) continue;
      if (el === document.documentElement || el === document.body) continue;

      removeHugeBoxShadow(el);

      if (isBackdropLike(el, root, true)) {
        hideElement(el, root);
      } else if (hasDarkOverlayPseudo(el, true)) {
        markNoPseudoGradient(el);
      } else if (isLargeLayer(el)) {
        clearDarkTranslucentBackground(el);
      }
    }
  }

  function isLargeLayer(el) {
    if (!el || el.nodeType !== 1) return false;
    var rect = el.getBoundingClientRect();
    var vw = window.innerWidth || 0;
    var vh = window.innerHeight || 0;
    return vw > 0 && vh > 0 && rect.width >= vw * 0.6 && rect.height >= vh * 0.3;
  }

  // 只收集“可能在正文附近”的候选，避免整页 getAllComputedStyle。
  function collectGradientCandidates(root) {
    var list = [];
    var seen = [];
    function add(el) {
      if (!el || el.nodeType !== 1) return;
      if (seen.indexOf(el) >= 0) return;
      seen.push(el);
      list.push(el);
    }

    // 正文内部
    queryAll('div, section, aside', root).forEach(add);

    // 正文祖先的兄弟节点（渐变遮罩常与正文平级）
    var node = root;
    var guard = 0;
    while (node && node !== document.body && node !== document.documentElement && guard < 8) {
      guard++;
      var parent = node.parentElement;
      if (parent) {
        Array.prototype.slice.call(parent.children).forEach(add);
      }
      node = parent;
    }

    // body 顶层的全屏遮罩
    if (document.body) {
      Array.prototype.slice.call(document.body.children).forEach(add);
    }

    // 带 gradient / fade / paywall 语义的节点，层级可能更深
    queryAll('[class*="gradient" i], [class*="fade" i], [class*="paywall" i], ' +
             '[data-testid*="gradient" i], [data-testid*="fade" i], [data-testid*="paywall" i]').forEach(add);

    return list;
  }

  function hideGradientOverlays(root) {
    if (!root || state.destroyed) return;
    var now = Date.now ? Date.now() : new Date().getTime();
    if (now - state.lastGradientScan < 400) return;
    state.lastGradientScan = now;

    var rootRect = root.getBoundingClientRect();
    if (rootRect.width < 80 || rootRect.height < 80) return;

    var candidates = collectGradientCandidates(root);
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      if (!el || el.nodeType !== 1) continue;
      if (el === document.documentElement || el === document.body) continue;

      // 包含正文的容器不能隐藏，但可以去掉它身上的渐变伪元素。
      if (el === root || el.contains(root)) {
        if (hasGradientPseudo(el)) markNoPseudoGradient(el);
        continue;
      }

      if (el.getAttribute(HIDDEN_ATTR) === '1') continue;

      var cs = computedStyle(el);
      if (!cs) continue;

      var rect = el.getBoundingClientRect();
      if (rect.width < 80 || rect.height < 6) continue;
      if (!rectsOverlap(rect, rootRect)) continue;

      var text = '';
      try { text = (el.innerText || '').trim(); } catch (e) { text = ''; }
      if (text.length > 160) continue;
      if (el.closest && el.closest('figure, picture, video, nav, form')) continue;

      var coversWidth = rect.width >= rootRect.width * 0.55;
      var nearBottom = rect.top >= rootRect.top + rootRect.height * 0.4;
      var nearTop = rect.bottom <= rootRect.top + rootRect.height * 0.25;
      var coversViewport = rect.height >= (window.innerHeight || 0) * 0.25;
      var pointerNone = cs.pointerEvents === 'none';
      if (!(coversWidth && (nearBottom || nearTop || coversViewport || pointerNone))) continue;

      if (backgroundHasGradient(cs)) {
        if (cs.position !== 'absolute' && cs.position !== 'fixed' && cs.position !== 'sticky') continue;
        hideElement(el, root);
      } else if (hasGradientPseudo(el)) {
        markNoPseudoGradient(el);
      }
    }
  }

  function sweep() {
    if (state.destroyed) return;

    var observer = state.observer;
    // sweep 自己会改 style/attribute，先断开 observer，避免自触发循环。
    if (observer) {
      try { observer.disconnect(); } catch (e) {}
    }

    try {
      var root = findArticleRoot();
      markArticlePage(root);
      hideKnown(root);
      hideNativeDialogs(root);
      unlockScroll(root);
      revealArticle(root);
      hideViewportOverlays(root);
      hideBackdrops(root);
      hideGradientOverlays(root);
    } catch (e) {
      // 页面结构千变万化，单次 sweep 失败不应影响阅读。
    } finally {
      if (observer && !state.destroyed) {
        observe(observer);
      }
    }
  }

  function observe(observer) {
    try {
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['style', 'class', 'hidden', 'aria-hidden', 'inert']
      });
    } catch (e) {}
  }

  function scheduleSweep() {
    if (state.destroyed || state.sweepTimer) return;
    state.sweepTimer = setTimeout(function () {
      state.sweepTimer = null;
      sweep();
    }, 120);
  }

  function addTimer(ms) {
    if (state.destroyed) return;
    var timer = setTimeout(function () {
      var idx = state.timers.indexOf(timer);
      if (idx >= 0) {
        state.timers.splice(idx, 1);
      }
      sweep();
    }, ms);
    state.timers.push(timer);
  }

  state.destroy = function () {
    state.destroyed = true;
    if (state.observer) {
      try { state.observer.disconnect(); } catch (e) {}
      state.observer = null;
    }
    if (state.sweepTimer) {
      clearTimeout(state.sweepTimer);
      state.sweepTimer = null;
    }
    while (state.timers.length) {
      clearTimeout(state.timers.pop());
    }
    document.removeEventListener('DOMContentLoaded', sweep);
    window.removeEventListener('load', sweep);
  };

  // 立即跑一次，再在常见的延迟渲染时间点补扫。
  sweep();

  if (window.MutationObserver && document.documentElement) {
    state.observer = new MutationObserver(function () {
      if (!state.destroyed) {
        scheduleSweep();
      }
    });
    observe(state.observer);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', sweep, { once: true });
  }
  window.addEventListener('load', sweep, { once: true });

  [150, 400, 900, 1800, 3200, 6000, 10000].forEach(addTimer);
})();
