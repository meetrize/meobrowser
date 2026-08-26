(function () {
  /* 每次注入都刷新 apply/remove。
     Canvas 字色/阴影只用 CSS filter（不改像素），退出时可瞬间恢复原貌。 */
  var STYLE_ID = "meo-transparent-mode";
  var CANVAS_STYLE_ID = "meo-transparent-mode-canvas";
  var ROOT_CLASS = "meo-transparent-mode";
  var POINTER_OUTSIDE_CLASS = "meo-pointer-outside";
  var SVG_FILTER_HOST_ID = "meo-tm-svg-filters";
  var CANVAS_RECOLOR_FILTER_ID = "meo-tm-canvas-recolor";
  var MARK_ATTR = "data-meo-tm-color";
  /* 微信读书底栏 + 翻页钮（迁入前也在栏外）：用 @scope … to() 排除（勿用 revert） */
  var READER_CONTROLS_SELECTOR = ".readerControls, #readerControls";
  var SCOPE_LIMIT_SELECTOR =
    ".readerControls, #readerControls, .renderTarget_pager, " +
    ".renderTarget_pager_button, .renderTarget_pager_button_right, [data-meo-weread-pager]";
  var SKIP_TAGS = {
    IMG: 1, PICTURE: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, SVG: 1, IFRAME: 1,
    SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, NOSCRIPT: 1, BR: 1, HR: 1,
    SOURCE: 1, TRACK: 1, PARAM: 1, COL: 1, COLGROUP: 1, TEMPLATE: 1,
    PATH: 1, CIRCLE: 1, RECT: 1, LINE: 1, POLYGON: 1, POLYLINE: 1, G: 1, USE: 1, DEFS: 1, SYMBOL: 1
  };

  var state = window.__MeoTMState || (window.__MeoTMState = {
    enabled: false,
    pointerOutside: false,
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
    if (!(n === n)) {
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
    var filter = host.querySelector("#" + CANVAS_RECOLOR_FILTER_ID);
    if (!filter) {
      host.innerHTML =
        '<filter id="' + CANVAS_RECOLOR_FILTER_ID + '" color-interpolation-filters="sRGB">' +
        '<feColorMatrix type="matrix" values="' + matrix + '"/>' +
        "</filter>";
      return;
    }
    var fe = filter.querySelector("feColorMatrix");
    if (fe) {
      fe.setAttribute("values", matrix);
    }
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

  function isInReaderControls(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    try {
      if (el.id === "readerControls") {
        return true;
      }
      if (el.classList && el.classList.contains("readerControls")) {
        return true;
      }
      if (typeof el.closest === "function") {
        return !!el.closest(READER_CONTROLS_SELECTOR);
      }
    } catch (e) {
    }
    return false;
  }

  function isWereadChrome(el) {
    if (isInReaderControls(el)) {
      return true;
    }
    if (!el || el.nodeType !== 1) {
      return false;
    }
    try {
      if (el.hasAttribute && el.hasAttribute("data-meo-weread-pager")) {
        return true;
      }
      if (el.classList) {
        if (el.classList.contains("renderTarget_pager_button") ||
            el.classList.contains("renderTarget_pager_button_right") ||
            el.classList.contains("renderTarget_pager")) {
          return true;
        }
      }
      if (typeof el.closest === "function") {
        return !!el.closest(
          ".renderTarget_pager, .renderTarget_pager_button, .renderTarget_pager_button_right, [data-meo-weread-pager]"
        );
      }
    } catch (e) {
    }
    return false;
  }

  function buildCSS() {
    /* @scope … to(...)：透明规则不作用在底栏/翻页钮及其后代（含图标 mask / 伪元素） */
    return (
      ":root, html {" +
      "  --meo-tm-color: " + state.color + ";" +
      "  --meo-tm-shadow: " + state.shadow + ";" +
      "}" +
      "@scope (html." + ROOT_CLASS + ") to (" + SCOPE_LIMIT_SELECTOR + ") {" +
      "  :scope, :scope body, div, section, article, main, header, footer, aside, nav," +
      "  span, p, li, ul, ol, dl, dt, dd, td, th, blockquote, pre, code, figure, figcaption," +
      "  form, fieldset, label, table, thead, tbody, tfoot, tr, button, a {" +
      "    background: transparent !important;" +
      "    background-color: transparent !important;" +
      "    background-image: none !important;" +
      "    box-shadow: none !important;" +
      "    border-color: transparent !important;" +
      "  }" +
      "  :scope *::before, :scope *::after {" +
      "    background: transparent !important;" +
      "    background-color: transparent !important;" +
      "    background-image: none !important;" +
      "  }" +
      "  :scope, :scope body," +
      "  :scope body *:not(img):not(picture):not(video):not(canvas):not(svg):not(iframe)," +
      "  :scope body *::before, :scope body *::after {" +
      "    color: var(--meo-tm-color) !important;" +
      "    -webkit-text-fill-color: var(--meo-tm-color) !important;" +
      "    text-shadow: var(--meo-tm-shadow) !important;" +
      "    caret-color: var(--meo-tm-color) !important;" +
      "  }" +
      "}"
    );
  }

  function buildCanvasFilterCSS(canvasFilter) {
    return (
      "@scope (html." + ROOT_CLASS + ") to (" + SCOPE_LIMIT_SELECTOR + ") {" +
      "  canvas { filter: " + (canvasFilter || "none") + " !important; }" +
      "}"
    );
  }

  function shouldSkip(el) {
    if (!el || el.nodeType !== 1 || !el.tagName) {
      return true;
    }
    if (SKIP_TAGS[el.tagName]) {
      return true;
    }
    return isWereadChrome(el);
  }

  function paintElement(el) {
    if (shouldSkip(el)) {
      return;
    }
    try {
      el.style.setProperty("background", "transparent", "important");
      el.style.setProperty("background-color", "transparent", "important");
      el.style.setProperty("background-image", "none", "important");
      el.style.setProperty("color", "var(--meo-tm-color)", "important");
      el.style.setProperty("-webkit-text-fill-color", "var(--meo-tm-color)", "important");
      el.style.setProperty("text-shadow", "var(--meo-tm-shadow)", "important");
      el.style.setProperty("caret-color", "var(--meo-tm-color)", "important");
      el.setAttribute(MARK_ATTR, "1");
    } catch (e) {
    }
  }

  function clearElement(el) {
    if (!el || el.nodeType !== 1 || el.getAttribute(MARK_ATTR) !== "1") {
      return;
    }
    try {
      el.style.removeProperty("background");
      el.style.removeProperty("background-color");
      el.style.removeProperty("background-image");
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

  function restoreReaderControlsSubtree() {
    try {
      var roots = document.querySelectorAll(READER_CONTROLS_SELECTOR);
      for (var i = 0; i < roots.length; i++) {
        var root = roots[i];
        clearElement(root);
        walk(root, clearElement);
      }
    } catch (e) {
    }
  }

  function paintAll() {
    if (!document.documentElement) {
      return;
    }
    walk(document.documentElement, paintElement);
    /* 翻页钮可能先在栏外被染色，再迁入 .readerControls —— 必须清掉残留 inline */
    restoreReaderControlsSubtree();
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

  function ensureStyleTag(id) {
    var style = document.getElementById(id);
    if (!style) {
      style = document.createElement("style");
      style.id = id;
      ensureRoot().appendChild(style);
    }
    return style;
  }

  function updateStyleVariables() {
    var root = document.documentElement;
    if (!root) {
      return;
    }
    root.style.setProperty("--meo-tm-color", state.color);
    root.style.setProperty("--meo-tm-shadow", state.shadow);
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
    state._canvasFilter = canvasFilter;
    var style = ensureStyleTag(STYLE_ID);
    style.textContent = buildCSS();
    if (style.parentNode) {
      style.parentNode.appendChild(style);
    }
    ensureStyleTag(CANVAS_STYLE_ID).textContent = buildCanvasFilterCSS(canvasFilter);
    updateStyleVariables();
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

  function scheduleApplyRepaints() {
    clearRepaintTimers();
    var delays = [50, 150, 400, 1000, 2500];
    for (var i = 0; i < delays.length; i++) {
      (function (delay) {
        var id = setTimeout(function () {
          if (state.enabled) {
            paintAll();
          }
        }, delay);
        repaintTimers.push(id);
      })(delays[i]);
    }
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

  function setTransparentRootClass(active) {
    var root = document.documentElement;
    if (!root) {
      return;
    }
    if (active) {
      root.classList.add(ROOT_CLASS);
    } else {
      root.classList.remove(ROOT_CLASS);
    }
  }

  function setPointerOutsideClass(outside) {
    var root = document.documentElement;
    if (!root) {
      return;
    }
    state.pointerOutside = !!outside;
    if (outside) {
      root.classList.add(POINTER_OUTSIDE_CLASS);
    } else {
      root.classList.remove(POINTER_OUTSIDE_CLASS);
    }
  }

  window.__MeoTransparentMode = {
    __v: 25,
    apply: function (opts) {
      if (!document.documentElement) {
        return;
      }
      rememberNativeCanvasTextIfNeeded();
      uninstallCanvasTextHook();
      commitStyleState(opts);
      state.enabled = true;
      setTransparentRootClass(true);
      writeStylesheet();
      paintAll();
      startObserver();
      scheduleApplyRepaints();
      if (opts && typeof opts === "object" && opts.pointerOutside != null) {
        setPointerOutsideClass(!!opts.pointerOutside);
      }
    },
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
      paintAll();
    },
    setPointerOutside: function (outside) {
      setPointerOutsideClass(!!outside);
    },
    reprotectReaderControls: function () {
      if (!state.enabled) {
        return;
      }
      writeStylesheet();
      paintAll();
    },
    remove: function () {
      state.enabled = false;
      setPointerOutsideClass(false);
      setTransparentRootClass(false);
      clearRepaintTimers();
      stopObserver();
      clearAll();
      var style = document.getElementById(STYLE_ID);
      if (style && style.parentNode) {
        style.parentNode.removeChild(style);
      }
      var canvasStyle = document.getElementById(CANVAS_STYLE_ID);
      if (canvasStyle && canvasStyle.parentNode) {
        canvasStyle.parentNode.removeChild(canvasStyle);
      }
      if (document.documentElement) {
        document.documentElement.style.removeProperty("--meo-tm-color");
        document.documentElement.style.removeProperty("--meo-tm-shadow");
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
