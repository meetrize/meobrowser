(function () {
  'use strict';

  // Allow upgrade when an older bridge (without collectCandidates) is already present.
  if (window.__MeoTranslation && typeof window.__MeoTranslation.collectCandidates === 'function') {
    return;
  }
  if (window.__MeoTranslation && typeof window.__MeoTranslation.clear === 'function') {
    try {
      window.__MeoTranslation.clear();
    } catch (e) {
    }
  }

  var STYLE_ID = 'meo-tr-style';
  var TIP_ID = 'meo-tr-hover-tip';
  var ATTR = 'data-meo-tid';
  var CLASS_BI = 'meo-tr-bilingual';
  var COLLECT_CAP = 200;
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
    return String(s || '')
      .replace(/\u00a0/g, ' ')
      .replace(/[\u2018\u2019\u201A\u201B]/g, "'")
      .replace(/[\u201C\u201D\u201E\u201F]/g, '"')
      .replace(/\s+/g, ' ')
      .trim();
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
    // Long-needle containment: prefer hosts where needle is a substantial share of
    // textContent (or the element starts with the needle). No reverse short-string
    // contains (needle.indexOf(text)) — that climbs to card ancestors.
    if (needle.length >= 20 && text.indexOf(needle) !== -1) {
      if (needle.length / text.length >= 0.5 || text.indexOf(needle) === 0) {
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

  /**
   * For collect on list/headline pages, prefer the heading or link itself
   * rather than climbing to a cardish ancestor.
   */
  function pickCollectHost(el) {
    if (!el) {
      return null;
    }
    var tag = el.tagName;
    if (tag === 'H1' || tag === 'H2' || tag === 'H3' || tag === 'H4' ||
        tag === 'H5' || tag === 'H6' || tag === 'A' || tag === 'P') {
      return el;
    }
    if (el.getAttribute &&
        (el.getAttribute('role') === 'heading' || el.getAttribute('role') === 'link')) {
      return el;
    }
    if (tag === 'DIV') {
      return el;
    }
    if (tag === 'SPAN') {
      var spanOwn = ownTextRough(el);
      if (looksLikeHeadline(spanOwn)) {
        return el;
      }
    }
    if (tag === 'LI') {
      var childHeading = el.querySelector('h1,h2,h3,h4,h5,h6,a');
      if (childHeading) {
        var childText = normalizeText(childHeading.textContent);
        if (childText.length >= 20 && !isNoisySource(childText)) {
          return childHeading;
        }
      }
      return el;
    }
    return pickHost(el);
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

  function isSkippedAnchorParent(parent) {
    if (!parent || !parent.closest) {
      return true;
    }
    if (parent.closest('script,style,noscript,textarea,code,pre,.' + CLASS_BI + ',#' + TIP_ID)) {
      return true;
    }
    if (parent.closest('[' + ATTR + '],.' + CLASS_BI)) {
      return true;
    }
    return false;
  }

  function isInSkippedRegion(el) {
    if (!el || !el.closest) {
      return true;
    }
    // Only real <nav>/<footer> chrome — do not treat main story columns as nav.
    if (el.closest('script,style,noscript,textarea,code,pre,nav,footer,.' + CLASS_BI + ',#' + TIP_ID)) {
      return true;
    }
    return false;
  }

  function isCheaplyHidden(el) {
    if (!el) {
      return true;
    }
    if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') {
      return true;
    }
    // Prefer computed style. Do NOT reject solely because offsetParent === null
    // (fixed/sticky/flex children often have a null offsetParent while visible).
    try {
      var style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') {
        return true;
      }
      if (parseFloat(style.opacity) === 0) {
        return true;
      }
    } catch (e) {
      return true;
    }
    return false;
  }

  /** Visit document.body and every open shadowRoot under it. */
  function forEachSearchRoot(visit) {
    function walk(root) {
      if (!root) {
        return;
      }
      visit(root);
      if (!root.querySelectorAll) {
        return;
      }
      var els = root.querySelectorAll('*');
      for (var i = 0; i < els.length; i++) {
        if (els[i].shadowRoot) {
          walk(els[i].shadowRoot);
        }
      }
    }
    walk(document.body);
  }

  /** Fast path: single text node exact / long-needle containment. */
  function findTextNodeHost(needle) {
    var found = null;
    forEachSearchRoot(function (root) {
      if (found || !root) {
        return;
      }
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
      var node;
      while ((node = walker.nextNode())) {
        if (!node.parentElement) {
          continue;
        }
        var parent = node.parentElement;
        if (isSkippedAnchorParent(parent)) {
          continue;
        }
        var text = normalizeText(node.nodeValue);
        if (!text || !textMatchesNeedle(text, needle)) {
          continue;
        }
        found = pickHost(parent);
        return;
      }
    });
    return found;
  }

  /**
   * Element-level match: smallest element whose normalized textContent
   * equals (or, for long needles, substantially contains) the needle.
   */
  function findElementHost(needle) {
    var best = null;
    var bestLen = Infinity;
    forEachSearchRoot(function (root) {
      if (!root || !root.querySelectorAll) {
        return;
      }
      var els = root.querySelectorAll('*');
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        var tag = el.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' ||
            tag === 'TEXTAREA' || tag === 'CODE' || tag === 'PRE') {
          continue;
        }
        if (el.classList && el.classList.contains(CLASS_BI)) {
          continue;
        }
        if (el.id === TIP_ID) {
          continue;
        }
        if (isSkippedAnchorParent(el)) {
          continue;
        }
        var text = normalizeText(el.textContent);
        if (!text || !textMatchesNeedle(text, needle)) {
          continue;
        }
        if (text.length < bestLen) {
          best = el;
          bestLen = text.length;
        }
      }
    });
    return best ? pickHost(best) : null;
  }

  function findAnchorForSource(sourceText) {
    var needle = normalizeText(sourceText);
    if (!needle || needle.length < 2 || isNoisySource(needle)) {
      return null;
    }
    var host = findTextNodeHost(needle);
    if (host) {
      return host;
    }
    return findElementHost(needle);
  }

  function looksLikeHeadline(text) {
    var s = normalizeText(text);
    if (!s || isNoisySource(s)) {
      return false;
    }
    // Prefer title-ish lines; skip tiny category chips ("Gaming").
    if (s.length < 20) {
      return false;
    }
    return true;
  }

  var HEADLINE_MAX = 280;

  function ownTextRough(el) {
    if (!el || !el.childNodes) {
      return normalizeText(el && el.textContent);
    }
    var parts = [];
    for (var i = 0; i < el.childNodes.length; i++) {
      var n = el.childNodes[i];
      if (n.nodeType === 3) {
        parts.push(n.nodeValue || '');
      } else if (n.nodeType === 1) {
        var t = n.tagName;
        if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT' ||
            (n.classList && n.classList.contains(CLASS_BI))) {
          continue;
        }
        // Keep inline wrappers' text for title links / nested spans (Kagi titles).
        if (t === 'A' || t === 'SPAN' || t === 'EM' || t === 'STRONG' ||
            t === 'B' || t === 'I' || t === 'SMALL' || t === 'MARK' ||
            t === 'U' || t === 'S' || t === 'SUP' || t === 'SUB' ||
            t === 'TIME' || t === 'ABBR' || t === 'CITE') {
          parts.push(n.textContent || '');
        }
      }
    }
    var own = normalizeText(parts.join(' '));
    if (own.length >= 12) {
      return own;
    }
    // Div/span with a single nested text wrapper (common on Svelte list pages).
    if (el.children && el.children.length === 1) {
      var only = el.children[0];
      var ot = only.tagName;
      if (ot === 'SPAN' || ot === 'A' || ot === 'DIV' || ot === 'P') {
        var nested = ownTextRough(only);
        if (nested.length >= 12) {
          return nested;
        }
      }
    }
    return normalizeText(el.textContent);
  }

  /** True when a descendant is a tighter headline host than el. */
  function hasSmallerHeadlineChild(el, own) {
    if (!el || !el.children) {
      return false;
    }
    for (var i = 0; i < el.children.length; i++) {
      var c = el.children[i];
      var t = c.tagName;
      if (t !== 'DIV' && t !== 'SPAN' && t !== 'A' && t !== 'P' &&
          t !== 'H1' && t !== 'H2' && t !== 'H3' && t !== 'H4' &&
          t !== 'H5' && t !== 'H6') {
        continue;
      }
      var ct = ownTextRough(c);
      if (ct.length >= 20 && !isNoisySource(ct) &&
          (ct === own || own.indexOf(ct) !== -1)) {
        return true;
      }
    }
    return false;
  }

  function candidateSelector() {
    return 'h1,h2,h3,h4,h5,h6,p,li,article a,main a,a[href],[role="link"],[role="heading"]';
  }

  function collectCandidates() {
    clear();
    ensureStyle();
    var candidates = [];
    var seenHosts = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
    var seenSources = Object.create(null);
    var nextId = 0;

    function tryAdd(el) {
      if (!el || candidates.length >= COLLECT_CAP) {
        return;
      }
      if (isInSkippedRegion(el) || isCheaplyHidden(el)) {
        return;
      }
      var host = pickCollectHost(el);
      if (!host || isInSkippedRegion(host) || isCheaplyHidden(host)) {
        return;
      }
      if (seenHosts) {
        if (seenHosts.has(host)) {
          return;
        }
      } else if (host.getAttribute(ATTR)) {
        return;
      }
      var source = ownTextRough(host);
      var full = normalizeText(host.textContent);
      // Skip huge containers: prefer smallest host (child pass / tighter pick).
      if (source.length > HEADLINE_MAX) {
        return;
      }
      if (full.length > HEADLINE_MAX && source.length < full.length * 0.6) {
        return;
      }
      if (full.length > source.length * 2.5 && full.length > 120) {
        return;
      }
      if (!looksLikeHeadline(source)) {
        // For h*/p keep slightly shorter suitable lines (≥12 via noise filter).
        var tag = host.tagName;
        if (tag === 'H1' || tag === 'H2' || tag === 'H3' || tag === 'H4' ||
            tag === 'H5' || tag === 'H6' || tag === 'P') {
          if (isNoisySource(source) || source.length < 12) {
            return;
          }
        } else {
          return;
        }
      }
      if (seenSources[source]) {
        return;
      }
      var id = 'c' + nextId;
      nextId += 1;
      host.setAttribute(ATTR, id);
      if (seenHosts) {
        seenHosts.add(host);
      }
      seenSources[source] = true;
      candidates.push({ id: id, source: source });
    }

    // Pass 1: semantic tags + links / ARIA roles.
    forEachSearchRoot(function (root) {
      if (!root || !root.querySelectorAll || candidates.length >= COLLECT_CAP) {
        return;
      }
      var els = root.querySelectorAll(candidateSelector());
      for (var i = 0; i < els.length && candidates.length < COLLECT_CAP; i++) {
        tryAdd(els[i]);
      }
    });

    // Pass 2: visible div/span headlines (Kagi Svelte list titles, etc.).
    if (candidates.length < COLLECT_CAP) {
      forEachSearchRoot(function (root) {
        if (!root || !root.querySelectorAll || candidates.length >= COLLECT_CAP) {
          return;
        }
        var els = root.querySelectorAll('div,span');
        for (var i = 0; i < els.length && candidates.length < COLLECT_CAP; i++) {
          var el = els[i];
          if (isInSkippedRegion(el) || isCheaplyHidden(el)) {
            continue;
          }
          var own = ownTextRough(el);
          if (!looksLikeHeadline(own) || own.length > HEADLINE_MAX) {
            continue;
          }
          var full = normalizeText(el.textContent);
          if (full.length > HEADLINE_MAX && own.length < full.length * 0.6) {
            continue;
          }
          if (hasSmallerHeadlineChild(el, own)) {
            continue;
          }
          tryAdd(el);
        }
      });
    }

    // Pass 3: text-node TreeWalker fallback when selectors still yield nothing.
    if (candidates.length === 0) {
      forEachSearchRoot(function (root) {
        if (!root || candidates.length >= COLLECT_CAP) {
          return;
        }
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var node;
        while ((node = walker.nextNode()) && candidates.length < COLLECT_CAP) {
          if (!node.parentElement) {
            continue;
          }
          var parent = node.parentElement;
          if (isSkippedAnchorParent(parent) || isInSkippedRegion(parent) ||
              isCheaplyHidden(parent)) {
            continue;
          }
          var text = normalizeText(node.nodeValue);
          if (!looksLikeHeadline(text) || text.length > HEADLINE_MAX) {
            continue;
          }
          tryAdd(pickCollectHost(parent) || parent);
        }
      });
    }

    return { ok: true, candidates: candidates, total: candidates.length };
  }

  function findHostById(id) {
    if (!id) {
      return null;
    }
    var found = null;
    var sel = '[' + ATTR + '="' + String(id).replace(/"/g, '\\"') + '"]';
    forEachSearchRoot(function (root) {
      if (found || !root || !root.querySelector) {
        return;
      }
      var el = root.querySelector(sel);
      if (el && !(el.classList && el.classList.contains(CLASS_BI))) {
        found = el;
      }
    });
    return found;
  }

  function replaceOrInsertBilingualRow(host, id, text) {
    var sib = host.nextElementSibling;
    if (sib && sib.classList && sib.classList.contains(CLASS_BI)) {
      sib.setAttribute(ATTR, id);
      sib.textContent = text;
      return;
    }
    var row = document.createElement('div');
    row.className = CLASS_BI;
    row.setAttribute(ATTR, id);
    row.textContent = text;
    if (host.nextSibling) {
      host.parentNode.insertBefore(row, host.nextSibling);
    } else {
      host.parentNode.appendChild(row);
    }
  }

  function applyBilingualById(units) {
    ensureStyle();
    // Do NOT clear tids — they were stamped by collectCandidates.
    var applied = 0;
    var list = Array.isArray(units) ? units : [];
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || {};
      var id = String(u.id || '');
      var text = u.text || '';
      if (!id || !text) {
        continue;
      }
      var host = findHostById(id);
      if (!host || !host.parentNode) {
        continue;
      }
      replaceOrInsertBilingualRow(host, id, text);
      applied += 1;
    }
    return { ok: true, applied: applied, total: list.length };
  }

  function applyHoverById(units) {
    ensureStyle();
    // Do NOT clear tids. Rebuild hover map for this batch; keep stamps.
    var applied = 0;
    var list = Array.isArray(units) ? units : [];
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || {};
      var id = String(u.id || '');
      var text = u.text || '';
      if (!id || !text) {
        continue;
      }
      var host = findHostById(id);
      if (!host) {
        continue;
      }
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
    collectCandidates: collectCandidates,
    applyBilingualById: applyBilingualById,
    applyHoverById: applyHoverById,
    applyBilingual: applyBilingual,
    applyHover: applyHover
  };
})();
