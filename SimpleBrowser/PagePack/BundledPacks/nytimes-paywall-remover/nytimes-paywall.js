/*
 * 纽约时报去付费墙（Page Pack）
 *
 * 设计目标：
 * - 只解除“页面已经拿到手”的显示限制：付费墙遮罩、订阅弹层、滚动锁、正文裁切；
 * - 不请求任何额外接口，也不伪造订阅状态；
 * - 对 NYT 的 React 重渲染保持幂等，脚本保存后热更新可重复执行。
 *
 * 如果 NYTimes 在服务端就只下发了前几段正文，本脚本无法补出后面的文字。
 */
(function () {
  'use strict';

  // 热更新 / 重复注入时先清理上一轮 observer 与 timers。
  var previous = window.__meoNYTPaywallRemover;
  if (previous && typeof previous.destroy === 'function') {
    try { previous.destroy(); } catch (e) {}
  }

  var HIDE_SELECTORS = [
    '#gateway-content',
    '#paywall',
    '#piano-inline-content-wrapper',
    '#tp-modal',
    '#tp-backdrop',
    '#tp-iframe-wrapper',
    '[data-testid="gateway-content"]',
    '[data-testid="paywall"]',
    '[data-testid="Paywall"]',
    '[data-testid="inline-message"]',
    '[data-testid="InlineMessage"]',
    '[data-testid="regwall"]',
    '[data-testid="Regwall"]',
    '[data-testid="modal-container"]',
    '[data-testid="piano-inline-content-wrapper"]',
    '[data-testid="article-paywall"]',
    '.piano-inline-content-wrapper',
    'tp-modal',
    'tp-backdrop',
    'tp-iframe-wrapper',
    'iframe[src*="tinypass"]',
    'iframe[src*="piano"]'
  ];

  // 属性名里出现这些词，基本可以判定为付费墙相关节点。
  var TOKEN_RE = /(paywall|pay-wall|gateway-content|metered|regwall|reg-wall|piano|tinypass|tp-modal|tp-backdrop|subscribe-wall|subscription-wall)/i;

  // 弹层里常见的订阅/登录文案，用于补充识别没有语义属性的遮罩。
  var CTA_RE = /(subscribe|subscription|already a subscriber|sign in|log in|create a (free )?account|continue reading|to continue reading|订阅|付费|登录|注册|已是订户|继续阅读)/i;

  // html/body 或正文祖先上的滚动锁 class。
  var LOCK_CLASS_RE = /(paywall|regwall|metered|no-?scroll|noscroll|lock-?scroll|scroll-?lock|modal-?open|overflow-?hidden)/i;

  var state = {
    observer: null,
    sweepTimer: null,
    timers: [],
    destroyed: false
  };

  window.__meoNYTPaywallRemover = state;

  function queryAll(selector, root) {
    try {
      return Array.prototype.slice.call((root || document).querySelectorAll(selector));
    } catch (e) {
      return [];
    }
  }

  function computedStyle(el) {
    try {
      return window.getComputedStyle ? window.getComputedStyle(el) : null;
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
      el.getAttribute('role') || '',
      el.getAttribute('aria-label') || '',
      el.getAttribute('name') || ''
    ].join(' ');
  }

  function findArticleRoot() {
    var candidates = [
      'main article',
      'article[data-testid]',
      'article',
      '[data-testid="article-body"]',
      'section[name="articleBody"]',
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
    if (el.getAttribute('data-meo-nyt-hidden') === '1') return;
    el.setAttribute('data-meo-nyt-hidden', '1');
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function hideKnown(root) {
    queryAll(HIDE_SELECTORS.join(',')).forEach(function (el) {
      hideElement(el, root);
    });

    // class / id / data-testid 里带 paywall、regwall 的节点也处理。
    queryAll('[id*="paywall" i], [class*="paywall" i], [data-testid*="paywall" i], ' +
             '[id*="regwall" i], [class*="regwall" i], [data-testid*="regwall" i]').forEach(function (el) {
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
      var cs = computedStyle(el);
      if (cs && cs.position === 'fixed') {
        // 有些实现把 body 设成 fixed 来锁滚动。
        el.style.setProperty('position', 'static', 'important');
      }
      el.style.setProperty('overflow-y', 'auto', 'important');
      el.style.setProperty('overscroll-behavior-y', 'auto', 'important');
    });

    // 正文祖先上也可能挂着 overflow/max-height 裁切，逐层解开。
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
      }
      node = node.parentElement;
    }
  }

  function revealArticle(root) {
    if (!root) return;

    // 文章根节点及其祖先：去掉 aria-hidden / inert，恢复被隐藏的容器。
    var chain = [];
    var node = root;
    var guard = 0;
    while (node && node !== document.documentElement && guard < 24) {
      chain.push(node);
      node = node.parentElement;
      guard++;
    }

    chain.forEach(function (el) {
      if (!el) return;
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
    });

    // 正文内部被折叠/隐藏的段落也展开。
    queryAll('p, h1, h2, h3, h4, h5, blockquote, figure, figcaption, ul, ol', root).forEach(function (el) {
      if (el.getAttribute('data-meo-nyt-hidden') === '1') return;
      var cs = computedStyle(el);
      if (!cs) return;
      if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) {
        el.style.setProperty('display', 'block', 'important');
        el.style.setProperty('visibility', 'visible', 'important');
        el.style.setProperty('opacity', '1', 'important');
      }
      if (cs.maxHeight !== 'none' && (cs.overflowY === 'hidden' || cs.overflow === 'hidden')) {
        el.style.setProperty('max-height', 'none', 'important');
        el.style.setProperty('overflow', 'visible', 'important');
      }
    });
  }

  function isPaywallLike(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el === document.documentElement || el === document.body) return false;

    if (TOKEN_RE.test(attrString(el))) return true;

    var text = '';
    try { text = (el.innerText || '').trim(); } catch (e) { text = ''; }
    if (!text || text.length > 4000) return false;
    if (!CTA_RE.test(text)) return false;

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
    return rect.width >= vw * 0.4 && rect.height >= vh * 0.2;
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
        // 采样点已经落到正文上，说明前面的遮罩层已经处理完。
        if (el === root || root.contains(el)) break;

        var node = el;
        var guard = 0;
        while (node && node !== document.body && node !== document.documentElement && guard < 12) {
          guard++;
          if (node === root || root.contains(node)) break;
          if (isPaywallLike(node)) {
            hideElement(node, root);
            break;
          }
          node = node.parentElement;
        }
      }
    });
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
      hideKnown(root);
      unlockScroll(root);
      revealArticle(root);
      hideViewportOverlays(root);
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
