(function () {
  /* 每次注入都刷新 apply/remove。
     Canvas 字色/阴影只用 CSS filter（不改像素），退出时可瞬间恢复原貌。 */
  var STYLE_ID = "meo-transparent-mode";
  var SVG_FILTER_HOST_ID = "meo-tm-svg-filters";
  var CANVAS_RECOLOR_FILTER_ID = "meo-tm-canvas-recolor";
  var MARK_ATTR = "data-meo-tm-color";
  var SKIP_TAGS = {
    IMG: 1, PICTURE: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, SVG: 1, IFRAME: 1,
    SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, NOSCRIPT: 1, BR: 1, HR: 1,
    SOURCE: 1, TRACK: 1, PARAM: 1, COL: 1, COLGROUP: 1, TEMPLATE: 1,
    PATH: 1, CIRCLE: 1, RECT: 1, LINE: 1, POLYGON: 1, POLYLINE: 1, G: 1, USE: 1, DEFS: 1, SYMBOL: 1
  };

  /* 状态挂在 window 上 */
  var state = window.__MeoTMState || (window.__MeoTMState = {
    enabled: false,
    color: "#f2f2f2",
    shadow: "0 0 3px rgba(0,0,0,0.95)",
    shadowColor: "#000000",
    shadowStrength: 0.9,
    shadowRadius: 3,
    canvasShadowColor: "rgba(0,0,0,0.9)",
    canvasShadowBlur: 3,
    canvasShadowOffsetY: 1
  });

  var observer = window.__MeoTMObserver || null;
  var paintScheduled = false;
  var repaintTimers = window.__MeoTMRepaintTimers || (window.__MeoTMRepaintTimers = []);

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

  function clamp(n, lo, hi) {
    n = Number(n);
    if (!(n === n)) { // NaN
      return lo;
    }
    return Math.max(lo, Math.min(hi, n));
  }

  function rgba(rgb, alpha) {
    return "rgba(" + (rgb.r | 0) + "," + (rgb.g | 0) + "," + (rgb.b | 0) + "," + Number(alpha).toFixed(3) + ")";
  }

  function buildShadow(shadowRgb, strength, radius) {
    strength = clamp(strength, 0, 1);
    radius = clamp(radius, 0, 24);
    var blur = radius;
    var soft = Math.max(0, radius * 0.55);
    var offset = Math.max(0, Math.round(radius * 0.35 * 10) / 10);
    var aOuter = (0.35 + 0.65 * strength);
    var aInner = (0.45 + 0.55 * strength);
    var aCore = (0.25 + 0.6 * strength);
    if (strength <= 0.001 || radius <= 0.001) {
      return "none";
    }
    return (
      "0 0 " + blur + "px " + rgba(shadowRgb, aOuter) + ", " +
      "0 " + offset + "px " + soft + "px " + rgba(shadowRgb, aInner) + ", " +
      "0 0 " + Math.max(1, blur * 0.35) + "px " + rgba(shadowRgb, aCore)
    );
  }

  function ensureRoot() {
    return document.head || document.documentElement;
  }

  /** SVG feColorMatrix：只改显示色、保留 alpha，不改 Canvas 像素 */
  function ensureCanvasRecolorSVG(rgb) {
    var host = document.getElementById(SVG_FILTER_HOST_ID);
    if (!host) {
      host = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      host.setAttribute("id", SVG_FILTER_HOST_ID);
      host.setAttribute("width", "0");
      host.setAttribute("height", "0");
      host.setAttribute("aria-hidden", "true");
      host.style.cssText = "position:absolute;width:0;height:0;overflow:hidden;pointer-events:none;";
      ensureRoot().appendChild(host);
    }
    var r = (rgb.r / 255).toFixed(6);
    var g = (rgb.g / 255).toFixed(6);
    var b = (rgb.b / 255).toFixed(6);
    var matrix =
      "0 0 0 0 " + r + " 0 0 0 0 " + g + " 0 0 0 0 " + b + " 0 0 0 1 0";
    host.innerHTML =
      '<filter id="' + CANVAS_RECOLOR_FILTER_ID + '" color-interpolation-filters="sRGB">' +
      '<feColorMatrix type="matrix" values="' + matrix + '"/>' +
      "</filter>";
  }

  function removeCanvasRecolorSVG() {
    var host = document.getElementById(SVG_FILTER_HOST_ID);
    if (host && host.parentNode) {
      host.parentNode.removeChild(host);
    }
  }

  function buildCanvasDropShadow(shadowRgb, strength, radius) {
    strength = clamp(strength, 0, 1);
    radius = clamp(radius, 0, 24);
    if (strength <= 0.001 || radius <= 0.001) {
      return "";
    }
    var a = 0.35 + 0.65 * strength;
    var offset = Math.max(0, Math.round(radius * 0.35 * 10) / 10);
    return (
      "drop-shadow(0 0 " + radius + "px " + rgba(shadowRgb, a) + ") " +
      "drop-shadow(0 " + offset + "px " + Math.max(1, radius * 0.55) + "px " + rgba(shadowRgb, a) + ")"
    );
  }

  function buildCanvasCompositeFilter(textRgb, shadowRgb, strength, radius) {
    ensureCanvasRecolorSVG(textRgb);
    var parts = ["url(#" + CANVAS_RECOLOR_FILTER_ID + ")"];
    var shadowPart = buildCanvasDropShadow(shadowRgb, strength, radius);
    if (shadowPart) {
      parts.push(shadowPart);
    }
    return parts.join(" ");
  }

  function buildCSS(hex, shadow, canvasFilter) {
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
      "}" +
      "canvas {" +
      "  filter: " + (canvasFilter || "none") + " !important;" +
      "}"
    );
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
    try {
      var marked = document.querySelectorAll("[" + MARK_ATTR + "]");
      for (var i = 0; i < marked.length; i++) {
        clearElement(marked[i]);
      }
    } catch (e) {
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
    window.__MeoTMObserver = observer;
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  function stopObserver() {
    var obs = observer || window.__MeoTMObserver;
    if (obs) {
      obs.disconnect();
    }
    observer = null;
    window.__MeoTMObserver = null;
    paintScheduled = false;
  }

  /**
   * 旧版曾 hook fillText 改像素色，导致退出后必须刷新才能恢复。
   * 现在改为 CSS filter；若页面上仍挂着旧 hook，从干净 iframe 取回原生方法并卸掉。
   */
  function captureNativeCanvasTextMethods() {
    if (window.__MeoTMCanvasOrig &&
        typeof window.__MeoTMCanvasOrig.fillText === "function") {
      return window.__MeoTMCanvasOrig;
    }
    try {
      var iframe = document.createElement("iframe");
      iframe.style.cssText = "display:none;width:0;height:0;border:0;position:absolute;";
      iframe.setAttribute("aria-hidden", "true");
      (document.documentElement || document.body).appendChild(iframe);
      var iproto = iframe.contentWindow.CanvasRenderingContext2D.prototype;
      window.__MeoTMCanvasOrig = {
        fillText: iproto.fillText,
        strokeText: iproto.strokeText
      };
      iframe.parentNode.removeChild(iframe);
    } catch (e) {
      try {
        var proto = CanvasRenderingContext2D.prototype;
        if (!window.__MeoTMCanvasHooked) {
          window.__MeoTMCanvasOrig = {
            fillText: proto.fillText,
            strokeText: proto.strokeText
          };
        }
      } catch (e2) {
      }
    }
    return window.__MeoTMCanvasOrig || null;
  }

  function uninstallCanvasTextHook() {
    try {
      var proto = CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
      if (!proto) {
        return;
      }
      var orig = captureNativeCanvasTextMethods();
      if (orig) {
        if (typeof orig.fillText === "function") {
          proto.fillText = orig.fillText;
        }
        if (typeof orig.strokeText === "function") {
          proto.strokeText = orig.strokeText;
        }
      }
      window.__MeoTMCanvasHooked = false;
    } catch (e) {
    }
  }

  function rememberNativeCanvasTextIfNeeded() {
    captureNativeCanvasTextMethods();
  }

  function parseApplyOptions(opts) {
    var color = "#f2f2f2";
    var shadowColor = "#000000";
    var strength = 0.9;
    var radius = 3;
    if (typeof opts === "string") {
      color = opts;
    } else if (opts && typeof opts === "object") {
      if (opts.color) color = opts.color;
      if (opts.shadowColor) shadowColor = opts.shadowColor;
      if (opts.shadowStrength != null) strength = opts.shadowStrength;
      if (opts.shadowRadius != null) radius = opts.shadowRadius;
    }
    return {
      color: color,
      shadowColor: shadowColor,
      strength: strength,
      radius: radius
    };
  }

  function commitStyleState(opts) {
    var o = parseApplyOptions(opts);
    var rgb = parseHex(o.color);
    var shadowRgb = parseHex(o.shadowColor);
    state.color = toHex(rgb);
    state.shadowColor = toHex(shadowRgb);
    state.shadowStrength = clamp(o.strength, 0, 1);
    state.shadowRadius = clamp(o.radius, 0, 24);
    state.shadow = buildShadow(shadowRgb, state.shadowStrength, state.shadowRadius);
    var shadowAlpha = (0.35 + 0.65 * state.shadowStrength);
    state.canvasShadowColor = rgba(shadowRgb, shadowAlpha);
    state.canvasShadowBlur = state.shadowRadius;
    state.canvasShadowOffsetY = Math.max(0, Math.round(state.shadowRadius * 0.35 * 10) / 10);
    state._shadowRgb = shadowRgb;
    state._textRgb = rgb;
    return { rgb: rgb, shadowRgb: shadowRgb };
  }

  function ensureStyleTag() {
    var style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      ensureRoot().appendChild(style);
    }
    return style;
  }

  function writeStylesheet() {
    var textRgb = state._textRgb || parseHex(state.color);
    var shadowRgb = state._shadowRgb || parseHex(state.shadowColor || "#000000");
    var canvasFilter = buildCanvasCompositeFilter(
      textRgb,
      shadowRgb,
      state.shadowStrength,
      state.shadowRadius
    );
    var style = ensureStyleTag();
    style.textContent = buildCSS(state.color, state.shadow, canvasFilter);
    if (style.parentNode) {
      style.parentNode.appendChild(style);
    }
  }

  function clearRepaintTimers() {
    var timers = window.__MeoTMRepaintTimers || repaintTimers;
    for (var i = 0; i < timers.length; i++) {
      var id = timers[i];
      try {
        cancelAnimationFrame(id);
      } catch (e1) {
      }
      try {
        clearTimeout(id);
      } catch (e2) {
      }
    }
    timers.length = 0;
    repaintTimers = timers;
    window.__MeoTMRepaintTimers = timers;
  }

  function clearCanvasInlineFilters() {
    try {
      var canvases = document.querySelectorAll("canvas");
      for (var i = 0; i < canvases.length; i++) {
        var c = canvases[i];
        c.style.removeProperty("filter");
        c.style.removeProperty("-webkit-filter");
      }
    } catch (e) {
    }
  }

  window.__MeoTransparentMode = {
    __v: 10,
    /** 进入透明模式 / 导航完成后 */
    apply: function (opts) {
      if (!document.documentElement) {
        return;
      }
      rememberNativeCanvasTextIfNeeded();
      uninstallCanvasTextHook();
      var wasEnabled = !!state.enabled;
      commitStyleState(opts);
      state.enabled = true;
      writeStylesheet();
      if (!wasEnabled) {
        paintAll();
        startObserver();
      } else if (!window.__MeoTMObserver) {
        startObserver();
      }
    },
    /** 设置变更：只改 stylesheet / canvas CSS filter，实时且可逆 */
    refresh: function (opts) {
      if (!document.documentElement) {
        return;
      }
      if (!state.enabled) {
        window.__MeoTransparentMode.apply(opts);
        return;
      }
      commitStyleState(opts);
      writeStylesheet();
    },
    /** 退出：移除滤镜与样式，像素未改写故立刻恢复原色，无需刷新 */
    remove: function () {
      state.enabled = false;
      clearRepaintTimers();
      stopObserver();
      clearAll();
      var style = document.getElementById(STYLE_ID);
      if (style && style.parentNode) {
        style.parentNode.removeChild(style);
      }
      removeCanvasRecolorSVG();
      clearCanvasInlineFilters();
      rememberNativeCanvasTextIfNeeded();
      uninstallCanvasTextHook();
    }
  };

  rememberNativeCanvasTextIfNeeded();
  uninstallCanvasTextHook();
})();
