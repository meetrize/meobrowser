/**
 * MeoBrowser Page Context — PC-1 capture (meta/article/outline/html/markdown).
 * Injected via evaluateJavaScript; exposes window.__MeoPageContext.capture(opts).
 */
(function () {
  'use strict';
  var VERSION = 3;

  function trim(s) {
    return String(s || '').replace(/\s+/g, ' ').trim();
  }

  function metaContent(sel) {
    var el = document.querySelector(sel);
    return el ? trim(el.getAttribute('content') || el.getAttribute('href') || '') : '';
  }

  function collectMeta() {
    var canon = document.querySelector('link[rel="canonical"]');
    return {
      title: trim(document.title || ''),
      url: String(location.href || ''),
      description: metaContent('meta[name="description"]') ||
                   metaContent('meta[property="og:description"]'),
      lang: trim(document.documentElement.getAttribute('lang') || ''),
      canonical: canon ? trim(canon.href || '') : ''
    };
  }

  function isNoiseNode(el) {
    if (!el || el.nodeType !== 1) return true;
    var tag = (el.tagName || '').toLowerCase();
    if (/^(script|style|noscript|svg|iframe|canvas|template|nav|footer|header|aside|form)$/.test(tag)) {
      return true;
    }
    var role = (el.getAttribute('role') || '').toLowerCase();
    if (role === 'navigation' || role === 'banner' || role === 'contentinfo' || role === 'complementary') {
      return true;
    }
    var cls = ((el.className && String(el.className)) || '').toLowerCase();
    if (/(^|[\s_-])(nav|menu|sidebar|footer|header|广告|ad-|ads|cookie|banner|comment)([\s_-]|$)/.test(cls)) {
      return true;
    }
    return false;
  }

  function textOf(el) {
    if (!el) return '';
    try {
      return String(el.innerText || el.textContent || '');
    } catch (e) {
      return '';
    }
  }

  function linkDensity(el) {
    var all = trim(textOf(el)).length || 1;
    var links = el.querySelectorAll('a');
    var lt = 0;
    for (var i = 0; i < links.length; i++) {
      lt += trim(textOf(links[i])).length;
    }
    return lt / all;
  }

  function scoreCandidate(el) {
    var t = trim(textOf(el));
    var len = t.length;
    if (len < 80) return 0;
    var dens = linkDensity(el);
    var pCount = el.querySelectorAll('p').length;
    var score = len * (1 - Math.min(0.85, dens)) + pCount * 40;
    var tag = (el.tagName || '').toLowerCase();
    if (tag === 'article') score *= 1.35;
    if (tag === 'main' || el.getAttribute('role') === 'main') score *= 1.25;
    return score;
  }

  function pickArticleRoot() {
    var preferred = document.querySelector('article, main, [role="main"]');
    if (preferred && !isNoiseNode(preferred) && trim(textOf(preferred)).length > 120) {
      return preferred;
    }
    var candidates = document.querySelectorAll('article, main, [role="main"], .post, .article, .content, #content, #main');
    var best = null;
    var bestScore = 0;
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      if (isNoiseNode(el)) continue;
      var s = scoreCandidate(el);
      if (s > bestScore) {
        bestScore = s;
        best = el;
      }
    }
    if (best && bestScore > 200) return best;

    var paras = document.body ? document.body.querySelectorAll('p') : [];
    var parentScores = {};
    var parentEls = {};
    for (var j = 0; j < paras.length; j++) {
      var p = paras[j];
      if (isNoiseNode(p) || isNoiseNode(p.parentElement)) continue;
      var pt = trim(textOf(p));
      if (pt.length < 40) continue;
      var parent = p.parentElement;
      if (!parent) continue;
      var key = parent.tagName + (parent.id || '') + (parent.className || '');
      parentScores[key] = (parentScores[key] || 0) + pt.length;
      parentEls[key] = parent;
    }
    var topKey = null;
    var top = 0;
    for (var k in parentScores) {
      if (parentScores[k] > top) {
        top = parentScores[k];
        topKey = k;
      }
    }
    if (topKey && top > 200) return parentEls[topKey];
    return document.body || document.documentElement;
  }

  function cleanArticleText(root) {
    if (!root) return '';
    var clone = root.cloneNode(true);
    var kill = clone.querySelectorAll('script,style,noscript,svg,iframe,nav,footer,header,aside,form,button');
    for (var i = 0; i < kill.length; i++) {
      try { kill[i].remove(); } catch (e) {}
    }
    return String(clone.innerText || clone.textContent || '')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  function visibleTextSample(maxChars) {
    maxChars = maxChars || 12000;
    try {
      var t = String(document.body ? document.body.innerText : '') || '';
      t = t.replace(/\n{3,}/g, '\n\n').trim();
      if (t.length > maxChars) t = t.slice(0, maxChars);
      return t;
    } catch (e) {
      return '';
    }
  }

  function collectOutline(maxChars) {
    maxChars = maxChars || 8000;
    var nodes = document.querySelectorAll('h1,h2,h3');
    var lines = [];
    var total = 0;
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (isNoiseNode(el)) continue;
      var level = parseInt((el.tagName || 'H2').charAt(1), 10) || 2;
      var t = trim(textOf(el));
      if (!t) continue;
      var indent = '';
      for (var n = 1; n < level; n++) indent += '  ';
      var line = indent + t;
      if (total + line.length + 1 > maxChars) {
        lines.push('…（提纲已截断）');
        break;
      }
      lines.push(line);
      total += line.length + 1;
    }
    return lines.join('\n');
  }

  function collectHTML(maxChars) {
    maxChars = maxChars || 100000;
    var root = document.documentElement || document.body;
    if (!root) return { text: '', truncated: false, charCount: 0 };
    var clone = root.cloneNode(true);
    var kill = clone.querySelectorAll('script,style,noscript,svg,iframe,canvas,template');
    for (var i = 0; i < kill.length; i++) {
      try { kill[i].remove(); } catch (e) {}
    }
    // 去掉超长 data: / base64 src，避免炸上下文
    var media = clone.querySelectorAll('[src],[href]');
    for (var j = 0; j < media.length; j++) {
      var m = media[j];
      ['src', 'href'].forEach(function (attr) {
        var v = m.getAttribute(attr) || '';
        if (v.indexOf('data:') === 0 && v.length > 120) {
          m.setAttribute(attr, 'data:…');
        }
      });
    }
    var html = '';
    try {
      html = String(clone.outerHTML || '');
    } catch (e) {
      html = '';
    }
    var truncated = false;
    if (html.length > maxChars) {
      html = html.slice(0, maxChars) + '\n<!-- … HTML 已截断 -->';
      truncated = true;
    }
    return { text: html, truncated: truncated, charCount: html.length };
  }

  function collectMarkdown(root, maxChars) {
    maxChars = maxChars || 24000;
    if (!root) return '';
    var parts = [];
    var total = 0;
    function push(s) {
      if (!s) return;
      if (total + s.length + 1 > maxChars) {
        parts.push('…（Markdown 已截断）');
        total = maxChars;
        return false;
      }
      parts.push(s);
      total += s.length + 1;
      return true;
    }
    var walk = root.querySelectorAll('h1,h2,h3,h4,p,li,pre,blockquote,a');
    var seen = {};
    for (var i = 0; i < walk.length; i++) {
      if (total >= maxChars) break;
      var el = walk[i];
      if (isNoiseNode(el)) continue;
      var tag = (el.tagName || '').toLowerCase();
      var t = trim(textOf(el));
      if (!t) continue;
      // 避免父子重复灌水：跳过已被父级覆盖的短节点时仍保留标题/段落
      var key = tag + ':' + t.slice(0, 40);
      if (seen[key]) continue;
      seen[key] = 1;
      var line = t;
      if (tag === 'h1') line = '# ' + t;
      else if (tag === 'h2') line = '## ' + t;
      else if (tag === 'h3') line = '### ' + t;
      else if (tag === 'h4') line = '#### ' + t;
      else if (tag === 'li') line = '- ' + t;
      else if (tag === 'blockquote') line = '> ' + t;
      else if (tag === 'pre') line = '```\n' + t + '\n```';
      else if (tag === 'a') {
        var href = el.getAttribute('href') || '';
        if (href && href.indexOf('javascript:') !== 0) line = '[' + t + '](' + href + ')';
        else continue;
      }
      if (!push(line)) break;
    }
    if (parts.length === 0) {
      return cleanArticleText(root).slice(0, maxChars);
    }
    return parts.join('\n\n');
  }

  function wants(layers, name) {
    if (!layers || !layers.length) return true;
    for (var i = 0; i < layers.length; i++) {
      if (layers[i] === name) return true;
    }
    return false;
  }

  function shortLabel(url, fallback) {
    try {
      if (url) {
        var u = new URL(url, location.href);
        var path = u.pathname || '';
        var base = path.split('/').filter(Boolean).pop() || u.host || fallback;
        return String(base).slice(0, 48);
      }
    } catch (e) {}
    return fallback || 'resource';
  }

  function collectResources(opts) {
    opts = opts || {};
    var maxInline = opts.maxInlineChars || 65536;
    var maxItems = opts.maxResources || 40;
    var list = [];
    var seen = {};

    function push(item) {
      if (list.length >= maxItems) return;
      var key = (item.kind || '') + '|' + (item.url || '') + '|' + (item.inline ? '1' : '0') + '|' + (item.label || '');
      if (seen[key]) return;
      seen[key] = 1;
      item.id = 'r' + list.length + '_' + Math.random().toString(36).slice(2, 8);
      list.push(item);
    }

    var scripts = document.querySelectorAll('script');
    for (var i = 0; i < scripts.length; i++) {
      var s = scripts[i];
      var type = (s.getAttribute('type') || '').toLowerCase();
      var src = s.getAttribute('src') || '';
      if (type.indexOf('json') >= 0 || type === 'application/ld+json') {
        var jt = String(s.textContent || '');
        if (jt.length > maxInline) jt = jt.slice(0, maxInline) + '\n…（已截断）';
        push({
          kind: 'json',
          url: src || location.href + '#json-' + i,
          label: type.indexOf('ld+json') >= 0 ? 'JSON-LD' : shortLabel(src, 'inline-json'),
          inline: !src,
          text: jt,
          size: jt.length
        });
        continue;
      }
      if (src) {
        push({
          kind: 'script',
          url: s.src || src,
          label: shortLabel(s.src || src, 'script.js'),
          inline: false,
          size: 0
        });
      } else {
        var st = String(s.textContent || '');
        if (st.length < 8) continue;
        if (st.length > maxInline) st = st.slice(0, maxInline) + '\n…（已截断）';
        push({
          kind: 'script',
          url: location.href + '#inline-script-' + i,
          label: 'inline-script',
          inline: true,
          text: st,
          size: st.length
        });
      }
    }

    var links = document.querySelectorAll('link[rel~="stylesheet"], link[as="style"]');
    for (var j = 0; j < links.length; j++) {
      var l = links[j];
      var href = l.href || l.getAttribute('href') || '';
      if (!href) continue;
      push({
        kind: 'stylesheet',
        url: href,
        label: shortLabel(href, 'style.css'),
        inline: false,
        size: 0
      });
    }
    var styles = document.querySelectorAll('style');
    for (var k = 0; k < styles.length; k++) {
      var css = String(styles[k].textContent || '');
      if (css.length < 8) continue;
      if (css.length > maxInline) css = css.slice(0, maxInline) + '\n…（已截断）';
      push({
        kind: 'stylesheet',
        url: location.href + '#inline-style-' + k,
        label: 'inline-style',
        inline: true,
        text: css,
        size: css.length
      });
    }

    var imgs = document.querySelectorAll('img[src]');
    for (var m = 0; m < imgs.length && list.length < maxItems; m++) {
      var img = imgs[m];
      var iu = img.currentSrc || img.src || '';
      if (!iu || iu.indexOf('data:') === 0) continue;
      push({
        kind: 'image',
        url: iu,
        label: shortLabel(iu, img.alt || 'image'),
        inline: false,
        size: 0
      });
    }
    return list;
  }

  function fetchResourceText(url, maxChars) {
    maxChars = maxChars || 65536;
    return fetch(String(url), { credentials: 'include', mode: 'cors', cache: 'force-cache' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.text();
      })
      .then(function (t) {
        t = String(t || '');
        var truncated = false;
        if (t.length > maxChars) {
          t = t.slice(0, maxChars) + '\n…（已截断）';
          truncated = true;
        }
        return { ok: true, text: t, truncated: truncated, size: t.length };
      })
      .catch(function (e) {
        return { ok: false, error: String(e && e.message || e) };
      });
  }

  function capture(opts) {
    opts = opts || {};
    var maxArticle = opts.maxArticleChars || 24000;
    var maxHtml = opts.maxHtmlChars || 100000;
    var layers = opts.layers || null;
    var includeResources = opts.includeResources !== false;
    var meta = collectMeta();
    var root = pickArticleRoot();
    var text = cleanArticleText(root);
    var quality = 'high';
    var warning = '';
    if (text.length < 120) {
      quality = 'low';
      warning = '正文提取较短，已尽量取页面可见文本';
      var vis = visibleTextSample(maxArticle);
      if (vis.length > text.length) text = vis;
    } else if (root === document.body || root === document.documentElement) {
      quality = 'low';
      warning = '未能可靠识别正文区域，使用页面主体文本';
    }
    if (text.length > maxArticle) {
      text = text.slice(0, maxArticle) + '\n\n…（正文已截断）';
    }

    var out = {
      ok: true,
      url: meta.url,
      title: meta.title,
      meta: meta,
      article: {
        text: text,
        quality: quality,
        warning: warning,
        charCount: text.length
      },
      visibleText: visibleTextSample(Math.min(8000, maxArticle))
    };

    if (wants(layers, 'outline')) {
      var outline = collectOutline(8000);
      out.outline = { text: outline, charCount: outline.length };
    }
    if (wants(layers, 'html')) {
      out.html = collectHTML(maxHtml);
    }
    if (wants(layers, 'markdown')) {
      var md = collectMarkdown(root, maxArticle);
      out.markdown = { text: md, charCount: md.length };
    }
    if (includeResources) {
      out.resources = collectResources(opts);
    }
    return out;
  }

  window.__MeoPageContext = {
    version: VERSION,
    capture: capture,
    fetchResourceText: fetchResourceText
  };
})();
