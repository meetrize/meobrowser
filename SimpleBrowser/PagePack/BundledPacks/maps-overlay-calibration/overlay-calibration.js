/**
 * MeoBrowser — 地图/地球叠加校准（共享脚本；由 pack-identity.js 区分 Pack）
 * Maps Pack 1.3.2 · Earth Pack 1.0.10
 * Earth：setView 钉卫星中心 + 地理偏移转屏幕像素 translate，避免放大时偏左再跳右。
 */
(function () {
  'use strict';

  var PACK_META = (typeof window !== 'undefined' && window.__MeoMapAlignPackMeta) || {};
  var PACK_ID = PACK_META.id || 'maps-overlay-calibration';
  var PACK_VERSION = PACK_META.version || '1.3.1';
  var SITE_LOCK = PACK_META.siteLock || null;

  // Earth 独立配置键：避免 Maps 的 selfOverlay=true 拖垮地球页；偏移格子可从 Maps 导入
  var STORAGE_KEY = SITE_LOCK === 'earth'
    ? 'meo.earthOverlayCalibration.v1'
    : 'meo.mapsOverlayCalibration.v1';
  var MAPS_STORAGE_KEY = 'meo.mapsOverlayCalibration.v1';
  var ROOT_ID = 'meo-mapalign-root';
  var HOST_ID = 'meo-mapalign-leaflet-host';
  var CELL_DEG = 0.5;
  var DEFAULT_MAX = 2000;
  var EARTH_TILT_MAX = 2;
  var EARTH_HEADING_MAX = 5;

  if (window.__MeoMapAlign && typeof window.__MeoMapAlign.teardown === 'function') {
    try { window.__MeoMapAlign.teardown(); } catch (e) {}
  }

  var TILE_STYLES = {
    // Google 域名瓦片：在 maps.google.com 页内通常不被 CSP 拦截（CARTO/OSM 常被拦 → 叠加层空白 → 拖滑条无感）
    googleRoads: {
      name: '谷歌路网',
      url: 'https://mt{s}.google.com/vt/lyrs=h&hl=zh-CN&x={x}&y={y}&z={z}',
      subdomains: '0123',
      opacity: 1,
      attribution: 'Google'
    },
    googleHybrid: {
      name: '谷歌混合字',
      url: 'https://mt{s}.google.com/vt/lyrs=y&hl=zh-CN&x={x}&y={y}&z={z}',
      subdomains: '0123',
      opacity: 0.55,
      attribution: 'Google'
    },
    osm: {
      name: 'OSM半透',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: '',
      opacity: 0.45,
      attribution: '&copy; OpenStreetMap'
    },
    cartoLabels: {
      name: 'CARTO标注',
      url: 'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png',
      subdomains: 'abcd',
      opacity: 1,
      attribution: '&copy; OSM &copy; CARTO'
    }
  };

  var state = {
    config: null,
    eastMeters: 0,
    northMeters: 0,
    /** 地理偏移权威：由米在参考纬度换算后固定，缩放时不再随当前 lat 重算 */
    deltaLat: 0,
    deltaLng: 0,
    offsetRefLat: null,
    offsetRefLng: null,
    cellId: null,
    collapsed: true,
    lastDiag: { mode: '', note: '', arch: null },
    pollTimer: null,
    drag: null,
    hudPos: null,
    leafletMap: null,
    tileLayer: null,
    lastViewKey: '',
    overlayReady: false,
    tileLoads: 0,
    tileErrors: 0
  };

  function defaultConfig() {
    return {
      schemaVersion: 2,
      // Earth 默认关闭：打开地球页不自动建 Leaflet，避免极卡；勾选后再加载叠加层
      paused: false,
      selfOverlay: SITE_LOCK !== 'earth',
      tileStyle: 'googleRoads',
      layers: { roads: true, labels: true, pois: true, experimental: false },
      stepMeters: 1,
      maxAbsMeters: DEFAULT_MAX,
      earthZoomBias: 0,
      hud: { collapsed: true, corner: 'bottom-right', offsetX: 0, offsetY: 0 },
      regions: []
    };
  }

  function importMapsRegionsIfNeeded(base) {
    if (SITE_LOCK !== 'earth') return base;
    if (base.regions && base.regions.length) return base;
    try {
      var raw = localStorage.getItem(MAPS_STORAGE_KEY);
      if (!raw) return base;
      var parsed = JSON.parse(raw);
      if (parsed && Array.isArray(parsed.regions) && parsed.regions.length) {
        base.regions = parsed.regions;
      }
    } catch (e) {}
    return base;
  }

  function loadConfig() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return importMapsRegionsIfNeeded(defaultConfig());
      var parsed = JSON.parse(raw);
      if (!parsed || parsed.schemaVersion !== 1) return importMapsRegionsIfNeeded(defaultConfig());
      var base = defaultConfig();
      base.paused = !!parsed.paused;
      if (SITE_LOCK === 'earth') {
        // 仅当用户曾在地球 Pack 里显式打开过才为 true
        base.selfOverlay = parsed.selfOverlay === true;
      } else {
        base.selfOverlay = parsed.selfOverlay !== false;
      }
      if (parsed.tileStyle && TILE_STYLES[parsed.tileStyle]) {
        base.tileStyle = parsed.tileStyle;
      }
      if (base.tileStyle === 'labels' || base.tileStyle === 'roads' || !TILE_STYLES[base.tileStyle]) {
        base.tileStyle = 'googleRoads';
      }
      if (parsed.layers) {
        base.layers.experimental = !!parsed.layers.experimental;
      }
      if (typeof parsed.stepMeters === 'number') base.stepMeters = parsed.stepMeters;
      if (typeof parsed.maxAbsMeters === 'number') base.maxAbsMeters = parsed.maxAbsMeters;
      if (typeof parsed.earthZoomBias === 'number') base.earthZoomBias = parsed.earthZoomBias;
      if (parsed.hud && typeof parsed.hud === 'object') {
        base.hud.collapsed = parsed.hud.collapsed !== false;
        base.hud.corner = parsed.hud.corner || 'bottom-right';
        base.hud.offsetX = parsed.hud.offsetX || 0;
        base.hud.offsetY = parsed.hud.offsetY || 0;
      }
      if (Array.isArray(parsed.regions)) base.regions = parsed.regions;
      return importMapsRegionsIfNeeded(base);
    } catch (e) {
      return importMapsRegionsIfNeeded(defaultConfig());
    }
  }

  function saveConfig() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state.config)); } catch (e) {}
  }

  function clampMeters(v) {
    var max = state.config.maxAbsMeters || DEFAULT_MAX;
    if (v > max) return max;
    if (v < -max) return -max;
    // 保留 0.1m 精度，避免浮点毛刺
    return Math.round(v * 10) / 10;
  }

  function currentStepMeters() {
    var s = state.config.stepMeters;
    if (typeof s !== 'number' || !(s > 0)) return 1;
    return s;
  }

  function snapToStep(v) {
    var step = currentStepMeters();
    return clampMeters(Math.round(v / step) * step);
  }

  function setAxisMeters(axis, value) {
    var v = clampMeters(value);
    if (axis === 'east') state.eastMeters = v;
    else state.northMeters = v;
    rebuildOffsetDeltas();
    persistCurrentRegion();
    syncSliders();
    applyOverlayPixelOffset();
    updateStatusUI();
  }

  function nudgeAxis(axis, dir) {
    var cur = axis === 'east' ? state.eastMeters : state.northMeters;
    setAxisMeters(axis, cur + dir * currentStepMeters());
  }

  function cellIdFor(lat, lng) {
    var la = Math.floor(lat / CELL_DEG) * CELL_DEG;
    var lo = Math.floor(lng / CELL_DEG) * CELL_DEG;
    return 'c:' + la.toFixed(1) + ':' + lo.toFixed(1);
  }

  function findRegion(cellId) {
    var regions = state.config.regions || [];
    for (var i = 0; i < regions.length; i++) {
      if (regions[i].cellId === cellId) return regions[i];
    }
    return null;
  }

  /** 东/北米 → 经纬度差；refLat 固定后 Δ 与 zoom 无关 */
  function metersToLatLngDelta(east, north, lat) {
    var cos = Math.cos((lat || 0) * Math.PI / 180);
    if (Math.abs(cos) < 0.01) cos = cos >= 0 ? 0.01 : -0.01;
    return {
      dLat: (north || 0) / 111320,
      dLng: (east || 0) / (111320 * cos)
    };
  }

  function pickOffsetRefLat(explicitLat) {
    if (typeof explicitLat === 'number' && isFinite(explicitLat)) return explicitLat;
    if (typeof state.offsetRefLat === 'number' && isFinite(state.offsetRefLat)) return state.offsetRefLat;
    try {
      var view = readMapView();
      if (view && typeof view.lat === 'number' && isFinite(view.lat)) return view.lat;
    } catch (e0) {}
    return 0;
  }

  function pickOffsetRefLng(explicitLng) {
    if (typeof explicitLng === 'number' && isFinite(explicitLng)) return explicitLng;
    if (typeof state.offsetRefLng === 'number' && isFinite(state.offsetRefLng)) return state.offsetRefLng;
    try {
      var view = readMapView();
      if (view && typeof view.lng === 'number' && isFinite(view.lng)) return view.lng;
    } catch (e0) {}
    return 0;
  }

  function normalizeLng(lng) {
    var x = lng;
    if (!isFinite(x)) return 0;
    while (x > 180) x -= 360;
    while (x < -180) x += 360;
    return x;
  }

  /**
   * 用当前东/北米在参考点上生成固定 Δlat/Δlng。
   * 之后无论缩放多少，只应用这对 Δ（Earth 再换成当前 zoom 下的屏幕像素）。
   */
  function rebuildOffsetDeltas(refLat, refLng) {
    var lat0 = pickOffsetRefLat(refLat);
    var lng0 = pickOffsetRefLng(refLng);
    state.offsetRefLat = lat0;
    state.offsetRefLng = lng0;
    var d = metersToLatLngDelta(state.eastMeters, state.northMeters, lat0);
    state.deltaLat = d.dLat;
    state.deltaLng = d.dLng;
  }

  function clearOffsetState() {
    state.eastMeters = 0;
    state.northMeters = 0;
    state.deltaLat = 0;
    state.deltaLng = 0;
    state.offsetRefLat = null;
    state.offsetRefLng = null;
  }

  function upsertRegion(cellId, east, north, center) {
    var regions = state.config.regions || [];
    var found = null;
    for (var i = 0; i < regions.length; i++) {
      if (regions[i].cellId === cellId) { found = regions[i]; break; }
    }
    if (!found) {
      found = { cellId: cellId };
      regions.push(found);
      state.config.regions = regions;
    }
    found.eastMeters = east;
    found.northMeters = north;
    found.deltaLat = state.deltaLat;
    found.deltaLng = state.deltaLng;
    found.offsetRefLat = state.offsetRefLat;
    found.offsetRefLng = state.offsetRefLng;
    found.updatedAt = Date.now();
    if (center) found.sampleCenter = { lat: center.lat, lng: center.lng };
    saveConfig();
  }

  var _vpCache = null;
  var _vpCacheAt = 0;

  function isEarthSite() {
    return detectSite() === 'earth';
  }

  /** 取面积最大的可见 canvas 矩形（Earth WebGL 主画布） */
  function findBestCanvasViewport() {
    var best = null;
    var bestArea = 0;
    var nodes = document.querySelectorAll('canvas');
    for (var i = 0; i < nodes.length; i++) {
      var r = nodes[i].getBoundingClientRect();
      if (r.width < 160 || r.height < 160) continue;
      var area = r.width * r.height;
      if (area > bestArea) {
        bestArea = area;
        best = {
          w: r.width,
          h: r.height,
          left: r.left,
          top: r.top,
          source: 'canvas'
        };
      }
    }
    return best;
  }

  /**
   * 视口尺寸。Earth：zoom 优先用主 canvas 高宽（与地球实际成像一致），
   * 叠加层仍像素全屏；用 window 高算 zoom 会偏大、路网显得比底图大。
   */
  function getGoogleViewportCssSize() {
    var ttl = isEarthSite() ? 800 : 300;
    var now = Date.now();
    if (_vpCache && (now - _vpCacheAt) < ttl) return _vpCache;

    if (isEarthSite()) {
      var winW = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1280);
      var winH = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 800);
      try {
        if (window.visualViewport && window.visualViewport.width > 0 && window.visualViewport.height > 0) {
          winW = Math.max(winW, Math.round(window.visualViewport.width));
          winH = Math.max(winH, Math.round(window.visualViewport.height));
        }
      } catch (e0) {}
      var canvasVp = findBestCanvasViewport();
      // canvas 至少占半屏才可信，否则回退 window
      if (canvasVp && canvasVp.w >= winW * 0.45 && canvasVp.h >= winH * 0.45) {
        _vpCache = {
          w: canvasVp.w,
          h: canvasVp.h,
          left: canvasVp.left,
          top: canvasVp.top,
          source: 'earth-canvas'
        };
      } else {
        _vpCache = { w: winW, h: winH, left: 0, top: 0, source: 'window' };
      }
      _vpCacheAt = now;
      return _vpCache;
    }

    var best = findBestCanvasViewport();
    if (best) {
      _vpCache = best;
      _vpCacheAt = now;
      return best;
    }
    var host = document.getElementById('meo-mapalign-leaflet');
    if (host) {
      var hr = host.getBoundingClientRect();
      if (hr.width > 100 && hr.height > 100) {
        _vpCache = { w: hr.width, h: hr.height, left: hr.left, top: hr.top, source: 'host' };
        _vpCacheAt = now;
        return _vpCache;
      }
    }
    _vpCache = {
      w: window.innerWidth || 1280,
      h: window.innerHeight || 800,
      left: 0,
      top: 0,
      source: 'window'
    };
    _vpCacheAt = now;
    return _vpCache;
  }

  /**
   * Earth：强制像素全屏。禁止 height:auto（WebKit 会按内容收缩成「只有上半屏」）。
   */
  function layoutEarthOverlayHost() {
    if (!isEarthSite()) return false;
    var host = document.getElementById(HOST_ID);
    if (!host) return false;
    _vpCache = null;

    var w = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1280);
    var h = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 800);
    // visualViewport 更贴近实际可视区域（地址栏等）
    try {
      if (window.visualViewport && window.visualViewport.width > 0 && window.visualViewport.height > 0) {
        w = Math.max(w, Math.round(window.visualViewport.width));
        h = Math.max(h, Math.round(window.visualViewport.height));
      }
    } catch (e0) {}

    function forceBox(el) {
      if (!el) return;
      el.style.setProperty('position', el === host ? 'fixed' : 'absolute', 'important');
      el.style.setProperty('inset', 'auto', 'important');
      el.style.setProperty('left', '0px', 'important');
      el.style.setProperty('top', '0px', 'important');
      el.style.setProperty('right', 'auto', 'important');
      el.style.setProperty('bottom', 'auto', 'important');
      el.style.setProperty('width', w + 'px', 'important');
      el.style.setProperty('height', h + 'px', 'important');
      el.style.setProperty('max-width', 'none', 'important');
      el.style.setProperty('max-height', 'none', 'important');
      el.style.setProperty('min-width', w + 'px', 'important');
      el.style.setProperty('min-height', h + 'px', 'important');
      el.style.setProperty('margin', '0', 'important');
      el.style.setProperty('padding', '0', 'important');
      el.style.setProperty('box-sizing', 'border-box', 'important');
      el.style.setProperty('overflow', 'hidden', 'important');
    }

    forceBox(host);
    forceBox(document.getElementById('meo-mapalign-leaflet-shift'));
    var leafletEl = document.getElementById('meo-mapalign-leaflet');
    forceBox(leafletEl);
    if (leafletEl) {
      // L.map 会把该类设到同一节点
      leafletEl.style.setProperty('position', 'relative', 'important');
    }

    state._earthLayout = { w: w, h: h, at: Date.now() };

    if (state.leafletMap) {
      try {
        state.leafletMap.invalidateSize({ pan: false, debounceMoveEnd: false });
      } catch (e1) {
        try { state.leafletMap.invalidateSize(false); } catch (e2) {}
      }
    }
    return true;
  }

  /**
   * 垂直地面跨度（米）→ Web Mercator zoom。
   * mpp = (C·cosφ) / (256·2^z)  ⇒  z = log2(C·cosφ·heightPx / (256·meters))
   */
  function metersVerticalToZoom(lat, meters, viewportHeightPx) {
    var h = Math.max(viewportHeightPx || 1, 1);
    var m = Math.max(meters || 1, 1);
    var cosLat = Math.cos((lat || 0) * Math.PI / 180);
    if (cosLat < 0.01) cosLat = 0.01;
    return Math.log2((40075016.686 * cosLat * h) / (256 * m));
  }

  function clampZoom(z) {
    if (!isFinite(z)) return 12;
    if (z < 2) return 2;
    if (z > 22) return 22;
    return z;
  }

  /** 正俯视：相机距离 d + 垂直 FOV → 视口底→顶地面跨度（Maps 几何） */
  function rangeFovToMetersVertical(rangeM, fovY) {
    var d = Math.max(rangeM || 1, 1);
    var fov = (typeof fovY === 'number' && fovY > 1 && fovY < 120) ? fovY : 35;
    return 2 * d * Math.tan((fov * Math.PI / 180) / 2);
  }

  /**
   * Earth Web：`Ny` 按垂直视场角（与相机距离 d）→ 视口垂直地面跨度。
   * 先前按「水平 FOV × 高宽比」会把跨度算小 → zoom 偏高 → 路网显得比地球底图大。
   */
  function earthRangeFovToMetersVertical(rangeM, fovDeg, viewport) {
    var d = Math.max(rangeM || 1, 1);
    var fov = (typeof fovDeg === 'number' && fovDeg > 1 && fovDeg < 120) ? fovDeg : 35;
    return 2 * d * Math.tan((fov * Math.PI / 180) / 2);
  }

  /**
   * Earth Web 专用：相机 → Leaflet zoom（浮点，对齐地球比例）。
   * earthZoomBias 为附加级数（可 0.25 步进微调）；默认 0。
   */
  function earthCameraToZoom(lat, rangeM, fovY, viewport) {
    var h = Math.max((viewport && viewport.h) || window.innerHeight || 800, 1);
    var metersVertical = earthRangeFovToMetersVertical(rangeM, fovY, viewport);
    var z = metersVerticalToZoom(lat, metersVertical, h);
    var bias = 0;
    if (state.config && typeof state.config.earthZoomBias === 'number') {
      bias = state.config.earthZoomBias;
    }
    return Math.round(clampZoom(z + bias) * 100) / 100;
  }

  function normalizeHeadingDeg(h) {
    var x = h || 0;
    while (x > 180) x -= 360;
    while (x < -180) x += 360;
    return x;
  }

  function detectSite() {
    if (SITE_LOCK === 'maps' || SITE_LOCK === 'earth') return SITE_LOCK;
    var h = (location.hostname || '').toLowerCase();
    var p = location.pathname || '';
    if (h === 'earth.google.com' || h.indexOf('.earth.google.') !== -1 || h.indexOf('earth.google.') === 0) {
      return 'earth';
    }
    if (h === 'maps.google.com') return 'maps';
    if (h.indexOf('google.') !== -1 && p.indexOf('/maps') === 0) return 'maps';
    return null;
  }

  function siteHints(site) {
    if (site === 'earth') {
      return 'Earth：偏移按地理 Δ→屏幕像素锚定；放大应保持相对卫星位置。请正俯视。';
    }
    return 'Maps：东/北为地面米，缩放保持地理对齐。请关闭 Labels。';
  }

  function emptyViewFallback(site) {
    return {
      site: site || detectSite() || 'unknown',
      lat: 0,
      lng: 0,
      zoom: 12,
      source: 'fallback',
      unit: 'z',
      metersVertical: null,
      viewport: getGoogleViewportCssSize(),
      heading: 0,
      tilt: 0,
      rangeM: null,
      fovY: null,
      altM: null,
      calibrationSupported: true,
      unsupportedReason: ''
    };
  }

  function parseMapsViewFromURL() {
    try {
      var href = location.href;
      var m = href.match(/@(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*),([0-9]+\.?[0-9]*)([a-z])?/i);
      if (!m) return null;
      var lat = parseFloat(m[1]);
      var lng = parseFloat(m[2]);
      var third = parseFloat(m[3]);
      var unit = (m[4] || 'z').toLowerCase();
      // Earth 串也会被本正则吃到 a/d；Maps adapter 只认 m/z
      if (unit === 'a' || unit === 'd' || unit === 'y' || unit === 'h' || unit === 't' || unit === 'r') {
        return null;
      }
      var vp = getGoogleViewportCssSize();
      var zoom;
      var metersVertical = null;
      if (unit === 'm') {
        metersVertical = Math.max(third, 1);
        zoom = metersVerticalToZoom(lat, metersVertical, vp.h);
      } else {
        zoom = third;
      }
      zoom = clampZoom(zoom);
      if (isFinite(lat) && isFinite(lng) && isFinite(zoom)) {
        return {
          site: 'maps',
          lat: lat,
          lng: lng,
          zoom: zoom,
          source: 'url',
          unit: unit,
          metersVertical: metersVertical,
          viewport: vp,
          heading: 0,
          tilt: 0,
          rangeM: null,
          fovY: null,
          altM: null,
          calibrationSupported: true,
          unsupportedReason: ''
        };
      }
    } catch (e) {}
    return null;
  }

  function parseEarthCameraSuffix(suffix) {
    var out = { alt: null, range: null, fovY: 35, heading: 0, tilt: 0, roll: 0 };
    if (!suffix) return out;
    var parts = suffix.split(',');
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      var mm = p.match(/^(-?[0-9]+\.?[0-9]*)([a-z])$/i);
      if (!mm) continue;
      var val = parseFloat(mm[1]);
      var u = mm[2].toLowerCase();
      if (u === 'a') out.alt = val;
      else if (u === 'd') out.range = val;
      else if (u === 'y') out.fovY = val;
      else if (u === 'h') out.heading = val;
      else if (u === 't') out.tilt = val;
      else if (u === 'r') out.roll = val;
    }
    return out;
  }

  function parseEarthViewFromURL() {
    try {
      var href = location.href;
      // @lat,lng,1963a,4715d,35y,0h,0t,0r
      var m = href.match(/@(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*),([^/?#]*)/);
      if (!m) return null;
      var lat = parseFloat(m[1]);
      var lng = parseFloat(m[2]);
      var cam = parseEarthCameraSuffix(m[3] || '');
      var heading = normalizeHeadingDeg(cam.heading);
      var tilt = cam.tilt || 0;
      var rangeM = cam.range;
      if (rangeM == null || !(rangeM > 0)) {
        // 无 d 时，正俯视可用 a 作近似距离
        if (cam.alt != null && Math.abs(tilt) <= EARTH_TILT_MAX) rangeM = Math.abs(cam.alt);
      }
      var fovY = cam.fovY != null ? cam.fovY : 35;
      var vp = getGoogleViewportCssSize();
      var metersVertical = null;
      var zoom = 12;
      if (rangeM != null && rangeM > 0) {
        // Earth：水平 FOV→垂直跨度→浮点 zoom（对齐地球比例）
        metersVertical = earthRangeFovToMetersVertical(rangeM, fovY, vp);
        zoom = earthCameraToZoom(lat, rangeM, fovY, vp);
      }
      zoom = clampZoom(zoom);
      var supported = Math.abs(tilt) <= EARTH_TILT_MAX && Math.abs(heading) <= EARTH_HEADING_MAX;
      var reason = '';
      if (!supported) {
        reason = '请调到正俯视（tilt≈0、heading≈0）后再校准；当前 3D 视角无法与平面路网对齐。';
      }
      if (isFinite(lat) && isFinite(lng) && isFinite(zoom)) {
        return {
          site: 'earth',
          lat: lat,
          lng: lng,
          zoom: zoom,
          source: 'url',
          unit: 'd',
          metersVertical: metersVertical,
          viewport: vp,
          heading: heading,
          tilt: tilt,
          rangeM: rangeM,
          fovY: fovY,
          altM: cam.alt,
          calibrationSupported: supported,
          unsupportedReason: reason
        };
      }
    } catch (e) {}
    return null;
  }

  function parseMapViewFromURL() {
    var site = detectSite();
    if (site === 'earth') return parseEarthViewFromURL();
    if (site === 'maps') return parseMapsViewFromURL();
    return parseMapsViewFromURL() || parseEarthViewFromURL();
  }

  function readMapView() {
    return parseMapViewFromURL() || emptyViewFallback(detectSite());
  }

  /** E0 探针摘要（写入诊断，便于真机贴回） */
  function collectProbeHints() {
    var canvases = document.querySelectorAll('canvas');
    var sizes = [];
    var i;
    for (i = 0; i < canvases.length && i < 6; i++) {
      var r = canvases[i].getBoundingClientRect();
      sizes.push({ w: Math.round(r.width), h: Math.round(r.height) });
    }
    return {
      site: detectSite(),
      hrefHasAt: location.href.indexOf('@') !== -1,
      canvasCount: canvases.length,
      canvasSizes: sizes,
      leaflet: typeof L !== 'undefined',
      packVersion: PACK_VERSION
    };
  }

  function metersPerPixel(lat, zoom) {
    var z = Math.max(0, Math.min(22, zoom || 12));
    return (156543.03392 * Math.cos((lat || 0) * Math.PI / 180)) / Math.pow(2, z);
  }

  function metersToPixels(east, north, lat, zoom) {
    var mpp = metersPerPixel(lat, zoom);
    if (!mpp || !isFinite(mpp) || mpp <= 0) return { dx: 0, dy: 0, mpp: mpp };
    return { dx: east / mpp, dy: -north / mpp, mpp: mpp };
  }

  /**
   * 方案 A（Maps）：正东/正北 ≡ Leaflet 中心反向移动。
   * Earth 不用此中心偏移（易在换瓦片级时左右跳），见 applyEarthAnchoredOffset。
   */
  function overlayCameraCenter(view) {
    var lat = view.lat;
    var lng = normalizeLng(view.lng);
    if (isEarthSite()) {
      // Earth：相机钉在卫星 look-at，偏移用屏幕像素
      return { lat: lat, lng: lng };
    }
    if (state.config && !state.config.paused && state.config.selfOverlay) {
      if ((!state.deltaLat && !state.deltaLng) && (state.eastMeters || state.northMeters)) {
        rebuildOffsetDeltas(view.lat, view.lng);
      }
      lat = lat - (state.deltaLat || 0);
      lng = normalizeLng(lng - (state.deltaLng || 0));
    }
    return { lat: lat, lng: lng };
  }

  function clearCssShift() {
    var shift = document.getElementById('meo-mapalign-leaflet-shift');
    if (shift) {
      shift.style.transform = 'translate3d(0,0,0)';
      shift.style.webkitTransform = 'translate3d(0,0,0)';
    }
  }

  /**
   * Earth：地图中心始终 = 卫星 look-at；地理 Δ 换成当前 zoom 下的屏幕像素 translate。
   * 避免 setView(偏移中心) 在放大时 pixelOrigin/世界卷绕导致「越来越偏左，然后突然跳到右侧」。
   */
  function applyEarthAnchoredOffset(view, zoom) {
    var shift = document.getElementById('meo-mapalign-leaflet-shift');
    var map = state.leafletMap;
    if (!shift || !map) return;

    if (!state.config || state.config.paused || !state.config.selfOverlay) {
      clearCssShift();
      return;
    }
    if ((!state.deltaLat && !state.deltaLng) && (state.eastMeters || state.northMeters)) {
      rebuildOffsetDeltas(view.lat, view.lng);
    }
    var dLat = state.deltaLat || 0;
    var dLng = state.deltaLng || 0;
    if (!dLat && !dLng) {
      clearCssShift();
      return;
    }

    var lat0 = view.lat;
    var lng0 = normalizeLng(view.lng);
    var lat1 = lat0 - dLat;
    var lng1 = normalizeLng(lng0 - dLng);
    var z = zoom;
    var p0;
    var p1;
    try {
      p0 = map.project(L.latLng(lat0, lng0), z);
      p1 = map.project(L.latLng(lat1, lng1), z);
    } catch (e0) {
      clearCssShift();
      return;
    }
    // 等价于把相机放到 (lat1,lng1)：层平移 (p0-p1)
    var dx = p0.x - p1.x;
    var dy = p0.y - p1.y;
    if (!isFinite(dx) || !isFinite(dy)) {
      clearCssShift();
      return;
    }
    // 亚像素，避免放大过程中累积取整误差
    var t = 'translate3d(' + dx.toFixed(3) + 'px,' + dy.toFixed(3) + 'px,0)';
    shift.style.transform = t;
    shift.style.webkitTransform = t;
  }

  /** 强制整棵叠加树不接收指针（只在创建/换层时调用，勿在每张瓦片上扫 DOM） */
  function forceOverlayPassThrough() {
    var host = document.getElementById(HOST_ID);
    if (!host) return;
    host.style.pointerEvents = 'none';
    var nodes = host.querySelectorAll('*');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].style.pointerEvents = 'none';
    }
  }

  function isSupportedMapSite() {
    return !!detectSite();
  }

  /** @deprecated 使用 isSupportedMapSite */
  function isMapsContext() {
    return isSupportedMapSite();
  }

  function $(sel, root) { return (root || document).querySelector(sel); }

  function ensureLeafletHost() {
    var host = document.getElementById(HOST_ID);
    if (host) {
      host.classList.toggle('meo-ma-earth', isEarthSite());
      if (isEarthSite()) layoutEarthOverlayHost();
      return host;
    }
    host = document.createElement('div');
    host.id = HOST_ID;
    if (isEarthSite()) host.classList.add('meo-ma-earth');
    host.innerHTML =
      '<div id="meo-mapalign-leaflet-shift">' +
      '  <div id="meo-mapalign-leaflet"></div>' +
      '</div>';
    (document.body || document.documentElement).appendChild(host);
    if (isEarthSite()) layoutEarthOverlayHost();
    return host;
  }

  function destroyLeaflet() {
    try {
      if (state.leafletMap) {
        state.leafletMap.remove();
      }
    } catch (e) {}
    state.leafletMap = null;
    state.tileLayer = null;
    state.overlayReady = false;
    var host = document.getElementById(HOST_ID);
    if (host && host.parentNode) host.parentNode.removeChild(host);
  }

  function setTileStyle(styleKey) {
    if (!TILE_STYLES[styleKey]) styleKey = 'googleRoads';
    state.config.tileStyle = styleKey;
    saveConfig();
    if (!state.leafletMap || typeof L === 'undefined') return;
    if (state.tileLayer) {
      try { state.leafletMap.removeLayer(state.tileLayer); } catch (e) {}
      state.tileLayer = null;
    }
    state.tileLoads = 0;
    state.tileErrors = 0;
    var spec = TILE_STYLES[styleKey];
    var earth = isEarthSite();
    var opts = {
      opacity: spec.opacity,
      attribution: spec.attribution,
      maxZoom: earth ? 19 : 22,
      maxNativeZoom: earth ? 18 : 21,
      tileSize: 256,
      zoomOffset: 0,
      detectRetina: false,
      // Earth / Maps 都用标准 XYZ；Earth 禁止世界拷贝，减少放大时左右跳变
      tms: false,
      noWrap: earth,
      bounds: earth ? L.latLngBounds(L.latLng(-85, -180), L.latLng(85, 180)) : undefined,
      updateWhenIdle: false,
      updateWhenZooming: true,
      keepBuffer: earth ? 4 : 2,
      crossOrigin: earth ? false : true,
      className: earth ? 'meo-ma-earth-tiles' : ''
    };
    if (spec.subdomains) opts.subdomains = spec.subdomains;
    if (!earth) delete opts.bounds;
    state.tileLayer = createMeoTileLayer(spec.url, opts);
    state.tileLayer.on('tileload', function () {
      state.tileLoads += 1;
      if (state.tileLoads === 1 || state.tileLoads === 8) updateStatusUI();
    });
    state.tileLayer.on('tileerror', function () {
      state.tileErrors += 1;
      if (state.tileErrors === 2 || state.tileErrors === 8) {
        state.lastDiag = {
          mode: 'tile-error',
          note: '瓦片失败 ' + state.tileErrors + '（Earth 需原生代理）。proxy=' + hasMeoTileProxy() + ' loads=' + state.tileLoads,
          arch: {
            kind: 'moc5-leaflet',
            tileStyle: state.config.tileStyle,
            tileLoads: state.tileLoads,
            tileErrors: state.tileErrors,
            tileProxy: hasMeoTileProxy()
          }
        };
        updateStatusUI();
      }
    });
    state.tileLayer.addTo(state.leafletMap);
    forceOverlayPassThrough();
    updateStyleButtons();
  }

  function hasMeoTileProxy() {
    try {
      return !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoMapAlignTiles);
    } catch (e) {
      return false;
    }
  }

  /** Earth：经原生 NSURLSession 拉瓦片 → data URL，绕过页内 CSP；尺寸固定 256 防错位 */
  function createMeoTileLayer(urlTemplate, opts) {
    if (!isEarthSite() || !hasMeoTileProxy() || typeof L === 'undefined') {
      return L.tileLayer(urlTemplate, opts);
    }
    var tileSize = (opts && opts.tileSize) || 256;
    var ProxyLayer = L.TileLayer.extend({
      createTile: function (coords, done) {
        var tile = document.createElement('img');
        tile.alt = '';
        tile.setAttribute('role', 'presentation');
        tile.setAttribute('width', String(tileSize));
        tile.setAttribute('height', String(tileSize));
        tile.style.width = tileSize + 'px';
        tile.style.height = tileSize + 'px';
        tile.style.position = 'absolute';
        tile.style.maxWidth = 'none';
        tile.style.maxHeight = 'none';
        try { L.DomEvent.disableClickPropagation(tile); } catch (e0) {}
        var url = this.getTileUrl(coords);
        var id = 't' + coords.z + '_' + coords.x + '_' + coords.y + '_' + Math.random().toString(36).slice(2, 9);
        window.__meoTileCbs = window.__meoTileCbs || {};
        var settled = false;
        var finish = function (dataUrl, err) {
          if (settled) return;
          settled = true;
          try { delete window.__meoTileCbs[id]; } catch (e1) {}
          if (dataUrl) {
            tile.onload = function () { done(null, tile); };
            tile.onerror = function () { done(new Error('img-decode'), tile); };
            tile.src = dataUrl;
          } else {
            done(err || new Error('proxy'), tile);
          }
        };
        window.__meoTileCbs[id] = finish;
        try {
          window.webkit.messageHandlers.meoMapAlignTiles.postMessage({ id: id, url: url });
        } catch (e2) {
          finish(null, e2);
          return tile;
        }
        setTimeout(function () {
          if (window.__meoTileCbs && window.__meoTileCbs[id]) finish(null, new Error('timeout'));
        }, 25000);
        return tile;
      }
    });
    return new ProxyLayer(urlTemplate, opts);
  }

  function createLeafletOverlay() {
    if (typeof L === 'undefined') {
      state.lastDiag = {
        mode: 'no-leaflet',
        note: 'Leaflet 未加载（检查页面插件是否包含 leaflet.js）'
      };
      updateStatusUI();
      return false;
    }
    ensureLeafletHost();
    var el = document.getElementById('meo-mapalign-leaflet');
    if (!el) return false;
    if (state.leafletMap) {
      try { state.leafletMap.remove(); } catch (e) {}
      state.leafletMap = null;
    }

    var earth = isEarthSite();
    // Earth：先像素全屏再 L.map；保持 Leaflet 默认 3D transform，否则 setView/偏移不跟手
    if (earth) {
      layoutEarthOverlayHost();
    }

    state.leafletMap = L.map(el, {
      zoomControl: false,
      attributionControl: false,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      tap: false,
      touchZoom: false,
      // Earth：浮点 zoom 对齐地球比例
      zoomSnap: earth ? 0.01 : 0,
      zoomDelta: earth ? 0.25 : 0.1,
      fadeAnimation: false,
      zoomAnimation: false,
      markerZoomAnimation: false,
      preferCanvas: false,
      worldCopyJump: false,
      // Earth：限制在单世界，避免偏移中心触发跨世界跳变
      maxBounds: earth ? L.latLngBounds([-85, -180], [85, 180]) : null,
      maxBoundsViscosity: earth ? 1.0 : 0.0,
      crs: L.CRS.EPSG3857
    });

    if (earth) {
      layoutEarthOverlayHost();
    }
    setTileStyle(state.config.tileStyle || 'googleRoads');
    try { state.leafletMap.invalidateSize(false); } catch (eInv) {}
    clearCssShift();
    forceOverlayPassThrough();
    state.overlayReady = true;
    state.lastViewKey = '';
    syncOverlayFromGoogle(true);
    updateHostVisibility();
    updateSiteChrome();
    var site = detectSite();
    var hostBox = null;
    try {
      var hEl = document.getElementById(HOST_ID);
      if (hEl) {
        var hr = hEl.getBoundingClientRect();
        hostBox = { w: Math.round(hr.width), h: Math.round(hr.height), top: Math.round(hr.top) };
      }
    } catch (eBox) {}
    var mapBox = null;
    try {
      if (state.leafletMap) {
        var sz = state.leafletMap.getSize();
        mapBox = { w: sz.x, h: sz.y };
      }
    } catch (eSz) {}
    state.lastDiag = {
      mode: site === 'earth' ? 'self-overlay-earth' : 'self-overlay',
      note: site === 'earth'
        ? 'Earth 叠加：跟飞+浮点zoom+偏移 ' + (hostBox ? (hostBox.w + 'x' + hostBox.h) : '?')
        : '自建叠加层已启用（相机偏移）。请关闭 Google Labels。',
      arch: {
        kind: 'moc5-leaflet-camera-offset',
        site: site,
        packId: PACK_ID,
        tileStyle: state.config.tileStyle,
        earthLayout: earth ? 'px-fullscreen+follow' : 'fullscreen+transform',
        hostBox: hostBox,
        mapBox: mapBox,
        win: { w: window.innerWidth, h: window.innerHeight }
      }
    };
    updateStatusUI();
    if (earth) {
      var bump = function () {
        _vpCache = null;
        layoutEarthOverlayHost();
        try { if (state.leafletMap) state.leafletMap.invalidateSize(false); } catch (e2) {}
        state.lastViewKey = '';
        syncOverlayFromGoogle(true);
        forceOverlayPassThrough();
        updateStatusUI();
      };
      setTimeout(bump, 50);
      setTimeout(bump, 400);
    }
    try { console.info('[MeoMapAlign] self-overlay ready', site, state.config.tileStyle); } catch (e2) {}
    return true;
  }

  function syncOverlayFromGoogle(force) {
    if (!state.leafletMap || !state.config.selfOverlay) return;
    var view = readMapView();
    if (view.source === 'fallback' && !force) return;

    var earth = isEarthSite();
    var z = earth
      ? Math.round(clampZoom(view.zoom) * 100) / 100
      : Math.round(clampZoom(view.zoom) * 1000) / 1000;
    var cam = overlayCameraCenter(view);
    var vpH = (view.viewport && view.viewport.h) || 0;
    // Earth：跟飞需要足够细的 lat/lng；偏移用 0.1m
    var key = earth
      ? (view.site + ',' + cam.lat.toFixed(6) + ',' + cam.lng.toFixed(6) + ',z' + z.toFixed(2) +
        ',b' + (state.config.earthZoomBias != null ? state.config.earthZoomBias : 0) +
        ',dLat' + (state.deltaLat || 0).toFixed(8) +
        ',dLng' + (state.deltaLng || 0).toFixed(8) +
        ',p' + (state.config.paused ? 1 : 0) + ',ok' + (view.calibrationSupported === false ? 0 : 1))
      : ((view.site || '') + ',' +
        cam.lat.toFixed(6) + ',' + cam.lng.toFixed(6) + ',' + z.toFixed(3) +
        ',h' + Math.round(vpH) +
        ',dLat' + (state.deltaLat || 0).toFixed(8) +
        ',dLng' + (state.deltaLng || 0).toFixed(8) +
        ',p' + (state.config.paused ? 1 : 0) +
        ',ok' + (view.calibrationSupported === false ? 0 : 1));

    if (view.calibrationSupported === false) {
      state.lastDiag = {
        mode: 'earth-3d-unsupported',
        note: view.unsupportedReason || '3D 视角不支持校准同步',
        arch: { site: view.site, tilt: view.tilt, heading: view.heading }
      };
      updateSiteChrome();
      if (!force) return;
    }

    if (!force && key === state.lastViewKey) return;
    state.lastViewKey = key;
    try {
      if (earth) {
        // 中心钉卫星 look-at；偏移用屏幕像素（与 zoom 成比例，换瓦片级不跳左右）
        state.leafletMap.setView([view.lat, normalizeLng(view.lng)], z, {
          animate: false,
          reset: true
        });
        applyEarthAnchoredOffset(view, z);
      } else {
        clearCssShift();
        state.leafletMap.setView([cam.lat, cam.lng], z, { animate: false, reset: false });
      }
    } catch (e) {}
    if (view.calibrationSupported !== false && state.lastDiag && state.lastDiag.mode === 'earth-3d-unsupported') {
      state.lastDiag = {
        mode: view.site === 'earth' ? 'self-overlay-earth' : 'self-overlay',
        note: siteHints(view.site),
        arch: { site: view.site, tileStyle: state.config.tileStyle }
      };
    }
  }

  /** 滑条/配置变更：刷新相机偏移 */
  function applyOverlayPixelOffset() {
    state.lastViewKey = '';
    syncOverlayFromGoogle(true);
  }

  function updateHostVisibility() {
    var host = document.getElementById(HOST_ID);
    if (!host) return;
    // 暂停只取消偏移，不隐藏叠加层
    var show = !!state.config.selfOverlay;
    host.classList.toggle('meo-ma-hidden', !show);
  }

  function loadRegionForView() {
    var view = readMapView();
    var cid = cellIdFor(view.lat, view.lng);
    state.cellId = cid;
    var reg = findRegion(cid);
    if (reg) {
      state.eastMeters = reg.eastMeters || 0;
      state.northMeters = reg.northMeters || 0;
      if (typeof reg.deltaLat === 'number' && typeof reg.deltaLng === 'number') {
        state.deltaLat = reg.deltaLat;
        state.deltaLng = reg.deltaLng;
        state.offsetRefLat = typeof reg.offsetRefLat === 'number'
          ? reg.offsetRefLat
          : ((reg.sampleCenter && reg.sampleCenter.lat) || view.lat);
        state.offsetRefLng = typeof reg.offsetRefLng === 'number'
          ? reg.offsetRefLng
          : ((reg.sampleCenter && reg.sampleCenter.lng) || view.lng);
      } else {
        // 旧数据只有米：用采样中心冻结成 Δ，之后缩放不再变
        var refLat = (reg.sampleCenter && reg.sampleCenter.lat) || view.lat;
        var refLng = (reg.sampleCenter && reg.sampleCenter.lng) || view.lng;
        rebuildOffsetDeltas(refLat, refLng);
        // 写回 Δ，下次直接用
        upsertRegion(cid, state.eastMeters, state.northMeters, view);
      }
    } else {
      clearOffsetState();
    }
    syncSliders();
    applyOverlayPixelOffset();
    updateStatusUI();
  }

  function persistCurrentRegion() {
    var view = readMapView();
    var cid = cellIdFor(view.lat, view.lng);
    state.cellId = cid;
    if (state.offsetRefLat == null) rebuildOffsetDeltas(view.lat, view.lng);
    upsertRegion(cid, state.eastMeters, state.northMeters, view);
  }

  function ensureHUD() {
    if (document.getElementById(ROOT_ID)) return;
    var root = document.createElement('div');
    root.id = ROOT_ID;
    root.innerHTML =
      '<button type="button" class="meo-ma-fab" title="地图叠加校准 (Alt+Shift+M)">校准</button>' +
      '<div class="meo-ma-panel" hidden>' +
      '  <div class="meo-ma-titlebar">' +
      '    <span class="meo-ma-grow">地图叠加校准</span>' +
      '    <button type="button" class="meo-ma-icon-btn meo-ma-collapse" title="收起">–</button>' +
      '  </div>' +
      '  <div class="meo-ma-status meo-ma-muted" data-role="status"></div>' +
      '  <div class="meo-ma-banner meo-ma-warn" data-role="banner" hidden></div>' +
      '  <div class="meo-ma-layers">' +
      '    <label><input type="checkbox" data-opt="selfOverlay" checked>自建叠加层</label>' +
      '  </div>' +
      '  <div class="meo-ma-styles" data-role="styles"></div>' +
      '  <div class="meo-ma-row">' +
      '    <label>东</label>' +
      '    <button type="button" class="meo-ma-nudge" data-nudge="east" data-dir="-1" title="减少一档">−</button>' +
      '    <input type="range" data-axis="east" min="-2000" max="2000" step="0.5" value="0">' +
      '    <button type="button" class="meo-ma-nudge" data-nudge="east" data-dir="1" title="增加一档">+</button>' +
      '    <span class="meo-ma-val" data-val="east">0 m</span>' +
      '  </div>' +
      '  <div class="meo-ma-row">' +
      '    <label>北</label>' +
      '    <button type="button" class="meo-ma-nudge" data-nudge="north" data-dir="-1" title="减少一档">−</button>' +
      '    <input type="range" data-axis="north" min="-2000" max="2000" step="0.5" value="0">' +
      '    <button type="button" class="meo-ma-nudge" data-nudge="north" data-dir="1" title="增加一档">+</button>' +
      '    <span class="meo-ma-val" data-val="north">0 m</span>' +
      '  </div>' +
      '  <div class="meo-ma-steps-label meo-ma-muted">微调步进</div>' +
      '  <div class="meo-ma-steps" data-role="steps"></div>' +
      '  <div class="meo-ma-earth-zoom" data-role="earth-zoom" hidden>' +
      '    <span class="meo-ma-muted">Earth 比例</span>' +
      '    <button type="button" class="meo-ma-btn" data-earth-bias="-0.25" title="路网缩小（更远）">Z−</button>' +
      '    <button type="button" class="meo-ma-btn" data-earth-bias="0.25" title="路网放大（更近）">Z+</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="earth-bias-reset" title="重置比例微调">复位</button>' +
      '    <span class="meo-ma-val" data-role="earth-bias-val">bias 0</span>' +
      '  </div>' +
      '  <div class="meo-ma-actions">' +
      '    <button type="button" class="meo-ma-btn" data-act="pause">暂停偏移</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="reset">重置本区</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="resync">同步视图</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="copydiag">复制诊断</button>' +
      '  </div>' +
      '  <div class="meo-ma-footer meo-ma-warn" data-role="footer">东/北为地面米（地理固定）；缩放后仍钉在同一卫星位置。</div>' +
      '</div>';

    (document.body || document.documentElement).appendChild(root);

    var fab = root.querySelector('.meo-ma-fab');
    var panel = root.querySelector('.meo-ma-panel');
    fab.style.cssText = 'position:fixed;right:16px;bottom:88px;z-index:2147483647;' +
      'min-width:56px;height:34px;padding:0 14px;border:0;border-radius:17px;' +
      'background:rgba(28,28,30,0.92);color:#f5f5f7;font:600 13px/34px -apple-system,sans-serif;' +
      'cursor:pointer;box-shadow:0 4px 16px rgba(0,0,0,0.35);pointer-events:auto;';
    panel.style.cssText = 'position:fixed;right:16px;bottom:88px;z-index:2147483647;' +
      'width:360px;max-width:calc(100vw - 24px);padding:10px 12px 12px;border-radius:12px;' +
      'background:rgba(245,245,247,0.96);box-shadow:0 8px 28px rgba(0,0,0,0.28);' +
      'border:1px solid rgba(0,0,0,0.08);pointer-events:auto;color:#1d1d1f;' +
      'font:12px/1.35 -apple-system,sans-serif;';

    fab.addEventListener('click', function () { setCollapsed(false); });
    root.querySelector('.meo-ma-collapse').addEventListener('click', function () { setCollapsed(true); });

    var stylesHost = root.querySelector('[data-role="styles"]');
    Object.keys(TILE_STYLES).forEach(function (key) {
      var lab = document.createElement('label');
      lab.innerHTML = '<input type="radio" name="meo-ma-style" data-style="' + key + '"> ' + TILE_STYLES[key].name;
      stylesHost.appendChild(lab);
      lab.querySelector('input').addEventListener('change', function () {
        if (this.checked) setTileStyle(key);
      });
    });

    var stepsHost = root.querySelector('[data-role="steps"]');
    [0.5, 1, 5, 10, 50].forEach(function (s) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'meo-ma-btn';
      b.textContent = s < 1 ? '0.5 m' : (s + ' m');
      b.setAttribute('data-step', String(s));
      b.addEventListener('click', function () {
        state.config.stepMeters = s;
        saveConfig();
        updateStepButtons();
        syncSliders();
      });
      stepsHost.appendChild(b);
    });

    var earthZoomRow = root.querySelector('[data-role="earth-zoom"]');
    if (earthZoomRow) {
      earthZoomRow.hidden = SITE_LOCK !== 'earth' && detectSite() !== 'earth';
      earthZoomRow.querySelectorAll('[data-earth-bias]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var delta = parseFloat(btn.getAttribute('data-earth-bias'));
          if (!isFinite(delta) || delta === 0) return;
          var cur = typeof state.config.earthZoomBias === 'number' ? state.config.earthZoomBias : 0;
          var next = Math.round((cur + delta) * 100) / 100;
          if (next > 2) next = 2;
          if (next < -4) next = -4;
          state.config.earthZoomBias = next;
          saveConfig();
          state.lastViewKey = '';
          syncOverlayFromGoogle(true);
          updateEarthBiasLabel();
          updateStatusUI();
        });
      });
      updateEarthBiasLabel();
    }

    root.querySelectorAll('[data-nudge]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var axis = btn.getAttribute('data-nudge');
        var dir = parseInt(btn.getAttribute('data-dir'), 10) || 0;
        if (!axis || !dir) return;
        nudgeAxis(axis, dir);
      });
    });

    root.querySelectorAll('input[data-axis]').forEach(function (input) {
      input.addEventListener('input', function () {
        var axis = input.getAttribute('data-axis');
        setAxisMeters(axis, parseFloat(input.value) || 0);
      });
    });

    var selfCb = root.querySelector('input[data-opt="selfOverlay"]');
    selfCb.checked = SITE_LOCK === 'earth' ? !!state.config.selfOverlay : (state.config.selfOverlay !== false);
    selfCb.addEventListener('change', function () {
      state.config.selfOverlay = selfCb.checked;
      saveConfig();
      if (selfCb.checked) {
        if (typeof L === 'undefined' && window.leaflet) {
          try { window.L = window.leaflet; } catch (eL) {}
        }
        // Earth：每次勾选重建，避免半初始化空白层
        if (isEarthSite() && state.leafletMap) {
          try { state.leafletMap.remove(); } catch (eRm) {}
          state.leafletMap = null;
          state.tileLayer = null;
          state.overlayReady = false;
        }
        if (!state.leafletMap) createLeafletOverlay();
        else syncOverlayFromGoogle(true);
        if (isEarthSite() && !hasMeoTileProxy()) {
          state.lastDiag = {
            mode: 'no-tile-proxy',
            note: '原生瓦片代理未注入，请完全退出并重启 MeoBrowser 后再试。',
            arch: { packId: PACK_ID }
          };
        }
      } else {
        destroyLeaflet();
      }
      // 切换叠加后重设轮询频率（Earth 开启时 350ms 跟飞）
      startPolling();
      updateHostVisibility();
      applyOverlayPixelOffset();
      updateStatusUI();
    });

    root.querySelectorAll('[data-act]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var act = btn.getAttribute('data-act');
        if (act === 'pause') {
          state.config.paused = !state.config.paused;
          saveConfig();
          updateHostVisibility();
          applyOverlayPixelOffset();
          updateStatusUI();
        } else if (act === 'reset') {
          clearOffsetState();
          persistCurrentRegion();
          syncSliders();
          applyOverlayPixelOffset();
          updateStatusUI();
        } else if (act === 'resync') {
          syncOverlayFromGoogle(true);
          if (state.leafletMap) state.leafletMap.invalidateSize(false);
        } else if (act === 'copydiag') {
          copyDiagnostics();
        } else if (act === 'earth-bias-reset') {
          state.config.earthZoomBias = 0;
          saveConfig();
          state.lastViewKey = '';
          syncOverlayFromGoogle(true);
          updateEarthBiasLabel();
          updateStatusUI();
        }
      });
    });

    var title = root.querySelector('.meo-ma-titlebar');
    title.addEventListener('mousedown', function (ev) {
      if (ev.button !== 0) return;
      var rect = panel.getBoundingClientRect();
      state.drag = { startX: ev.clientX, startY: ev.clientY, origLeft: rect.left, origTop: rect.top };
      ev.preventDefault();
    });
    window.addEventListener('mousemove', onDragMove);
    window.addEventListener('mouseup', onDragEnd);

    setCollapsed(state.config.hud.collapsed !== false);
    applyHudPosition();
    updateStepButtons();
    updateStyleButtons();
    syncSliders();
    updateStatusUI();
  }

  function onDragMove(ev) {
    if (!state.drag) return;
    var panel = document.querySelector('#' + ROOT_ID + ' .meo-ma-panel');
    if (!panel) return;
    var left = state.drag.origLeft + (ev.clientX - state.drag.startX);
    var top = state.drag.origTop + (ev.clientY - state.drag.startY);
    panel.style.right = 'auto';
    panel.style.bottom = 'auto';
    panel.style.left = Math.max(8, left) + 'px';
    panel.style.top = Math.max(8, top) + 'px';
    state.hudPos = { left: Math.max(8, left), top: Math.max(8, top) };
  }

  function onDragEnd() {
    if (!state.drag) return;
    state.drag = null;
    if (state.hudPos) {
      state.config.hud.offsetX = state.hudPos.left;
      state.config.hud.offsetY = state.hudPos.top;
      state.config.hud.corner = 'custom';
      saveConfig();
    }
  }

  function applyHudPosition() {
    var panel = document.querySelector('#' + ROOT_ID + ' .meo-ma-panel');
    if (!panel || state.config.hud.corner !== 'custom' || !state.config.hud.offsetX) return;
    panel.style.right = 'auto';
    panel.style.bottom = 'auto';
    panel.style.left = state.config.hud.offsetX + 'px';
    panel.style.top = state.config.hud.offsetY + 'px';
  }

  function setCollapsed(collapsed) {
    state.collapsed = collapsed;
    state.config.hud.collapsed = collapsed;
    saveConfig();
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    root.querySelector('.meo-ma-fab').hidden = !collapsed;
    root.querySelector('.meo-ma-panel').hidden = collapsed;
  }

  function syncSliders() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var max = state.config.maxAbsMeters || DEFAULT_MAX;
    var step = currentStepMeters();
    // range 最小刻度取 0.5，避免步进 5/10 时拖不动细调；细调用 ±
    var rangeStep = step <= 0.5 ? 0.5 : (step < 1 ? step : 0.5);
    root.querySelectorAll('input[data-axis]').forEach(function (input) {
      input.min = String(-max);
      input.max = String(max);
      input.step = String(rangeStep);
      input.value = String(input.getAttribute('data-axis') === 'east' ? state.eastMeters : state.northMeters);
    });
    var ve = root.querySelector('[data-val="east"]');
    var vn = root.querySelector('[data-val="north"]');
    if (ve) ve.textContent = formatMeters(state.eastMeters);
    if (vn) vn.textContent = formatMeters(state.northMeters);
  }

  function formatMeters(v) {
    var n = Math.round((v || 0) * 10) / 10;
    var abs = Math.abs(n);
    var body = (Math.abs(abs - Math.round(abs)) < 0.05) ? String(Math.round(n)) : n.toFixed(1);
    if (n > 0) body = '+' + body;
    return body + ' m';
  }

  function updateStepButtons() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var step = currentStepMeters();
    root.querySelectorAll('[data-step]').forEach(function (b) {
      var s = parseFloat(b.getAttribute('data-step'));
      b.classList.toggle('active', Math.abs(s - step) < 0.001);
    });
  }

  function updateEarthBiasLabel() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var row = root.querySelector('[data-role="earth-zoom"]');
    if (row) row.hidden = !isEarthSite();
    var el = root.querySelector('[data-role="earth-bias-val"]');
    if (!el) return;
    var b = typeof state.config.earthZoomBias === 'number' ? state.config.earthZoomBias : 0;
    var t = (Math.round(b * 100) / 100).toFixed(2);
    el.textContent = 'bias ' + (b > 0 ? '+' : '') + t;
  }

  function updateStyleButtons() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var cur = state.config.tileStyle || 'googleRoads';
    root.querySelectorAll('input[data-style]').forEach(function (r) {
      r.checked = r.getAttribute('data-style') === cur;
    });
  }

  function updateSiteChrome() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var site = detectSite() || 'maps';
    var view = readMapView();
    var title = root.querySelector('.meo-ma-grow');
    if (title) {
      title.textContent = site === 'earth' ? '地图叠加校准 · Earth' : '地图叠加校准 · Maps';
    }
    var footer = root.querySelector('[data-role="footer"]');
    if (footer) footer.textContent = siteHints(site);
    var banner = root.querySelector('[data-role="banner"]');
    if (banner) {
      if (view.calibrationSupported === false && view.unsupportedReason) {
        banner.hidden = false;
        banner.textContent = view.unsupportedReason;
      } else {
        banner.hidden = true;
        banner.textContent = '';
      }
    }
    updateEarthBiasLabel();
  }

  function updateStatusUI() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    updateSiteChrome();
    var el = root.querySelector('[data-role="status"]');
    if (!el) return;
    var view = readMapView();
    var px = metersToPixels(state.eastMeters, state.northMeters, view.lat, view.zoom);
    var parts = [];
    if (view.calibrationSupported === false) {
      parts.push('已暂停跟飞 · 请正俯视');
      el.className = 'meo-ma-status meo-ma-warn';
    } else if (!state.config.selfOverlay) {
      parts.push('自建层已关');
      el.className = 'meo-ma-status meo-ma-warn';
    } else if (state.config.paused) {
      parts.push('已暂停');
      el.className = 'meo-ma-status meo-ma-warn';
    } else if (!state.overlayReady && typeof L === 'undefined') {
      parts.push('Leaflet 未加载');
      el.className = 'meo-ma-status meo-ma-error';
    } else if (!state.overlayReady) {
      parts.push('叠加层启动中…');
      el.className = 'meo-ma-status meo-ma-muted';
    } else if (state.tileErrors > 0 && state.tileLoads === 0) {
      parts.push('瓦片全失败 · 换「谷歌路网」或查网络');
      el.className = 'meo-ma-status meo-ma-error';
    } else if (state.eastMeters === 0 && state.northMeters === 0) {
      parts.push('本区未校准 · 拖滑条 / ± 微调');
      el.className = 'meo-ma-status meo-ma-muted';
    } else {
      parts.push('本区已校准·地理固定');
      el.className = 'meo-ma-status meo-ma-muted';
    }
    parts.push(view.site || detectSite() || '—');
    parts.push('格 ' + (state.cellId || '—'));
    parts.push(state.config.tileStyle || 'googleRoads');
    parts.push('z≈' + (Math.round(view.zoom * 100) / 100));
    if (view.metersVertical) parts.push(Math.round(view.metersVertical) + 'm↕');
    if (view.site === 'earth' && view.rangeM != null) parts.push('d=' + Math.round(view.rangeM));
    if (view.site === 'earth') parts.push('t=' + Math.round((view.tilt || 0) * 10) / 10);
    parts.push('瓦片 ' + state.tileLoads + '/' + (state.tileLoads + state.tileErrors));
    parts.push('≈ ' + Math.round(Math.hypot(px.dx, px.dy)) + ' px');
    el.textContent = parts.join(' · ');

    var pauseBtn = root.querySelector('[data-act="pause"]');
    if (pauseBtn) pauseBtn.textContent = state.config.paused ? '恢复偏移' : '暂停偏移';
    syncSliders();
  }

  function getDiagnostics() {
    var view = readMapView();
    var cam = overlayCameraCenter(view);
    var hostRect = null;
    var mapSize = null;
    try {
      var hEl = document.getElementById(HOST_ID);
      if (hEl) {
        var hr = hEl.getBoundingClientRect();
        hostRect = {
          w: Math.round(hr.width),
          h: Math.round(hr.height),
          left: Math.round(hr.left),
          top: Math.round(hr.top)
        };
      }
    } catch (e0) {}
    try {
      if (state.leafletMap) {
        var sz = state.leafletMap.getSize();
        mapSize = { w: sz.x, h: sz.y };
      }
    } catch (e1) {}
    return {
      version: PACK_VERSION,
      packId: PACK_ID,
      siteLock: SITE_LOCK,
      mode: view.site === 'earth' ? 'moc-e-earth' : 'moc5-camera-offset',
      site: view.site || detectSite(),
      href: location.href,
      view: view,
      overlayCenter: cam,
      cellId: state.cellId,
      eastMeters: state.eastMeters,
      northMeters: state.northMeters,
      deltaLat: state.deltaLat,
      deltaLng: state.deltaLng,
      offsetRefLat: state.offsetRefLat,
      paused: state.config.paused,
      selfOverlay: state.config.selfOverlay,
      tileStyle: state.config.tileStyle,
      leaflet: typeof L !== 'undefined',
      overlayReady: state.overlayReady,
      tileLoads: state.tileLoads,
      tileErrors: state.tileErrors,
      tileProxy: hasMeoTileProxy(),
      earthZoomBias: state.config.earthZoomBias,
      earthLayout: state._earthLayout || null,
      hostRect: hostRect,
      mapSize: mapSize,
      windowSize: { w: window.innerWidth, h: window.innerHeight },
      leafletZoom: state.leafletMap ? state.leafletMap.getZoom() : null,
      leafletCenter: state.leafletMap ? state.leafletMap.getCenter() : null,
      pixelOffset: metersToPixels(state.eastMeters, state.northMeters, view.lat, view.zoom),
      probe: collectProbeHints(),
      diag: state.lastDiag,
      regionCount: (state.config.regions || []).length
    };
  }

  function copyDiagnostics() {
    var text = JSON.stringify(getDiagnostics(), null, 2);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () { window.prompt('诊断 JSON', text); });
    } else {
      window.prompt('诊断 JSON', text);
    }
  }

  function onKeydown(ev) {
    if (ev.altKey && ev.shiftKey && (ev.key === 'M' || ev.key === 'm')) {
      ev.preventDefault();
      setCollapsed(!state.collapsed);
    }
  }

  function onMaybeNavigate() {
    if (!document.getElementById(ROOT_ID)) ensureHUD();
    var view = readMapView();
    var cid = cellIdFor(view.lat, view.lng);
    if (cid !== state.cellId) loadRegionForView();
    // Earth 未开叠加时不 sync、少刷 UI，避免空转拖垮页面
    if (isEarthSite() && !state.config.selfOverlay) {
      return;
    }
    syncOverlayFromGoogle(false);
    updateStatusUI();
  }

  function startPolling() {
    stopPolling();
    // Earth 开启叠加时要紧跟 URL；未开启则保持低频以免卡顿
    var ms;
    if (isEarthSite()) {
      ms = state.config.selfOverlay ? 350 : 2000;
    } else {
      ms = 500;
    }
    state.pollTimer = window.setInterval(function () {
      if (document.visibilityState === 'hidden') return;
      onMaybeNavigate();
    }, ms);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = null;
    }
  }

  var _origPushState = null;
  var _origReplaceState = null;
  function installHistoryHooks() {
    if (state._histHooked) return;
    state._histHooked = true;
    try {
      _origPushState = history.pushState;
      _origReplaceState = history.replaceState;
      if (typeof _origPushState === 'function') {
        history.pushState = function () {
          var ret = _origPushState.apply(this, arguments);
          try { onMaybeNavigate(); } catch (e0) {}
          return ret;
        };
      }
      if (typeof _origReplaceState === 'function') {
        history.replaceState = function () {
          var ret = _origReplaceState.apply(this, arguments);
          try { onMaybeNavigate(); } catch (e1) {}
          return ret;
        };
      }
    } catch (e2) {}
    window.addEventListener('hashchange', onMaybeNavigate);
  }

  function uninstallHistoryHooks() {
    if (!state._histHooked) return;
    state._histHooked = false;
    try {
      if (_origPushState) history.pushState = _origPushState;
      if (_origReplaceState) history.replaceState = _origReplaceState;
    } catch (e0) {}
    _origPushState = null;
    _origReplaceState = null;
    window.removeEventListener('hashchange', onMaybeNavigate);
  }

  function teardown() {
    stopPolling();
    uninstallHistoryHooks();
    window.removeEventListener('keydown', onKeydown, true);
    window.removeEventListener('popstate', onMaybeNavigate);
    window.removeEventListener('resize', onViewportResize);
    window.removeEventListener('mousemove', onDragMove);
    window.removeEventListener('mouseup', onDragEnd);
    destroyLeaflet();
    var root = document.getElementById(ROOT_ID);
    if (root && root.parentNode) root.parentNode.removeChild(root);
    try { delete window.__MeoMapAlign; } catch (e) { window.__MeoMapAlign = undefined; }
    try { delete window.MeoMapAlign; } catch (e2) { window.MeoMapAlign = undefined; }
  }

  var resizeTimer = null;
  function onViewportResize() {
    if (resizeTimer) clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      resizeTimer = null;
      if (isEarthSite() && state.config.selfOverlay) {
        layoutEarthOverlayHost();
      }
      state.lastViewKey = '';
      syncOverlayFromGoogle(true);
      updateStatusUI();
    }, 120);
  }

  function boot() {
    if (!isSupportedMapSite()) {
      try { console.info('[MeoMapAlign] skip: not maps/earth', location.href); } catch (e) {}
      return;
    }
    state.config = loadConfig();
    ensureHUD();
    updateSiteChrome();
    loadRegionForView();

    var tries = 0;
    function tryOverlay() {
      tries++;
      if (typeof L === 'undefined' && typeof window !== 'undefined' && window.leaflet) {
        try { window.L = window.leaflet; } catch (e) {}
      }
      if (typeof L !== 'undefined') {
        if (state.config.selfOverlay) createLeafletOverlay();
        return;
      }
      if (tries < 40) {
        setTimeout(tryOverlay, 250);
      } else {
        state.lastDiag = {
          mode: 'no-leaflet',
          note: 'Leaflet 未挂到 window.L（若仍失败请重启并确认 Pack ' + PACK_VERSION + '）'
        };
        updateStatusUI();
        try { console.warn('[MeoMapAlign] Leaflet missing', typeof define, typeof module); } catch (e) {}
      }
    }
    tryOverlay();

    window.addEventListener('keydown', onKeydown, true);
    window.addEventListener('popstate', onMaybeNavigate);
    window.addEventListener('resize', onViewportResize);
    installHistoryHooks();
    startPolling();
    try {
      console.info('[MeoMapAlign] HUD ready', PACK_VERSION, detectSite(), collectProbeHints());
    } catch (e3) {}
  }

  window.MeoMapAlign = window.__MeoMapAlign = {
    toggleHUD: function () { setCollapsed(!state.collapsed); },
    setOffsetMeters: function (east, north) {
      state.eastMeters = clampMeters(east || 0);
      state.northMeters = clampMeters(north || 0);
      persistCurrentRegion();
      syncSliders();
      applyOverlayPixelOffset();
      updateStatusUI();
    },
    pause: function (p) {
      state.config.paused = !!p;
      saveConfig();
      updateHostVisibility();
      applyOverlayPixelOffset();
      updateStatusUI();
    },
    resetCurrentRegion: function () {
      state.eastMeters = 0;
      state.northMeters = 0;
      persistCurrentRegion();
      syncSliders();
      applyOverlayPixelOffset();
      updateStatusUI();
    },
    getDiagnostics: getDiagnostics,
    teardown: teardown
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
