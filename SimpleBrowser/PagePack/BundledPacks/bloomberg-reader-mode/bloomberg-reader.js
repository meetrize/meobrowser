/*
 * 彭博阅读模式（Page Pack）
 *
 * 思路：
 * 1. 在页面里用多组候选 + 评分找出最像“正文”的容器；
 * 2. 克隆并清洗正文（去掉广告、订阅块、导航、脚本等）；
 * 3. 放进一个全屏 <dialog> 阅读器，showModal() 进入 top layer；
 * 4. 打开时把页面其余元素全部隐藏，黑色遮罩/滚动锁都影响不到阅读器。
 */
(function () {
  'use strict';

  var OPEN_CLASS = 'meo-bloomberg-reader-open';

  var previous = window.__meoBloombergReader;
  if (previous && typeof previous.destroy === 'function') {
    try { previous.destroy(); } catch (e) {}
  }

  var state = {
    dialog: null,
    contentEl: null,
    scrollEl: null,
    reopenButton: null,
    shown: false,
    dismissed: false,
    destroyed: false,
    startTime: Date.now ? Date.now() : new Date().getTime(),
    timers: [],
    attemptTimer: null,
    observer: null,
    topLayerTimer: null,
    extractionLen: 0,
    lastAttempt: null
  };
  window.__meoBloombergReader = state;

  var ALLOWED_TAGS = {
    P: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    UL: 1, OL: 1, LI: 1, BLOCKQUOTE: 1, FIGURE: 1, FIGCAPTION: 1,
    IMG: 1, PICTURE: 1, SOURCE: 1, TABLE: 1, THEAD: 1, TBODY: 1, TFOOT: 1,
    TR: 1, TD: 1, TH: 1, A: 1, STRONG: 1, EM: 1, B: 1, I: 1, U: 1, S: 1,
    CODE: 1, PRE: 1, BR: 1, HR: 1, SUP: 1, SUB: 1, SPAN: 1, DIV: 1,
    SECTION: 1, ARTICLE: 1, MAIN: 1, MARK: 1, SMALL: 1, TIME: 1, CITE: 1,
    Q: 1, DL: 1, DT: 1, DD: 1, ABBR: 1
  };

  var REMOVE_TAGS = {
    SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, IFRAME: 1, FORM: 1, INPUT: 1, BUTTON: 1,
    SELECT: 1, TEXTAREA: 1, NAV: 1, HEADER: 1, FOOTER: 1, ASIDE: 1, SVG: 1,
    CANVAS: 1, VIDEO: 1, AUDIO: 1, OBJECT: 1, EMBED: 1, LINK: 1, META: 1
  };

  var KEEP_ATTRS = {
    href: 1, src: 1, srcset: 1, sizes: 1, alt: 1, title: 1,
    colspan: 1, rowspan: 1, datetime: 1, cite: 1, lang: 1,
    start: 1, type: 1, media: 1
  };

  var REMOVE_SELECTOR = [
    'script', 'style', 'noscript', 'iframe', 'form', 'button', 'input',
    'select', 'textarea', 'nav', 'header', 'footer', 'aside', 'svg', 'canvas',
    'video', 'audio', 'object', 'embed',
    '[role="navigation"]', '[role="banner"]', '[role="complementary"]',
    '[role="contentinfo"]', '[role="dialog"]', '[aria-modal="true"]',
    '[class*="paywall" i]', '[data-testid*="paywall" i]', '[data-component*="paywall" i]',
    '[class*="regwall" i]', '[class*="metered-wall" i]',
    '[class*="advert" i]', '[class*="advertisement" i]', '[id*="google_ads" i]',
    '[class*="newsletter-signup" i]', '[class*="newsletter-form" i]',
    '[class*="newsletter-box" i]', '[class*="newsletter-subscribe" i]',
    '[class*="signup" i]', '[class*="subscribe" i]',
    '[class*="share-tools" i]', '[class*="sharebar" i]', '[class*="share-bar" i]',
    '[class*="social" i]', '[class*="related" i]', '[class*="recommend" i]',
    '[class*="comments" i]', '[class*="comment-section" i]',
    '[class*="morefrombloomberg" i]', '[class*="morefrom" i]',
    '[class*="storycard" i]', '[class*="story-card" i]',
    '[class*="topreads" i]', '[class*="top-reads" i]',
    '[class*="relatedstories" i]', '[class*="related-stories" i]',
    '[class*="promo" i]', '[class*="outbrain" i]', '[class*="taboola" i]',
    '[class*="cookie" i]', '[class*="consent" i]', '[class*="modal" i]',
    '[class*="overlay" i]', '[class*="backdrop" i]', '[class*="scrim" i]'
  ].join(',');

  // 广告 / 推荐位外层：即使它包住了正文，也不应该成为正文根节点。
  var AD_CONTAINER_RE = /(leaderboard|parallax|advert|advertisement|sponsor|promo|dfp|gpt|adslot|ad-slot|adwrapper|ad_wrapper|ad-container|adcontainer|banner|(^|[-_ ])ads?([-_ ]|$))/i;

  function queryAll(selector, root) {
    try {
      return Array.prototype.slice.call((root || document).querySelectorAll(selector));
    } catch (e) {
      return [];
    }
  }

  // 穿透 open shadow DOM；付费墙有时把 dialog/遮罩放在 web component 里。
  function deepQueryAll(selector) {
    var out = queryAll(selector, document);
    var roots = [];
    var all = [];
    try { all = document.querySelectorAll('*'); } catch (e) { return out; }

    for (var i = 0; i < all.length; i++) {
      if (all[i].shadowRoot) roots.push(all[i].shadowRoot);
    }

    for (var r = 0; r < roots.length; r++) {
      var root = roots[r];
      queryAll(selector, root).forEach(function (el) {
        out.push(el);
      });
      var inner = [];
      try { inner = root.querySelectorAll('*'); } catch (e) { inner = []; }
      for (var j = 0; j < inner.length; j++) {
        if (inner[j].shadowRoot) roots.push(inner[j].shadowRoot);
      }
    }
    return out;
  }

  function textLengthOf(el) {
    if (!el) return 0;
    var text = el.textContent || '';
    return text.replace(/\s+/g, ' ').trim().length;
  }

  function attrOf(el) {
    var className = '';
    if (typeof el.className === 'string') {
      className = el.className;
    } else if (el.className && typeof el.className.baseVal === 'string') {
      className = el.className.baseVal;
    }
    return ((el.id || '') + ' ' + className + ' ' +
      (el.getAttribute('data-component') || '') + ' ' +
      (el.getAttribute('data-testid') || '')).toLowerCase();
  }

  function isArticleURL() {
    var path = (location.pathname || '').toLowerCase();
    if (/\/articles\//.test(path) || /\/features\//.test(path)) return true;
    // 有些 Bloomberg 文章路径不带 /articles/，但仍包含日期段。
    if (/\/20\d{2}-\d{2}-\d{2}\//.test(path)) return true;
    // 路径完全不同的页面，只要 DOM 里有明显文章结构也允许尝试。
    try {
      if (document.querySelector('.body-content, article h1, [data-component="article-body"], [data-testid="article-body"]')) {
        return true;
      }
    } catch (e) {}
    return false;
  }

  // ---------- 找正文 ----------

  function scoreCandidate(el) {
    if (!el || el.nodeType !== 1) return 0;
    var tag = el.tagName;
    if (tag === 'HTML' || tag === 'BODY') return 0;

    var textLen = textLengthOf(el);
    if (textLen < 200) return 0;

    var paragraphs = el.querySelectorAll('p');
    if (paragraphs.length < 2) return 0;

    var links = el.querySelectorAll('a');
    var linkText = 0;
    for (var i = 0; i < links.length; i++) {
      linkText += textLengthOf(links[i]);
    }
    var density = textLen > 0 ? linkText / textLen : 1;
    var attr = attrOf(el);

    // 广告/leaderboard/parallax 外层直接排除，避免它因为文本多而压过正文。
    if (AD_CONTAINER_RE.test(attr)) return 0;

    var score = Math.min(textLen, 15000) * 0.4 + Math.min(paragraphs.length, 60) * 100;
    if (tag === 'ARTICLE') score += 800;
    if (/(article|body|story|content|newsletter)/.test(attr)) score += 1200;
    if (/(nav|menu|header|footer|sidebar|comment|related|recommend|share|advert|promo)/.test(attr)) {
      score -= 1800;
    }
    // styles_articleBlur 之类是付费墙预览块，正文不完整。
    if (/blur/.test(attr)) score -= 2500;
    if (el.querySelector('h1')) score += 150;
    score -= density * 3000;
    score -= el.querySelectorAll('nav, header, footer, aside, form').length * 150;

    var adCount = el.querySelectorAll('iframe, ins, [data-ad], [data-ad-slot], ' +
                  '[id*="google_ads"], [class*="advert"], [class*="leaderboard"], ' +
                  '[class*="ad-slot"], [class*="adslot"]').length;
    score -= adCount * 600;

    // 段落文本密度：页面外层/广告外层往往有大量导航、广告文字，
    // 真正的正文容器文本应该集中在 <p> 里。
    var paragraphTextLen = 0;
    for (var pi = 0; pi < paragraphs.length; pi++) {
      paragraphTextLen += textLengthOf(paragraphs[pi]);
    }
    var paragraphDensity = textLen > 0 ? paragraphTextLen / textLen : 0;
    if (paragraphDensity < 0.25) score -= 5000;
    if (paragraphDensity < 0.12) score -= 5000;

    return score;
  }

  function findArticleRoot() {
    var candidates = [];
    var seen = [];

    function add(el) {
      if (!el || el.nodeType !== 1) return;
      if (seen.indexOf(el) >= 0) return;
      seen.push(el);
      candidates.push(el);
    }

    // 语义候选。注意不要提前返回 .body-content：Bloomberg 的 .body-content
    // 可能只是带 blur 的预览块，完整正文在外层 article 里。
    queryAll('article, main, [role="main"], .body-content, [itemprop="articleBody"], ' +
             '[class*="newsletter" i], [class*="article-body" i], [class*="story-body" i], ' +
             '[data-component], [data-testid], section').forEach(add);

    // 最长段落的祖先链也纳入候选。
    var paragraphs = queryAll('p');
    var bestP = null;
    var bestLen = 0;
    for (var j = 0; j < paragraphs.length; j++) {
      var len = textLengthOf(paragraphs[j]);
      if (len > bestLen) {
        bestLen = len;
        bestP = paragraphs[j];
      }
    }
    if (bestP) {
      var node = bestP;
      for (var depth = 0; node && depth < 10; depth++) {
        add(node);
        node = node.parentElement;
      }
    }

    var best = null;
    var bestScore = 0;
    for (var k = 0; k < candidates.length; k++) {
      var score = scoreCandidate(candidates[k]);
      if (score > bestScore) {
        bestScore = score;
        best = candidates[k];
      }
    }

    if (bestScore > 0) return best;

    // 很短的正文兜底。
    var preferred = [
      '.body-content',
      '[data-component="article-body"]',
      '[data-testid="article-body"]',
      '[data-testid="body-content"]',
      'main article',
      'article'
    ];
    for (var i = 0; i < preferred.length; i++) {
      var el = document.querySelector(preferred[i]);
      if (el && textLengthOf(el) >= 200 && el.querySelectorAll('p').length >= 1) {
        return el;
      }
    }

    return null;
  }

  // ---------- 清洗正文 ----------

  function stripAttributes(el) {
    if (!el || el.nodeType !== 1) return;
    var attrs = Array.prototype.slice.call(el.attributes || []);
    for (var i = 0; i < attrs.length; i++) {
      var name = attrs[i].name.toLowerCase();
      if (!KEEP_ATTRS[name]) {
        el.removeAttribute(attrs[i].name);
      }
    }
  }

  function cleanClone(clone) {
    if (!clone || clone.nodeType !== 1) return clone;

    // 先移除明确的垃圾节点。
    queryAll(REMOVE_SELECTOR, clone).forEach(function (el) {
      el.remove();
    });

    // 去掉不允许的标签，容器类标签保留；未知标签 unwrap。
    var all = queryAll('*', clone);
    for (var i = all.length - 1; i >= 0; i--) {
      var el = all[i];
      if (!el || !el.parentNode) continue;
      if (REMOVE_TAGS[el.tagName]) {
        el.remove();
        continue;
      }
      if (!ALLOWED_TAGS[el.tagName]) {
        var parent = el.parentNode;
        while (el.firstChild) {
          parent.insertBefore(el.firstChild, el);
        }
        parent.removeChild(el);
      }
    }

    // 懒加载图片：必须在 stripAttributes 之前把 data-src 拷到 src。
    queryAll('img', clone).forEach(function (img) {
      var src = img.getAttribute('data-src') ||
                img.getAttribute('data-lazy-src') ||
                img.getAttribute('data-original');
      var srcset = img.getAttribute('data-srcset') ||
                   img.getAttribute('data-lazy-srcset') ||
                   img.getAttribute('data-original-srcset');
      if (src) img.setAttribute('src', src);
      if (srcset) img.setAttribute('srcset', srcset);
    });
    queryAll('source', clone).forEach(function (source) {
      var srcset = source.getAttribute('data-srcset') ||
                   source.getAttribute('data-lazy-srcset');
      if (srcset) source.setAttribute('srcset', srcset);
    });

    // 清理属性（class/style/id 全部去掉，避免站点 CSS 影响阅读器）。
    stripAttributes(clone);
    queryAll('*', clone).forEach(stripAttributes);

    // 图片按容器宽度缩放，并修正 loading。
    queryAll('img', clone).forEach(function (img) {
      img.removeAttribute('loading');
      img.setAttribute('loading', 'eager');
    });

    // 链接统一新标签页打开。
    queryAll('a', clone).forEach(function (a) {
      if (!a.getAttribute('href')) {
        a.removeAttribute('href');
        return;
      }
      a.setAttribute('target', '_blank');
      a.setAttribute('rel', 'noopener noreferrer');
    });

    // 去掉追踪像素。
    queryAll('img', clone).forEach(function (img) {
      var src = (img.getAttribute('src') || '').toLowerCase();
      if (/(pixel|track|beacon|spacer)/.test(src)) {
        img.remove();
        return;
      }
      var w = parseInt(img.getAttribute('width'), 10);
      var h = parseInt(img.getAttribute('height'), 10);
      if (w > 0 && w <= 2 && h > 0 && h <= 2) {
        img.remove();
      }
    });

    // 订阅/付费墙文案块（位置不固定时用文字兜底）。
    queryAll('div, section, aside', clone).forEach(function (el) {
      if (!el.parentNode) return;
      if (el.querySelectorAll('p').length >= 2) return;
      var text = (el.textContent || '').trim();
      if (text.length > 0 && text.length < 500 &&
          /(subscribe to continue reading|already a subscriber|sign in to continue|create a free account|to continue reading)/i.test(text)) {
        el.remove();
      }
    });

    // 去掉空容器。
    var containers = queryAll('p, div, section, article, figure, li, blockquote, span', clone);
    for (var j = containers.length - 1; j >= 0; j--) {
      var item = containers[j];
      if (!item.parentNode) continue;
      if (!textLengthOf(item) && !item.querySelector('img, picture, br, hr, table')) {
        item.remove();
      }
    }

    return clone;
  }

  function extractTitle(root) {
    var selectors = [
      'article h1',
      '[data-component="headline"]',
      '[data-testid="headline"]',
      'main h1',
      'h1'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el && textLengthOf(el) >= 8) {
        var clone = el.cloneNode(true);
        cleanClone(clone);
        clone.classList.add('meo-bloomberg-reader-title');
        return clone;
      }
    }
    return null;
  }

  function extractByline(root) {
    var selectors = [
      '[data-component="byline"]',
      '[data-testid="byline"]',
      '[rel="author"]',
      '[class*="byline" i]',
      '[class*="author" i]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      var len = textLengthOf(el);
      if (el && len > 0 && len < 300) {
        var clone = el.cloneNode(true);
        cleanClone(clone);
        clone.classList.add('meo-bloomberg-reader-byline');
        return clone;
      }
    }
    return null;
  }

  function extractDomArticle() {
    var root = findArticleRoot();
    if (!root) return null;

    var titleNode = extractTitle(root);
    var bylineNode = extractByline(root);

    var clone = root.cloneNode(true);
    cleanClone(clone);

    if (titleNode) {
      queryAll('h1', clone).forEach(function (h1) {
        h1.remove();
      });
    }

    if (bylineNode) {
      queryAll('[data-component="byline"], [data-testid="byline"], [rel="author"], ' +
               '[class*="byline" i], [class*="author" i]', clone).forEach(function (b) {
        b.remove();
      });
    }

    var content = document.createElement('div');
    content.className = 'meo-bloomberg-reader-article';
    if (titleNode) content.appendChild(titleNode);
    if (bylineNode) content.appendChild(bylineNode);
    content.appendChild(clone);

    var textLength = textLengthOf(content);
    var paragraphs = content.querySelectorAll('p').length;
    if (textLength < 100) return null;

    return {
      node: content,
      textLength: textLength,
      paragraphs: paragraphs,
      root: root,
      source: 'dom'
    };
  }

  // ---------- JSON-LD 兜底 ----------

  function plainTextFromHtml(html) {
    if (!html) return '';
    var textarea = document.createElement('textarea');
    textarea.innerHTML = String(html);
    return (textarea.value || '').trim();
  }

  function findArticleInJson(node, depth) {
    if (!node || typeof node !== 'object') return null;
    if (depth > 6) return null;

    if (Array.isArray(node)) {
      for (var i = 0; i < node.length; i++) {
        var found = findArticleInJson(node[i], depth + 1);
        if (found) return found;
      }
      return null;
    }

    var type = node['@type'];
    var typeStr = Array.isArray(type) ? type.join(' ') : String(type || '');
    if (/Article/i.test(typeStr) && typeof node.articleBody === 'string' && node.articleBody.length > 0) {
      return node;
    }

    if (node['@graph']) {
      var graph = findArticleInJson(node['@graph'], depth + 1);
      if (graph) return graph;
    }

    for (var key in node) {
      if (!Object.prototype.hasOwnProperty.call(node, key)) continue;
      if (key === '@context' || key === '@graph') continue;
      var value = node[key];
      if (value && typeof value === 'object') {
        var nested = findArticleInJson(value, depth + 1);
        if (nested) return nested;
      }
    }
    return null;
  }

  function extractJsonLdArticle() {
    var scripts = queryAll('script[type="application/ld+json"]');
    var best = null;
    for (var i = 0; i < scripts.length; i++) {
      var raw = scripts[i].textContent || '';
      if (!raw || raw.length < 20) continue;
      var data = null;
      try { data = JSON.parse(raw); } catch (e) { continue; }
      var article = findArticleInJson(data, 0);
      if (article && typeof article.articleBody === 'string' && article.articleBody.length > 0) {
        if (!best || article.articleBody.length > best.articleBody.length) {
          best = article;
        }
      }
    }
    return best;
  }

  function buildJsonLdExtraction(article) {
    if (!article || typeof article.articleBody !== 'string') return null;

    var bodyText = plainTextFromHtml(article.articleBody);
    if (!bodyText) return null;

    var content = document.createElement('div');
    content.className = 'meo-bloomberg-reader-article';

    var headline = plainTextFromHtml(article.headline || article.name || '');
    if (headline) {
      var h1 = document.createElement('h1');
      h1.className = 'meo-bloomberg-reader-title';
      h1.textContent = headline;
      content.appendChild(h1);
    }

    var paragraphs = bodyText.split(/\n{2,}/);
    if (paragraphs.length <= 1) {
      paragraphs = bodyText.split(/\n/);
    }

    for (var i = 0; i < paragraphs.length; i++) {
      var text = paragraphs[i].trim();
      if (!text) continue;
      var p = document.createElement('p');
      p.textContent = text;
      content.appendChild(p);
    }

    var textLength = textLengthOf(content);
    if (textLength < 400) return null;

    return {
      node: content,
      textLength: textLength,
      paragraphs: content.querySelectorAll('p').length,
      root: null,
      source: 'jsonld'
    };
  }

  var embeddedJsonCache = { time: 0, value: null };

  function findHeadlineInObject(node) {
    if (!node || typeof node !== 'object') return '';
    var keys = ['headline', 'title', 'name'];
    for (var i = 0; i < keys.length; i++) {
      var value = node[keys[i]];
      if (typeof value === 'string') {
        var text = value.trim();
        if (text.length >= 10 && text.length <= 200) return text;
      }
    }
    return '';
  }

  function findLongTextInObject(node, depth, ctx) {
    if (!node || typeof node !== 'object' || depth > 8) return null;
    if (ctx.visited++ > 6000) return null;
    if (ctx.seen.indexOf(node) >= 0) return null;
    ctx.seen.push(node);

    if (Array.isArray(node)) {
      var arrayBest = null;
      for (var i = 0; i < node.length && i < 200; i++) {
        var item = findLongTextInObject(node[i], depth + 1, ctx);
        if (item && (!arrayBest || item.score > arrayBest.score)) arrayBest = item;
      }
      return arrayBest;
    }

    var best = null;
    var headline = findHeadlineInObject(node);

    for (var key in node) {
      if (!Object.prototype.hasOwnProperty.call(node, key)) continue;
      var value = node[key];

      if (typeof value === 'string') {
        if (value.length < 400 || value.length > 120000) continue;
        var lowerKey = key.toLowerCase();
        var strongHint = /(articlebody|bodytext|newsletter|articlecontent|storybody|body|story|article)/i.test(lowerKey);
        var weakHint = /(content|text)/i.test(lowerKey);
        if (!strongHint && !(weakHint && headline)) continue;
        if (!/[.!?。！？]/.test(value) && !/\n/.test(value)) continue;
        if (/^https?:\/\//i.test(value)) continue;
        if (/^[A-Za-z0-9+/=]{500,}$/.test(value)) continue;

        var score = value.length + (strongHint ? 5000 : 0);
        if (!best || score > best.score) {
          best = { text: value, key: key, score: score, headline: headline };
        }
      } else if (value && typeof value === 'object') {
        var nested = findLongTextInObject(value, depth + 1, ctx);
        if (nested && (!best || nested.score > best.score)) best = nested;
      }
    }
    return best;
  }

  function extractEmbeddedJsonArticle() {
    var now = Date.now ? Date.now() : new Date().getTime();
    if (now - embeddedJsonCache.time < 3000) return embeddedJsonCache.value;

    var best = null;
    var sources = [];

    queryAll('script[type="application/json"], script#__NEXT_DATA__, script[id*="state" i]').forEach(function (script) {
      var text = script.textContent || '';
      if (!text || text.length < 20 || text.length > 5000000) return;
      try { sources.push(JSON.parse(text)); } catch (e) {}
    });

    ['__NEXT_DATA__', '__INITIAL_STATE__', '__PRELOADED_STATE__', '__APOLLO_STATE__'].forEach(function (name) {
      try {
        var value = window[name];
        if (value && typeof value === 'object') sources.push(value);
      } catch (e) {}
    });

    for (var i = 0; i < sources.length; i++) {
      var ctx = { visited: 0, seen: [] };
      var found = findLongTextInObject(sources[i], 0, ctx);
      if (found && (!best || found.score > best.score)) best = found;
    }

    embeddedJsonCache.time = now;
    embeddedJsonCache.value = best;
    return best;
  }

  function buildEmbeddedJsonExtraction(found) {
    if (!found || typeof found.text !== 'string') return null;

    var text = found.text.trim();
    if (/<[a-z][\s\S]*>/i.test(text)) {
      text = plainTextFromHtml(text);
    }
    if (text.length < 400) return null;

    var content = document.createElement('div');
    content.className = 'meo-bloomberg-reader-article';

    if (found.headline) {
      var h1 = document.createElement('h1');
      h1.className = 'meo-bloomberg-reader-title';
      h1.textContent = found.headline;
      content.appendChild(h1);
    }

    var paragraphs = text.split(/\n{2,}/);
    if (paragraphs.length <= 1) {
      paragraphs = text.split(/\n/);
    }
    if (paragraphs.length <= 1) {
      var sentences = text.split(/(?=[.!?。！？]\s)/);
      var chunks = [];
      var current = '';
      for (var i = 0; i < sentences.length; i++) {
        current += sentences[i];
        if (current.length >= 600) {
          chunks.push(current);
          current = '';
        }
      }
      if (current) chunks.push(current);
      if (chunks.length > 1) paragraphs = chunks;
    }

    for (var j = 0; j < paragraphs.length; j++) {
      var paragraphText = paragraphs[j].trim();
      if (!paragraphText) continue;
      var p = document.createElement('p');
      p.textContent = paragraphText;
      content.appendChild(p);
    }

    var textLength = textLengthOf(content);
    if (textLength < 400) return null;

    return {
      node: content,
      textLength: textLength,
      paragraphs: content.querySelectorAll('p').length,
      root: null,
      source: 'embedded-json'
    };
  }

  function extractArticleBodyText() {
    // Bloomberg 的正文段落：class 里带 ArticleBodyText_articleBodyContent。
    var nodes = deepQueryAll('[class*="ArticleBodyText_articleBodyContent" i], [class*="articleBodyContent" i]');

    if (!nodes.length) {
      // data-component="paragraph" 是更稳定的回退，但只取文章正文区域里的。
      nodes = deepQueryAll('[data-component="paragraph"]').filter(function (el) {
        return !!(el.closest && el.closest('.body-content, [class*="articleBody" i], [class*="article-body" i], [class*="story-body" i]'));
      });
    }

    if (!nodes.length) {
      nodes = deepQueryAll('.body-content p');
    }

    if (!nodes.length) return null;

    var filtered = [];
    var seenText = [];

    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!el || el.nodeType !== 1) continue;

      if (el.closest && el.closest('nav, header, footer, aside, form, ' +
          '[class*="paywall" i], [class*="related" i], [class*="morefrom" i], ' +
          '[class*="storycard" i], [class*="story-card" i], [class*="topreads" i], ' +
          '[class*="subscribe" i], [class*="advert" i], [class*="comment" i], ' +
          '[class*="promo" i], [class*="newsletter-signup" i]')) {
        continue;
      }

      var text = (el.textContent || '').replace(/\s+/g, ' ').trim();
      if (text.length < 20) continue;
      if (seenText.indexOf(text) >= 0) continue;
      seenText.push(text);
      filtered.push(el);
    }

    if (!filtered.length) return null;

    // 去掉被其他节点包含的重复节点，避免同一段出现两次。
    var unique = [];
    for (var j = 0; j < filtered.length; j++) {
      var candidate = filtered[j];
      var nested = false;
      for (var k = 0; k < filtered.length; k++) {
        if (k === j) continue;
        if (filtered[k].contains(candidate)) {
          nested = true;
          break;
        }
      }
      if (!nested) unique.push(candidate);
    }

    var content = document.createElement('div');
    content.className = 'meo-bloomberg-reader-article';

    var titleNode = extractTitle(null);
    if (titleNode) content.appendChild(titleNode);

    var bylineNode = extractByline(null);
    if (bylineNode) content.appendChild(bylineNode);

    for (var m = 0; m < unique.length; m++) {
      var clone = unique[m].cloneNode(true);
      cleanClone(clone);
      if (textLengthOf(clone) >= 20) {
        content.appendChild(clone);
      }
    }

    var textLength = textLengthOf(content);
    if (textLength < 100) return null;

    return {
      node: content,
      textLength: textLength,
      paragraphs: content.querySelectorAll('p').length,
      root: null,
      source: 'articleBodyContent'
    };
  }

  function extractArticle() {
    var targeted = extractArticleBodyText();
    var dom = extractDomArticle();
    var fallback = extractParagraphFallback();

    var bestDom = dom;
    if (fallback && (!bestDom || fallback.textLength > bestDom.textLength + 200)) {
      bestDom = fallback;
    }

    // 精确命中 ArticleBodyText 节点时优先用它，避免外层容器夹带推荐位/广告。
    var best = bestDom;
    if (targeted && targeted.textLength >= 200) {
      best = targeted;
    }

    var json = buildJsonLdExtraction(extractJsonLdArticle());
    if (json && (!best || json.textLength > best.textLength + 200)) {
      best = json;
    }

    var embedded = buildEmbeddedJsonExtraction(extractEmbeddedJsonArticle());
    if (embedded && (!best || embedded.textLength > best.textLength + 200)) {
      best = embedded;
    }

    return best;
  }

  function extractParagraphFallback() {
    var scope = document.querySelector('main, article') || document.body;
    if (!scope) return null;

    var all = queryAll('p', scope);
    var seen = [];
    var texts = [];

    for (var i = 0; i < all.length; i++) {
      var p = all[i];
      if (p.closest && p.closest('nav, header, footer, aside, form, ' +
          '[class*="paywall" i], [class*="related" i], [class*="recommend" i], ' +
          '[class*="subscribe" i], [class*="advert" i], [class*="comment" i], ' +
          '[class*="promo" i], [class*="leaderboard" i], [class*="adslot" i], ' +
          '[class*="ad-slot" i], [class*="newsletter-signup" i], [data-ad]')) {
        continue;
      }

      var text = (p.textContent || '').replace(/\s+/g, ' ').trim();
      if (text.length < 30) continue;
      if (seen.indexOf(text) >= 0) continue;
      seen.push(text);
      texts.push(text);
    }

    if (texts.join('\n').length < 400) return null;

    var content = document.createElement('div');
    content.className = 'meo-bloomberg-reader-article';

    var titleEl = document.querySelector('h1');
    var titleText = titleEl ? (titleEl.textContent || '').replace(/\s+/g, ' ').trim() : '';
    if (titleText) {
      var h1 = document.createElement('h1');
      h1.className = 'meo-bloomberg-reader-title';
      h1.textContent = titleText;
      content.appendChild(h1);
    }

    for (var j = 0; j < texts.length; j++) {
      var node = document.createElement('p');
      node.textContent = texts[j];
      content.appendChild(node);
    }

    return {
      node: content,
      textLength: textLengthOf(content),
      paragraphs: texts.length,
      root: null,
      source: 'paragraphs'
    };
  }

  // ---------- 阅读器 UI ----------

  function hideOtherTopLayers() {
    if (!state.shown || !state.dialog) return;

    function hideIfOther(el) {
      if (!el || el === state.dialog) return;
      if (state.dialog.contains(el)) return;
      el.style.setProperty('display', 'none', 'important');
    }

    // 分开查询：某个选择器不被支持时，不会让整组查询失效。
    deepQueryAll('dialog[open]').forEach(hideIfOther);
    deepQueryAll(':modal').forEach(hideIfOther);
    deepQueryAll('[popover]:popover-open').forEach(hideIfOther);
  }

  function isReaderOnTop() {
    if (!state.dialog) return true;

    // 同文档或 open shadow DOM 里还有可见的 dialog/modal，说明它可能在阅读器之上。
    var others = deepQueryAll('dialog[open]').concat(deepQueryAll(':modal'));
    for (var i = 0; i < others.length; i++) {
      var el = others[i];
      if (!el || el === state.dialog || state.dialog.contains(el)) continue;
      var cs = null;
      try { cs = window.getComputedStyle ? window.getComputedStyle(el) : null; } catch (e) { cs = null; }
      if (cs && cs.display !== 'none' && cs.visibility !== 'hidden') {
        return false;
      }
    }

    if (!document.elementsFromPoint) return true;
    var x = (window.innerWidth || 0) / 2;
    var y = (window.innerHeight || 0) * 0.3;
    var stack = [];
    try { stack = document.elementsFromPoint(x, y) || []; } catch (e) { return true; }
    if (!stack.length) return true;
    var top = stack[0];
    return top === state.dialog || state.dialog.contains(top);
  }

  function keepReaderOnTop(force) {
    if (!state.shown || !state.dialog) return;
    if (!force && isReaderOnTop()) return;

    // close + showModal 会把阅读器重新放到 top layer 的最上层，
    // 即使站点遮罩来自 closed shadow DOM / 无法直接查询的 dialog。
    try {
      state.dialog.close();
    } catch (e) {}

    try {
      if (typeof state.dialog.showModal === 'function') {
        state.dialog.showModal();
      } else {
        state.dialog.setAttribute('open', '');
      }
      try { console.log('[MeoReader] re-top'); } catch (e) {}
    } catch (e) {
      try { state.dialog.setAttribute('open', ''); } catch (e2) {}
    }

    hideOtherTopLayers();
  }

  function showReader(extraction) {
    if (!extraction || state.shown || state.destroyed || !document.body) return;

    // 如果“阅读模式”入口按钮还在，先移除，避免和阅读器叠在一起。
    if (state.reopenButton) {
      var oldButton = state.reopenButton;
      state.reopenButton = null;
      try { if (oldButton.hidePopover) oldButton.hidePopover(); } catch (e) {}
      if (oldButton.parentNode) oldButton.parentNode.removeChild(oldButton);
    }

    state.shown = true;
    state.dismissed = false;
    state.extractionLen = extraction.textLength;

    try {
      console.log('[MeoReader] show', extraction.source || 'dom', extraction.textLength);
    } catch (e) {}

    var dialog = document.createElement('dialog');
    dialog.className = 'meo-bloomberg-reader-dialog';
    dialog.setAttribute('aria-label', 'Meo 阅读模式');

    var shell = document.createElement('div');
    shell.className = 'meo-bloomberg-reader-shell';

    var bar = document.createElement('div');
    bar.className = 'meo-bloomberg-reader-bar';

    var barTitle = document.createElement('div');
    barTitle.className = 'meo-bloomberg-reader-bar-title';
    barTitle.textContent = 'Meo 阅读模式';

    var actions = document.createElement('div');
    actions.className = 'meo-bloomberg-reader-actions';

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'meo-bloomberg-reader-close';
    close.textContent = '关闭';
    close.addEventListener('click', closeReader);
    actions.appendChild(close);

    bar.appendChild(barTitle);
    bar.appendChild(actions);

    var scroll = document.createElement('div');
    scroll.className = 'meo-bloomberg-reader-scroll';

    var contentWrap = document.createElement('div');
    contentWrap.className = 'meo-bloomberg-reader-content';
    contentWrap.appendChild(extraction.node);

    scroll.appendChild(contentWrap);
    shell.appendChild(bar);
    shell.appendChild(scroll);
    dialog.appendChild(shell);
    document.body.appendChild(dialog);

    state.dialog = dialog;
    state.contentEl = contentWrap;
    state.scrollEl = scroll;

    document.documentElement.classList.add(OPEN_CLASS);

    try {
      if (typeof dialog.showModal === 'function') {
        dialog.showModal();
      } else {
        dialog.setAttribute('open', '');
      }
    } catch (e) {
      dialog.setAttribute('open', '');
    }

    dialog.addEventListener('cancel', function (event) {
      event.preventDefault();
      closeReader();
    });

    if (state.observer) {
      state.observer.disconnect();
      state.observer = null;
    }

    // 站点可能在阅读器打开后才弹出付费墙 dialog/backdrop，持续压掉其他 top-layer；
    // 如果站点重渲染把阅读器从 DOM 里移走，也把它重新挂回去。
    state.topLayerTimer = setInterval(function () {
      if (!state.shown || !state.dialog) return;
      if (!state.dialog.parentNode && document.body) {
        document.body.appendChild(state.dialog);
      }
      if (state.dialog && !state.dialog.open) {
        try { state.dialog.showModal(); } catch (e) {}
      }
      keepReaderOnTop(false);
    }, 1000);
    hideOtherTopLayers();

    // 站点通常在页面加载约 2 秒后弹出付费墙；强制把阅读器再顶到最上层。
    addTimer(function () { keepReaderOnTop(true); }, 2500);
    addTimer(function () { keepReaderOnTop(true); }, 5000);

    // 正文如果稍后才补全，自动替换一次。
    addTimer(function () { refreshReaderIfLonger(); }, 4000);
    addTimer(function () { refreshReaderIfLonger(); }, 8000);
  }

  function refreshReaderIfLonger() {
    if (!state.shown || !state.contentEl || state.destroyed) return;
    var extraction = extractArticle();
    if (!extraction || extraction.textLength <= state.extractionLen + 200) return;

    var scrollTop = state.scrollEl ? state.scrollEl.scrollTop : 0;
    state.contentEl.innerHTML = '';
    state.contentEl.appendChild(extraction.node);
    state.extractionLen = extraction.textLength;
    if (state.scrollEl) {
      state.scrollEl.scrollTop = scrollTop;
    }
  }

  function showReopenButton() {
    if (!isArticleURL()) return;
    if (state.reopenButton || !document.body || state.destroyed) return;
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'meo-bloomberg-reader-reopen';
    button.textContent = '阅读模式';

    // 支持 Popover API 时把它放进 top layer，避免被页面遮罩盖住。
    var canPopover = typeof button.showPopover === 'function';
    if (canPopover) {
      button.setAttribute('popover', 'manual');
    }

    button.addEventListener('click', function () {
      if (button.hidePopover) {
        try { button.hidePopover(); } catch (e) {}
      }
      if (button.parentNode) button.parentNode.removeChild(button);
      state.reopenButton = null;
      state.dismissed = false;
      openReaderWithRetry(0);
    });

    document.body.appendChild(button);
    state.reopenButton = button;

    if (canPopover) {
      try { button.showPopover(); } catch (e) {}
    }
  }

  function closeReader() {
    if (!state.shown) return;

    state.dismissed = true;

    state.shown = false;
    state.extractionLen = 0;

    if (state.topLayerTimer) {
      clearInterval(state.topLayerTimer);
      state.topLayerTimer = null;
    }

    var dialog = state.dialog;
    state.dialog = null;
    state.contentEl = null;
    state.scrollEl = null;

    document.documentElement.classList.remove(OPEN_CLASS);

    if (dialog) {
      try {
        if (typeof dialog.close === 'function') dialog.close();
      } catch (e) {}
      if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
    }

    showReopenButton();
  }

  // ---------- 自动触发 ----------

  function openReaderWithRetry(attempt) {
    if (state.shown || state.destroyed) return;

    var extraction = extractArticle();
    if (extraction && extraction.textLength >= 100) {
      showReader(extraction);
      return;
    }

    // 正文可能是延迟加载的：点击后持续重试几秒。
    if (attempt < 8) {
      addTimer(function () { openReaderWithRetry(attempt + 1); }, 700);
    } else {
      try { console.log('[MeoReader] manual extraction: null after retries'); } catch (e) {}
      addTimer(showReopenButton, 800);
    }
  }

  function attemptAutoShow() {
    if (state.shown || state.dismissed || state.destroyed) return;

    state.lastAttempt = {
      time: Date.now ? Date.now() : new Date().getTime(),
      path: location.pathname,
      isArticleURL: isArticleURL(),
      status: 'start'
    };

    if (!state.lastAttempt.isArticleURL) {
      state.lastAttempt.status = 'not-article';
      try { console.log('[MeoReader] skip: not article URL', location.pathname); } catch (e) {}
      return;
    }

    try {
      var extraction = extractArticle();
      if (!extraction) {
        state.lastAttempt.status = 'extract-null';
        try { console.log('[MeoReader] extract: null'); } catch (e) {}
        return;
      }

      state.lastAttempt.extracted = extraction.textLength;
      state.lastAttempt.source = extraction.source;

      var elapsed = (Date.now ? Date.now() : new Date().getTime()) - state.startTime;
      var minLength = elapsed > 6000 ? 400 : 800;
      if (extraction.textLength < minLength) {
        state.lastAttempt.status = 'too-short';
        try { console.log('[MeoReader] extract too short', extraction.textLength); } catch (e) {}
        return;
      }

      state.lastAttempt.status = 'show';
      showReader(extraction);
    } catch (e) {
      state.lastAttempt.status = 'error';
      state.lastAttempt.error = String(e);
      try { console.error('[MeoReader] attempt failed', e); } catch (e2) {}
    }
  }

  function scheduleAttempt(ms) {
    if (state.shown || state.dismissed || state.destroyed || state.attemptTimer) return;
    state.attemptTimer = setTimeout(function () {
      state.attemptTimer = null;
      attemptAutoShow();
    }, ms);
  }

  function addTimer(fn, ms) {
    if (state.destroyed) return;
    var timer = setTimeout(function () {
      var idx = state.timers.indexOf(timer);
      if (idx >= 0) state.timers.splice(idx, 1);
      if (!state.destroyed) fn();
    }, ms);
    state.timers.push(timer);
  }

  // 手动/测试入口。
  state.showNow = function () {
    try {
      var extraction = extractArticle();
      try {
        console.log('[MeoReader] showNow extraction', extraction ? extraction.textLength : null,
                    extraction ? extraction.source : 'null');
      } catch (e) {}
      if (extraction) {
        showReader(extraction);
        return true;
      }
      return false;
    } catch (e) {
      try { console.error('[MeoReader] showNow failed', e); } catch (e2) {}
      return false;
    }
  };

  // 诊断入口：用户可在 Console 里执行 __meoBloombergReader.debug()
  state.debug = function () {
    var root = null;
    try { root = findArticleRoot(); } catch (e) {}

    var dom = null;
    try {
      var d = extractDomArticle();
      if (d) dom = { textLength: d.textLength, paragraphs: d.paragraphs };
    } catch (e) {
      dom = { error: String(e) };
    }

    var targeted = null;
    try {
      var t = extractArticleBodyText();
      if (t) targeted = { textLength: t.textLength, paragraphs: t.paragraphs, source: t.source };
    } catch (e) {
      targeted = { error: String(e) };
    }

    var jsonLd = null;
    try {
      var j = extractJsonLdArticle();
      if (j) jsonLd = { headline: j.headline || '', bodyLength: (j.articleBody || '').length };
    } catch (e) {
      jsonLd = { error: String(e) };
    }

    var embeddedJson = null;
    try {
      var embedded = buildEmbeddedJsonExtraction(extractEmbeddedJsonArticle());
      if (embedded) {
        embeddedJson = {
          textLength: embedded.textLength,
          paragraphs: embedded.paragraphs,
          source: embedded.source
        };
      }
    } catch (e) {
      embeddedJson = { error: String(e) };
    }

    var best = null;
    try {
      var b = extractArticle();
      if (b) best = { textLength: b.textLength, paragraphs: b.paragraphs, source: b.source };
    } catch (e) {
      best = { error: String(e) };
    }

    return {
      path: location.pathname,
      isArticleURL: isArticleURL(),
      root: root ? {
        tag: root.tagName,
        cls: String(root.className).slice(0, 160),
        text: textLengthOf(root),
        p: root.querySelectorAll('p').length
      } : null,
      dom: dom,
      targeted: targeted,
      jsonLd: jsonLd,
      embeddedJson: embeddedJson,
      best: best,
      shown: state.shown,
      dismissed: state.dismissed,
      timerCount: state.timers.length
    };
  };

  state.destroy = function () {
    state.destroyed = true;
    if (state.observer) {
      try { state.observer.disconnect(); } catch (e) {}
      state.observer = null;
    }
    if (state.attemptTimer) {
      clearTimeout(state.attemptTimer);
      state.attemptTimer = null;
    }
    if (state.topLayerTimer) {
      clearInterval(state.topLayerTimer);
      state.topLayerTimer = null;
    }
    while (state.timers.length) {
      clearTimeout(state.timers.pop());
    }
    if (state.dialog && state.dialog.parentNode) {
      state.dialog.parentNode.removeChild(state.dialog);
    }
    if (state.reopenButton && state.reopenButton.parentNode) {
      state.reopenButton.parentNode.removeChild(state.reopenButton);
    }
    document.documentElement.classList.remove(OPEN_CLASS);
  };

  // 启动
  state.dismissed = false;

  // 默认不自动打开阅读器，避免提取失败时把原页面整页隐藏。
  // 想恢复自动模式，把这里改成 true。
  var AUTO_SHOW = false;

  if (AUTO_SHOW) {
    [1800, 3200, 5500, 9000, 14000].forEach(function (ms) {
      addTimer(attemptAutoShow, ms);
    });
    addTimer(function () {
      if (!state.shown && !state.dismissed && !state.reopenButton) {
        showReopenButton();
      }
    }, 6000);

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', attemptAutoShow, { once: true });
    }
    window.addEventListener('load', attemptAutoShow, { once: true });

    if (window.MutationObserver && document.documentElement) {
      state.observer = new MutationObserver(function () {
        if (state.shown || state.dismissed || state.destroyed) return;
        scheduleAttempt(1200);
      });
      state.observer.observe(document.documentElement, { childList: true, subtree: true });
    }
  } else {
    // 手动模式：页面正常显示，只在右下角提供「阅读模式」按钮。
    addTimer(function () {
      if (!state.shown && !state.reopenButton) showReopenButton();
    }, 1500);
    addTimer(function () {
      if (!state.shown && !state.reopenButton) showReopenButton();
    }, 4000);
  }

  try { console.log('[MeoReader] installed (manual mode)'); } catch (e) {}
})();
