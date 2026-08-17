(function () {
  'use strict';

  if (window.__MeoTranslation) {
    return;
  }

  var STYLE_ID = 'meo-tr-style';
  var TIP_ID = 'meo-tr-hover-tip';
  var ATTR = 'data-meo-tid';
  var CLASS_BI = 'meo-tr-bilingual';
  var hoverMap = Object.create(null);
  var hideTimer = null;
  var tipEl = null;
  var listenersBound = false;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent =
      '.' + CLASS_BI + '{' +
      'display:block;margin-top:0.28em;font-size:0.95em;line-height:1.45;' +
      'color:rgba(60,60,67,0.72);font-weight:400;letter-spacing:normal;' +
      '}' +
      '@media (prefers-color-scheme: dark){.' + CLASS_BI + '{color:rgba(235,235,245,0.55);}}' +
      '#' + TIP_ID + '{' +
      'position:fixed;z-index:2147483646;max-width:min(420px,80vw);' +
      'padding:8px 12px;border-radius:8px;font:13px/1.45 -apple-system,BlinkMacSystemFont,sans-serif;' +
      'color:#fff;background:rgba(28,28,30,0.92);box-shadow:0 8px 24px rgba(0,0,0,0.25);' +
      'pointer-events:none;display:none;white-space:pre-wrap;word-break:break-word;' +
      '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function normalizeText(s) {
    return String(s || '').replace(/\s+/g, ' ').trim();
  }

  /** Skip domains, URL-like strings, and short metadata (unless a full sentence). */
  function isNoisySource(sourceText) {
    var s = normalizeText(sourceText);
    if (!s) {
      return true;
    }
    if (/^https?:\/\//i.test(s) || /^www\./i.test(s)) {
      return true;
    }
    // Pure domain / site label: cnbc.com, news.bbc.co.uk
    if (/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\/?$/i.test(s)) {
      return true;
    }
    if (s.length < 12) {
      // Allow short but sentence-like text (ends with punctuation, or has space + letter).
      var looksLikeSentence = /[.!?…。！？]$/.test(s) ||
        (/\s/.test(s) && /[A-Za-z\u00C0-\u024F]/.test(s));
      if (!looksLikeSentence) {
        return true;
      }
    }
    return false;
  }

  function textMatchesNeedle(text, needle) {
    if (text === needle) {
      return true;
    }
    // Containment only for long needles with similar length (avoid short-token climbs).
    if (needle.length >= 24 && text.indexOf(needle) !== -1) {
      if (text.length <= needle.length * 1.35 + 8) {
        return true;
      }
    }
    return false;
  }

  function isCardishTag(tag) {
    return tag === 'LI' || tag === 'ARTICLE' || tag === 'SECTION' ||
      tag === 'MAIN' || tag === 'ASIDE' || tag === 'NAV' || tag === 'UL' ||
      tag === 'OL' || tag === 'FIGURE';
  }

  function isInlineish(el) {
    if (!el || !el.tagName) {
      return false;
    }
    var tag = el.tagName;
    if (tag === 'A' || tag === 'SPAN' || tag === 'EM' || tag === 'STRONG' ||
        tag === 'B' || tag === 'I' || tag === 'SMALL' || tag === 'LABEL' ||
        tag === 'TIME' || tag === 'ABBR' || tag === 'CITE' || tag === 'CODE' ||
        tag === 'MARK' || tag === 'U' || tag === 'S' || tag === 'SUP' || tag === 'SUB') {
      return true;
    }
    try {
      var display = window.getComputedStyle(el).display;
      return display === 'inline' || display === 'inline-block' || display === 'contents';
    } catch (e) {
      return false;
    }
  }

  /** Prefer direct text wrapper; for links/inline climb at most one non-card level. */
  function pickHost(parent) {
    if (!parent) {
      return null;
    }
    if (!isInlineish(parent)) {
      return parent;
    }
    var up = parent.parentElement;
    if (!up || up === document.body || isCardishTag(up.tagName)) {
      return parent;
    }
    // One sensible level: e.g. A inside H2/P/DIV, not whole LI/article.
    if (up.tagName === 'P' || up.tagName === 'H1' || up.tagName === 'H2' ||
        up.tagName === 'H3' || up.tagName === 'H4' || up.tagName === 'H5' ||
        up.tagName === 'H6' || up.tagName === 'TD' || up.tagName === 'TH' ||
        up.tagName === 'BLOCKQUOTE' || up.tagName === 'FIGCAPTION' ||
        up.tagName === 'DIV' || up.tagName === 'HEADER' || up.tagName === 'FOOTER') {
      return up;
    }
    return parent;
  }

  function hostAlreadyPresented(host) {
    if (!host) {
      return true;
    }
    if (host.getAttribute(ATTR)) {
      return true;
    }
    var sib = host.nextElementSibling;
    if (sib && sib.classList && sib.classList.contains(CLASS_BI)) {
      return true;
    }
    return false;
  }

  function clear() {
    if (hideTimer) {
      clearTimeout(hideTimer);
      hideTimer = null;
    }
    document.querySelectorAll('.' + CLASS_BI).forEach(function (n) {
      n.remove();
    });
    document.querySelectorAll('[' + ATTR + ']').forEach(function (n) {
      n.removeAttribute(ATTR);
    });
    if (tipEl && tipEl.parentNode) {
      tipEl.parentNode.removeChild(tipEl);
    }
    tipEl = null;
    hoverMap = Object.create(null);
    if (listenersBound) {
      document.removeEventListener('mousemove', onMove, true);
      document.removeEventListener('scroll', onScroll, true);
      listenersBound = false;
    }
    return { ok: true };
  }

  function findAnchorForSource(sourceText) {
    var needle = normalizeText(sourceText);
    if (!needle || needle.length < 2 || isNoisySource(needle)) {
      return null;
    }
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var node;
    while ((node = walker.nextNode())) {
      if (!node.parentElement) {
        continue;
      }
      var parent = node.parentElement;
      if (parent.closest('script,style,noscript,textarea,code,pre,.' + CLASS_BI + ',#' + TIP_ID)) {
        continue;
      }
      if (parent.closest('[' + ATTR + '],.' + CLASS_BI)) {
        continue;
      }
      var text = normalizeText(node.nodeValue);
      if (!text) {
        continue;
      }
      if (!textMatchesNeedle(text, needle)) {
        continue;
      }
      return pickHost(parent);
    }
    return null;
  }

  function applyBilingual(units) {
    ensureStyle();
    clear();
    ensureStyle();
    var applied = 0;
    var list = Array.isArray(units) ? units : [];
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || {};
      var id = String(u.id || ('u' + i));
      var source = u.source || '';
      var text = u.text || '';
      if (!text || isNoisySource(source)) {
        continue;
      }
      var host = findAnchorForSource(source);
      if (!host || hostAlreadyPresented(host)) {
        continue;
      }
      host.setAttribute(ATTR, id);
      var row = document.createElement('div');
      row.className = CLASS_BI;
      row.setAttribute(ATTR, id);
      row.textContent = text;
      if (host.nextSibling) {
        host.parentNode.insertBefore(row, host.nextSibling);
      } else {
        host.parentNode.appendChild(row);
      }
      applied += 1;
    }
    return { ok: true, applied: applied, total: list.length };
  }

  function ensureTip() {
    if (tipEl) {
      return tipEl;
    }
    tipEl = document.createElement('div');
    tipEl.id = TIP_ID;
    document.documentElement.appendChild(tipEl);
    return tipEl;
  }

  function showTip(text, x, y) {
    var tip = ensureTip();
    tip.textContent = text;
    tip.style.display = 'block';
    var pad = 14;
    var tw = tip.offsetWidth || 200;
    var th = tip.offsetHeight || 40;
    var left = x + pad;
    var top = y + pad;
    if (left + tw > window.innerWidth - 8) {
      left = Math.max(8, x - tw - pad);
    }
    if (top + th > window.innerHeight - 8) {
      top = Math.max(8, y - th - pad);
    }
    tip.style.left = left + 'px';
    tip.style.top = top + 'px';
  }

  function hideTipSoon() {
    if (hideTimer) {
      clearTimeout(hideTimer);
    }
    hideTimer = setTimeout(function () {
      if (tipEl) {
        tipEl.style.display = 'none';
      }
      hideTimer = null;
    }, 180);
  }

  var lastMove = 0;
  function onMove(ev) {
    var now = Date.now();
    if (now - lastMove < 40) {
      return;
    }
    lastMove = now;
    var el = ev.target;
    if (!el || !el.closest) {
      hideTipSoon();
      return;
    }
    var host = el.closest('[' + ATTR + ']');
    if (!host) {
      hideTipSoon();
      return;
    }
    var id = host.getAttribute(ATTR);
    var text = hoverMap[id];
    if (!text) {
      hideTipSoon();
      return;
    }
    if (hideTimer) {
      clearTimeout(hideTimer);
      hideTimer = null;
    }
    showTip(text, ev.clientX, ev.clientY);
  }

  function onScroll() {
    if (tipEl) {
      tipEl.style.display = 'none';
    }
  }

  function applyHover(units) {
    ensureStyle();
    clear();
    ensureStyle();
    hoverMap = Object.create(null);
    var applied = 0;
    var list = Array.isArray(units) ? units : [];
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || {};
      var id = String(u.id || ('u' + i));
      var source = u.source || '';
      var text = u.text || '';
      if (!text || isNoisySource(source)) {
        continue;
      }
      var host = findAnchorForSource(source);
      if (!host || hostAlreadyPresented(host)) {
        continue;
      }
      host.setAttribute(ATTR, id);
      hoverMap[id] = text;
      applied += 1;
    }
    if (!listenersBound) {
      document.addEventListener('mousemove', onMove, true);
      document.addEventListener('scroll', onScroll, true);
      listenersBound = true;
    }
    return { ok: true, applied: applied, total: list.length };
  }

  window.__MeoTranslation = {
    clear: clear,
    applyBilingual: applyBilingual,
    applyHover: applyHover
  };
})();
