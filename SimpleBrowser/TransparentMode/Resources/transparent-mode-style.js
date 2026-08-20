(function () {
  /* 幂等：避免 evaluateJavaScript 重复注入时叠多层 hook */
  if (window.__MeoTransparentMode && window.__MeoTransparentMode.__v === 3) {
    return;
  }

  var STYLE_ID = "meo-transparent-mode";
  var MARK_ATTR = "data-meo-tm-color";
  var SKIP_TAGS = {
    IMG: 1, PICTURE: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, SVG: 1, IFRAME: 1,
    SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, NOSCRIPT: 1, BR: 1, HR: 1,
    SOURCE: 1, TRACK: 1, PARAM: 1, COL: 1, COLGROUP: 1, TEMPLATE: 1,
    PATH: 1, CIRCLE: 1, RECT: 1, LINE: 1, POLYGON: 1, POLYLINE: 1, G: 1, USE: 1, DEFS: 1, SYMBOL: 1
  };

  /* 状态挂在 window 上，hook 始终读最新值 */
  var state = window.__MeoTMState || (window.__MeoTMState = {
    enabled: false,
    color: "#f2f2f2",
    shadow: "0 0 3px rgba(0,0,0,0.95)"
  });

  var observer = null;
  var paintScheduled = false;
  var canvasHookInstalled = !!window.__MeoTMCanvasHooked;
  var repaintTimers = [];

  function parseHex(color) {
    if (!color || typeof color !== "string") {
      return { r: 242, g: 242, b: 242 };
    }
    var value = color.trim().toLowerCase();
    if (value.charAt(0) === "#") {
      value = value.slice(1);
    }
    if (value.length === 3) {
      value = value[0] + value[0] + value[1] + value[1] + value[2] + value[2];
    }
    if (!/^[0-9a-f]{6}$/.test(value)) {
      return { r: 242, g: 242, b: 242 };
    }
    return {
      r: parseInt(value.slice(0, 2), 16),
      g: parseInt(value.slice(2, 4), 16),
      b: parseInt(value.slice(4, 6), 16)
    };
  }

  function toHex(rgb) {
    function part(n) {
      var h = Math.max(0, Math.min(255, n | 0)).toString(16);
      return h.length === 1 ? "0" + h : h;
    }
    return "#" + part(rgb.r) + part(rgb.g) + part(rgb.b);
  }

  function contrastShadow(rgb) {
    var luminance = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255;
    if (luminance >= 0.55) {
      return "0 0 3px rgba(0,0,0,0.95), 0 1px 2px rgba(0,0,0,0.98), 0 0 1px rgba(0,0,0,0.85)";
    }
    return "0 0 3px rgba(255,255,255,0.92), 0 1px 2px rgba(255,255,255,0.85), 0 0 1px rgba(255,255,255,0.7)";
  }

  function buildCSS(hex, shadow) {
    return (
      "html, body, div, section, article, main, header, footer, aside, nav," +
      "span, p, li, ul, ol, dl, dt, dd, td, th, blockquote, pre, code, figure, figcaption," +
      "form, fieldset, label, table, thead, tbody, tfoot, tr {" +
      "  background-color: transparent !important;" +
      "  background-image: none !important;" +
      "  box-shadow: none !important;" +
      "  border-color: transparent !important;" +
      "}" +
      "html, html body, html body *:not(img):not(picture):not(video):not(canvas):not(svg):not(iframe)," +
      "html body *::before, html body *::after {" +
      "  color: " + hex + " !important;" +
      "  -webkit-text-fill-color: " + hex + " !important;" +
      "  text-shadow: " + shadow + " !important;" +
      "  caret-color: " + hex + " !important;" +
      "}"
    );
  }

  function ensureRoot() {
    return document.head || document.documentElement;
  }

  function shouldSkip(el) {
    if (!el || el.nodeType !== 1 || !el.tagName) {
      return true;
    }
    return !!SKIP_TAGS[el.tagName];
  }

  function paintElement(el) {
    if (shouldSkip(el)) {
      return;
    }
    try {
      el.style.setProperty("color", state.color, "important");
      el.style.setProperty("-webkit-text-fill-color", state.color, "important");
      el.style.setProperty("text-shadow", state.shadow, "important");
      el.style.setProperty("caret-color", state.color, "important");
      el.setAttribute(MARK_ATTR, "1");
    } catch (e) {
    }
  }

  function clearElement(el) {
    if (!el || el.nodeType !== 1 || el.getAttribute(MARK_ATTR) !== "1") {
      return;
    }
    try {
      el.style.removeProperty("color");
      el.style.removeProperty("-webkit-text-fill-color");
      el.style.removeProperty("text-shadow");
      el.style.removeProperty("caret-color");
      el.removeAttribute(MARK_ATTR);
    } catch (e) {
    }
  }

  function walk(root, fn) {
    if (!root) {
      return;
    }
    if (root.nodeType === 1) {
      fn(root);
      if (root.shadowRoot) {
        walk(root.shadowRoot, fn);
      }
    }
    var list;
    try {
      list = root.querySelectorAll ? root.querySelectorAll("*") : [];
    } catch (e) {
      list = [];
    }
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      fn(el);
      if (el.shadowRoot) {
        walk(el.shadowRoot, fn);
      }
    }
  }

  function paintAll() {
    if (!document.documentElement) {
      return;
    }
    walk(document.documentElement, paintElement);
  }

  function clearAll() {
    if (!document.documentElement) {
      return;
    }
    walk(document.documentElement, clearElement);
  }

  function schedulePaint() {
    if (paintScheduled) {
      return;
    }
    paintScheduled = true;
    var run = function () {
      paintScheduled = false;
      if (state.enabled) {
        paintAll();
      }
    };
    if (typeof requestAnimationFrame === "function") {
      requestAnimationFrame(run);
    } else {
      setTimeout(run, 16);
    }
  }

  function startObserver() {
    stopObserver();
    if (!document.documentElement || typeof MutationObserver !== "function") {
      return;
    }
    observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === "childList" && m.addedNodes && m.addedNodes.length) {
          schedulePaint();
          return;
        }
      }
    });
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  function stopObserver() {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    paintScheduled = false;
  }

  function installCanvasTextHook() {
    if (canvasHookInstalled) {
      return;
    }
    var proto = null;
    try {
      proto = CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
    } catch (e) {
      return;
    }
    if (!proto || typeof proto.fillText !== "function") {
      return;
    }
    canvasHookInstalled = true;
    window.__MeoTMCanvasHooked = true;

    var originalFillText = proto.fillText;
    var originalStrokeText = proto.strokeText;

    proto.fillText = function () {
      if (window.__MeoTMState && window.__MeoTMState.enabled) {
        try {
          this.fillStyle = window.__MeoTMState.color;
        } catch (e) {
        }
      }
      return originalFillText.apply(this, arguments);
    };

    if (typeof originalStrokeText === "function") {
      proto.strokeText = function () {
        if (window.__MeoTMState && window.__MeoTMState.enabled) {
          try {
            this.strokeStyle = window.__MeoTMState.color;
          } catch (e) {
          }
        }
        return originalStrokeText.apply(this, arguments);
      };
    }
  }

  /**
   * 立刻改已画好的 Canvas 像素（微信读书正文层通常是透明底+文字）。
   * 保留 alpha，只替换 RGB → 抗锯齿描边仍在，颜色立即变成设置色。
   */
  function recolorExistingCanvases() {
    if (!state.enabled || !document.querySelectorAll) {
      return;
    }
    var rgb = parseHex(state.color);
    var canvases = document.querySelectorAll("canvas");
    for (var i = 0; i < canvases.length; i++) {
      var canvas = canvases[i];
      var w = canvas.width | 0;
      var h = canvas.height | 0;
      if (w < 2 || h < 2) {
        continue;
      }
      try {
        var ctx = canvas.getContext("2d");
        if (!ctx) {
          continue;
        }
        var img = ctx.getImageData(0, 0, w, h);
        var d = img.data;
        for (var p = 0; p < d.length; p += 4) {
          if (d[p + 3] === 0) {
            continue;
          }
          d[p] = rgb.r;
          d[p + 1] = rgb.g;
          d[p + 2] = rgb.b;
        }
        ctx.putImageData(img, 0, 0);
      } catch (e) {
        /* 跨域/污染画布忽略 */
      }
    }
  }

  function clearRepaintTimers() {
    for (var i = 0; i < repaintTimers.length; i++) {
      clearTimeout(repaintTimers[i]);
    }
    repaintTimers = [];
  }

  function nudgeReaderRedraw() {
    try {
      window.dispatchEvent(new Event("resize"));
    } catch (e) {
    }
    try {
      if (window.visualViewport) {
        window.visualViewport.dispatchEvent(new Event("resize"));
      }
    } catch (e) {
    }
    try {
      var y = window.scrollY || document.documentElement.scrollTop || 0;
      window.scrollTo(0, y + 1);
      window.scrollTo(0, y);
    } catch (e) {
    }
  }

  /** 立即换色 + 促使阅读器后续用 hook 重画 */
  function applyCanvasColorNow() {
    recolorExistingCanvases();
    nudgeReaderRedraw();
  }

  function scheduleDeferredCanvasRecolor() {
    clearRepaintTimers();
    var delays = [0, 32, 100, 250, 600];
    for (var i = 0; i < delays.length; i++) {
      (function (ms) {
        repaintTimers.push(setTimeout(function () {
          if (state.enabled) {
            recolorExistingCanvases();
            nudgeReaderRedraw();
          }
        }, ms));
      })(delays[i]);
    }
  }

  window.__MeoTransparentMode = {
    __v: 3,
    apply: function (color) {
      if (!document.documentElement) {
        return;
      }
      var rgb = parseHex(color);
      state.color = toHex(rgb);
      state.shadow = contrastShadow(rgb);
      state.enabled = true;

      installCanvasTextHook();

      var style = document.getElementById(STYLE_ID);
      if (!style) {
        style = document.createElement("style");
        style.id = STYLE_ID;
        ensureRoot().appendChild(style);
      }
      style.textContent = buildCSS(state.color, state.shadow);
      if (style.parentNode) {
        style.parentNode.appendChild(style);
      }

      paintAll();
      startObserver();
      applyCanvasColorNow();
      scheduleDeferredCanvasRecolor();
    },
    remove: function () {
      state.enabled = false;
      clearRepaintTimers();
      stopObserver();
      clearAll();
      var style = document.getElementById(STYLE_ID);
      if (style && style.parentNode) {
        style.parentNode.removeChild(style);
      }
      nudgeReaderRedraw();
    }
  };

  /* document-start 注入时尽早挂钩，刷新后首屏即可用新色绘制 */
  installCanvasTextHook();
})();
