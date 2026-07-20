(function () {
  if (window.__MeoFind) {
    return;
  }

  var STYLE_ID = "meo-find-style";
  var MARK_ATTR = "data-meo-find";
  var CURRENT_ATTR = "data-meo-find-current";
  var MAX_MATCHES = 2000;
  var MUTATION_DEBOUNCE_MS = 300;
  var OBSERVER_RESUME_MS = 120;

  var marks = [];
  var currentIndex = -1;
  var truncated = false;
  var lastOptions = null;
  var mutationTimer = null;
  var resumeTimer = null;
  var observer = null;
  var applying = false;
  var suppressMutations = false;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent =
      "span[" + MARK_ATTR + "]{" +
      "background-color:rgba(255,214,0,0.55)!important;" +
      "color:inherit!important;" +
      "border-radius:2px;" +
      "box-decoration-break:clone;-webkit-box-decoration-break:clone;" +
      "}" +
      "span[" + CURRENT_ATTR + "]{" +
      "background-color:rgba(255,140,0,0.85)!important;" +
      "outline:1px solid rgba(200,90,0,0.9);" +
      "}";
    (document.head || document.documentElement).appendChild(style);
  }

  function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function buildRegExp(query, mode, caseSensitive) {
    if (!query) {
      return null;
    }
    if (mode === "wildcard") {
      if (query === "*") {
        return { invalid: true };
      }
      var parts = query.split("*");
      var body = parts.map(escapeRegExp).join("[\\s\\S]*?");
      if (!body) {
        return { invalid: true };
      }
      return new RegExp(body, caseSensitive ? "g" : "gi");
    }
    return new RegExp(escapeRegExp(query), caseSensitive ? "g" : "gi");
  }

  function isSkippedElement(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    var tag = el.tagName;
    if (!tag) {
      return false;
    }
    tag = tag.toUpperCase();
    if (
      tag === "SCRIPT" ||
      tag === "STYLE" ||
      tag === "NOSCRIPT" ||
      tag === "TEXTAREA" ||
      tag === "INPUT" ||
      tag === "SELECT" ||
      tag === "OPTION" ||
      tag === "SVG" ||
      tag === "MATH"
    ) {
      return true;
    }
    if (el.isContentEditable) {
      return true;
    }
    if (el.getAttribute && el.getAttribute(MARK_ATTR) != null) {
      return true;
    }
    return false;
  }

  function clearMarks() {
    for (var i = marks.length - 1; i >= 0; i--) {
      var mark = marks[i];
      var parent = mark.parentNode;
      if (!parent) {
        continue;
      }
      while (mark.firstChild) {
        parent.insertBefore(mark.firstChild, mark);
      }
      parent.removeChild(mark);
      parent.normalize();
    }
    marks = [];
    currentIndex = -1;
    truncated = false;
  }

  function collectTextNodes(root) {
    var nodes = [];
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node || !node.nodeValue || !node.nodeValue.trim()) {
          return NodeFilter.FILTER_REJECT;
        }
        var parent = node.parentElement;
        while (parent && parent !== root) {
          if (isSkippedElement(parent)) {
            return NodeFilter.FILTER_REJECT;
          }
          parent = parent.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var n;
    while ((n = walker.nextNode())) {
      nodes.push(n);
    }
    return nodes;
  }

  function wrapMatchesInTextNode(textNode, regex) {
    var text = textNode.nodeValue;
    if (!text) {
      return;
    }
    regex.lastIndex = 0;
    var matches = [];
    var m;
    while ((m = regex.exec(text)) !== null) {
      if (m[0].length === 0) {
        regex.lastIndex++;
        continue;
      }
      matches.push({ start: m.index, end: m.index + m[0].length });
      if (marks.length + matches.length >= MAX_MATCHES) {
        truncated = true;
        break;
      }
    }
    if (matches.length === 0) {
      return;
    }

    var frag = document.createDocumentFragment();
    var last = 0;
    for (var i = 0; i < matches.length; i++) {
      var match = matches[i];
      if (match.start > last) {
        frag.appendChild(document.createTextNode(text.slice(last, match.start)));
      }
      var span = document.createElement("span");
      span.setAttribute(MARK_ATTR, "1");
      span.textContent = text.slice(match.start, match.end);
      frag.appendChild(span);
      marks.push(span);
      last = match.end;
      if (marks.length >= MAX_MATCHES) {
        truncated = true;
        break;
      }
    }
    if (last < text.length) {
      frag.appendChild(document.createTextNode(text.slice(last)));
    }
    textNode.parentNode.replaceChild(frag, textNode);
  }

  function setCurrent(index) {
    if (currentIndex >= 0 && currentIndex < marks.length) {
      marks[currentIndex].removeAttribute(CURRENT_ATTR);
    }
    currentIndex = index;
    if (currentIndex >= 0 && currentIndex < marks.length) {
      var el = marks[currentIndex];
      el.setAttribute(CURRENT_ATTR, "1");
      try {
        // 避免 smooth 滚动触发懒加载 DOM，进而误触发 Mutation 重搜。
        el.scrollIntoView({ block: "center", inline: "nearest", behavior: "instant" });
      } catch (e) {
        try {
          el.scrollIntoView({ block: "center", inline: "nearest" });
        } catch (e2) {
          el.scrollIntoView(true);
        }
      }
    }
  }

  function resultPayload(wrapped) {
    return {
      matchCount: marks.length,
      currentIndex: marks.length === 0 ? 0 : currentIndex + 1,
      wrapped: !!wrapped,
      truncated: !!truncated,
      invalidQuery: false
    };
  }

  function beginDOMEdit() {
    suppressMutations = true;
    if (mutationTimer) {
      clearTimeout(mutationTimer);
      mutationTimer = null;
    }
    if (observer) {
      observer.disconnect();
      observer = null;
    }
  }

  function endDOMEditAndWatch() {
    if (resumeTimer) {
      clearTimeout(resumeTimer);
    }
    // 等本轮 DOM 变更刷完再恢复观察，避免把自己的 mark 当成页面更新。
    resumeTimer = setTimeout(function () {
      resumeTimer = null;
      suppressMutations = false;
      if (lastOptions && lastOptions.query) {
        ensureObserver();
      }
    }, OBSERVER_RESUME_MS);
  }

  function search(options) {
    ensureStyle();
    beginDOMEdit();

    var preserveIndex = !!(options && options.preserveIndex);
    var previousIndex = currentIndex;

    clearMarks();
    lastOptions = options ? {
      query: options.query,
      mode: options.mode,
      caseSensitive: options.caseSensitive
    } : {};

    var query = (lastOptions.query || "").toString();
    if (!query) {
      endDOMEditAndWatch();
      return resultPayload(false);
    }
    var built = buildRegExp(query, lastOptions.mode || "literal", !!lastOptions.caseSensitive);
    if (!built) {
      endDOMEditAndWatch();
      return resultPayload(false);
    }
    if (built.invalid) {
      endDOMEditAndWatch();
      return {
        matchCount: 0,
        currentIndex: 0,
        wrapped: false,
        truncated: false,
        invalidQuery: true
      };
    }

    applying = true;
    var roots = [document.body || document.documentElement];
    for (var r = 0; r < roots.length; r++) {
      if (!roots[r]) {
        continue;
      }
      var nodes = collectTextNodes(roots[r]);
      for (var i = 0; i < nodes.length; i++) {
        if (marks.length >= MAX_MATCHES) {
          truncated = true;
          break;
        }
        var re = buildRegExp(query, lastOptions.mode || "literal", !!lastOptions.caseSensitive);
        wrapMatchesInTextNode(nodes[i], re);
      }
    }
    applying = false;

    if (marks.length > 0) {
      var idx = 0;
      if (preserveIndex && previousIndex >= 0) {
        idx = Math.min(previousIndex, marks.length - 1);
      }
      setCurrent(idx);
    }

    endDOMEditAndWatch();
    return resultPayload(false);
  }

  function next() {
    if (marks.length === 0) {
      return resultPayload(false);
    }
    var wrapped = false;
    var nextIndex = currentIndex + 1;
    if (nextIndex >= marks.length) {
      nextIndex = 0;
      wrapped = true;
    }
    setCurrent(nextIndex);
    return resultPayload(wrapped);
  }

  function prev() {
    if (marks.length === 0) {
      return resultPayload(false);
    }
    var wrapped = false;
    var prevIndex = currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = marks.length - 1;
      wrapped = true;
    }
    setCurrent(prevIndex);
    return resultPayload(wrapped);
  }

  function clear() {
    beginDOMEdit();
    lastOptions = null;
    clearMarks();
    if (resumeTimer) {
      clearTimeout(resumeTimer);
      resumeTimer = null;
    }
    suppressMutations = false;
    return resultPayload(false);
  }

  function mutationIsOnlyOurMarks(records) {
    for (var i = 0; i < records.length; i++) {
      var record = records[i];
      var nodes = [];
      if (record.addedNodes && record.addedNodes.length) {
        for (var a = 0; a < record.addedNodes.length; a++) {
          nodes.push(record.addedNodes[a]);
        }
      }
      if (record.removedNodes && record.removedNodes.length) {
        for (var r = 0; r < record.removedNodes.length; r++) {
          nodes.push(record.removedNodes[r]);
        }
      }
      if (nodes.length === 0) {
        var t = record.target;
        if (t && t.nodeType === 1 && t.getAttribute && t.getAttribute(MARK_ATTR) != null) {
          continue;
        }
        if (t && t.parentElement && t.parentElement.getAttribute &&
            t.parentElement.getAttribute(MARK_ATTR) != null) {
          continue;
        }
        return false;
      }
      for (var n = 0; n < nodes.length; n++) {
        var node = nodes[n];
        if (node.nodeType === 1 && node.getAttribute && node.getAttribute(MARK_ATTR) != null) {
          continue;
        }
        if (node.nodeType === 3 && node.parentElement &&
            node.parentElement.getAttribute &&
            node.parentElement.getAttribute(MARK_ATTR) != null) {
          continue;
        }
        return false;
      }
    }
    return true;
  }

  function ensureObserver() {
    if (observer || !lastOptions || !lastOptions.query || suppressMutations) {
      return;
    }
    var root = document.body || document.documentElement;
    if (!root || typeof MutationObserver === "undefined") {
      return;
    }
    observer = new MutationObserver(function (records) {
      if (suppressMutations || applying || !lastOptions || !lastOptions.query) {
        return;
      }
      if (mutationIsOnlyOurMarks(records)) {
        return;
      }
      if (mutationTimer) {
        clearTimeout(mutationTimer);
      }
      mutationTimer = setTimeout(function () {
        mutationTimer = null;
        if (suppressMutations || !lastOptions || !lastOptions.query) {
          return;
        }
        // 页面真实更新：重搜并尽量保持当前命中序号。
        search({
          query: lastOptions.query,
          mode: lastOptions.mode,
          caseSensitive: lastOptions.caseSensitive,
          preserveIndex: true
        });
      }, MUTATION_DEBOUNCE_MS);
    });
    observer.observe(root, { childList: true, subtree: true, characterData: true });
  }

  window.__MeoFind = {
    search: search,
    next: next,
    prev: prev,
    clear: clear,
    selectionText: function () {
      try {
        return window.getSelection().toString() || "";
      } catch (e) {
        return "";
      }
    }
  };
})();
