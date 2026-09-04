/**
 * MeoBrowser — 地图叠加校准 v1.2.5 (MOC-5)
 * 自建 Leaflet 透明路网/标注层，与 Google Maps 相机同步；东/北米偏移写入 Leaflet 中心（非 CSS 平移），视口始终铺满瓦片。
 * URL 中 Xm = 视口垂直地面跨度（米），换算 zoom 必须乘上地图画布 CSS 高度。
 * 请在 Google Maps「图层」中关闭 Labels，避免双份标注。
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'meo.mapsOverlayCalibration.v1';
  var ROOT_ID = 'meo-mapalign-root';
  var HOST_ID = 'meo-mapalign-leaflet-host';
  var CELL_DEG = 0.5;
  var DEFAULT_MAX = 2000;

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
      schemaVersion: 1,
      paused: false,
      selfOverlay: true,
      tileStyle: 'googleRoads',
      layers: { roads: true, labels: true, pois: true, experimental: false },
      stepMeters: 1,
      maxAbsMeters: DEFAULT_MAX,
      hud: { collapsed: true, corner: 'bottom-right', offsetX: 0, offsetY: 0 },
      regions: []
    };
  }

  function loadConfig() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return defaultConfig();
      var parsed = JSON.parse(raw);
      if (!parsed || parsed.schemaVersion !== 1) return defaultConfig();
      var base = defaultConfig();
      base.paused = !!parsed.paused;
      base.selfOverlay = parsed.selfOverlay !== false;
      if (parsed.tileStyle && TILE_STYLES[parsed.tileStyle]) {
        base.tileStyle = parsed.tileStyle;
      }
      // 旧版 CARTO labels/roads 在 Google 页常被 CSP 拦成空白层 → 强制迁到谷歌路网瓦片
      if (base.tileStyle === 'labels' || base.tileStyle === 'roads' || !TILE_STYLES[base.tileStyle]) {
        base.tileStyle = 'googleRoads';
      }
      if (parsed.layers) {
        base.layers.experimental = !!parsed.layers.experimental;
      }
      if (typeof parsed.stepMeters === 'number') base.stepMeters = parsed.stepMeters;
      if (typeof parsed.maxAbsMeters === 'number') base.maxAbsMeters = parsed.maxAbsMeters;
      if (parsed.hud && typeof parsed.hud === 'object') {
        base.hud.collapsed = parsed.hud.collapsed !== false;
        base.hud.corner = parsed.hud.corner || 'bottom-right';
        base.hud.offsetX = parsed.hud.offsetX || 0;
        base.hud.offsetY = parsed.hud.offsetY || 0;
      }
      if (Array.isArray(parsed.regions)) base.regions = parsed.regions;
      return base;
    } catch (e) {
      return defaultConfig();
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
    found.updatedAt = Date.now();
    if (center) found.sampleCenter = { lat: center.lat, lng: center.lng };
    saveConfig();
  }

  /** Google 地图主画布 CSS 尺寸（用于 Xm→zoom；与 Leaflet 同用 CSS 像素） */
  function getGoogleViewportCssSize() {
    var best = null;
    var bestArea = 0;
    var nodes = document.querySelectorAll('canvas');
    for (var i = 0; i < nodes.length; i++) {
      var r = nodes[i].getBoundingClientRect();
      if (r.width < 160 || r.height < 160) continue;
      var area = r.width * r.height;
      if (area > bestArea) {
        bestArea = area;
        best = { w: r.width, h: r.height };
      }
    }
    if (best) return best;
    var host = document.getElementById('meo-mapalign-leaflet');
    if (host) {
      var hr = host.getBoundingClientRect();
      if (hr.width > 100 && hr.height > 100) return { w: hr.width, h: hr.height };
    }
    return {
      w: window.innerWidth || 1280,
      h: window.innerHeight || 800
    };
  }

  /**
   * Google URL 的 Xm = 地图视口「底→顶」地面跨度（米），不是整圈周长。
   * mpp = (C·cosφ) / (256·2^z)  ⇒  z = log2(C·cosφ·heightPx / (256·meters))
   * 若漏乘 heightPx（等价 height=256），zoom 会偏低约 log2(h/256)，路网偏小。
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

  function parseMapViewFromURL() {
    try {
      var href = location.href;
      var m = href.match(/@(-?[0-9]+\.?[0-9]*),(-?[0-9]+\.?[0-9]*),([0-9]+\.?[0-9]*)([a-z])?/i);
      if (!m) return null;
      var lat = parseFloat(m[1]);
      var lng = parseFloat(m[2]);
      var third = parseFloat(m[3]);
      var unit = (m[4] || 'z').toLowerCase();
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
          lat: lat,
          lng: lng,
          zoom: zoom,
          source: 'url',
          unit: unit,
          metersVertical: metersVertical,
          viewport: vp
        };
      }
    } catch (e) {}
    return null;
  }

  function readMapView() {
    return parseMapViewFromURL() || { lat: 0, lng: 0, zoom: 12, source: 'fallback', unit: 'z', metersVertical: null, viewport: getGoogleViewportCssSize() };
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

  /** 东/北米 → 经纬度差（近似，本地校准足够） */
  function metersToLatLngDelta(east, north, lat) {
    var cos = Math.cos((lat || 0) * Math.PI / 180);
    if (Math.abs(cos) < 0.01) cos = cos >= 0 ? 0.01 : -0.01;
    return {
      dLat: (north || 0) / 111320,
      dLng: (east || 0) / (111320 * cos)
    };
  }

  /**
   * 方案 A：正东/正北视觉偏移 ≡ Leaflet 中心反向移动。
   * 相对 Google 卫星中心，路网看起来东/北移，但瓦片仍铺满整个视口（无底边缺口）。
   */
  function overlayCameraCenter(view) {
    var lat = view.lat;
    var lng = view.lng;
    if (state.config && !state.config.paused && state.config.selfOverlay) {
      var d = metersToLatLngDelta(state.eastMeters, state.northMeters, lat);
      lat = lat - d.dLat;
      lng = lng - d.dLng;
    }
    return { lat: lat, lng: lng };
  }

  function clearCssShift() {
    var shift = document.getElementById('meo-mapalign-leaflet-shift');
    if (shift) shift.style.transform = 'translate3d(0,0,0)';
  }

  function isMapsContext() {
    var h = (location.hostname || '').toLowerCase();
    var p = location.pathname || '';
    if (h === 'maps.google.com') return true;
    if (h.indexOf('google.') !== -1 && p.indexOf('/maps') === 0) return true;
    return false;
  }

  function $(sel, root) { return (root || document).querySelector(sel); }

  function ensureLeafletHost() {
    var host = document.getElementById(HOST_ID);
    if (host) return host;
    host = document.createElement('div');
    host.id = HOST_ID;
    host.innerHTML =
      '<div id="meo-mapalign-leaflet-shift">' +
      '  <div id="meo-mapalign-leaflet"></div>' +
      '</div>';
    (document.body || document.documentElement).appendChild(host);
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
    var opts = {
      opacity: spec.opacity,
      attribution: spec.attribution,
      maxZoom: 22,
      maxNativeZoom: 21,
      // 避免跨域污染；Google 瓦片不需要 canvas 读像素
      crossOrigin: true
    };
    if (spec.subdomains) opts.subdomains = spec.subdomains;
    state.tileLayer = L.tileLayer(spec.url, opts);
    state.tileLayer.on('tileload', function () {
      state.tileLoads += 1;
    });
    state.tileLayer.on('tileerror', function () {
      state.tileErrors += 1;
      if (state.tileErrors === 3 || state.tileErrors === 12) {
        state.lastDiag = {
          mode: 'tile-error',
          note: '瓦片加载失败 ' + state.tileErrors + ' 次（可能 CSP/网络）。优先用「谷歌路网」。',
          arch: { kind: 'moc5-leaflet', tileStyle: state.config.tileStyle, tileLoads: state.tileLoads, tileErrors: state.tileErrors }
        };
        updateStatusUI();
      }
    });
    state.tileLayer.addTo(state.leafletMap);
    updateStyleButtons();
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
      zoomSnap: 0,
      zoomDelta: 0.1,
      fadeAnimation: false,
      zoomAnimation: false,
      markerZoomAnimation: false
    });

    setTileStyle(state.config.tileStyle || 'googleRoads');
    try { state.leafletMap.invalidateSize(false); } catch (eInv) {}
    clearCssShift();
    state.overlayReady = true;
    state.lastViewKey = '';
    syncOverlayFromGoogle(true);
    updateHostVisibility();
    state.lastDiag = {
      mode: 'self-overlay',
      note: '自建叠加层已启用（相机偏移，无裁切空白）。请关闭 Google Labels。',
      arch: { kind: 'moc5-leaflet-camera-offset', tileStyle: state.config.tileStyle }
    };
    updateStatusUI();
    try { console.info('[MeoMapAlign] self-overlay ready', state.config.tileStyle); } catch (e2) {}
    return true;
  }

  function syncOverlayFromGoogle(force) {
    if (!state.leafletMap || !state.config.selfOverlay) return;
    var view = readMapView();
    if (view.source === 'fallback' && !force) return;
    var z = Math.round(clampZoom(view.zoom) * 1000) / 1000;
    var cam = overlayCameraCenter(view);
    var vpH = (view.viewport && view.viewport.h) || 0;
    var key =
      cam.lat.toFixed(6) + ',' + cam.lng.toFixed(6) + ',' + z.toFixed(3) +
      ',h' + Math.round(vpH) +
      ',e' + Math.round(state.eastMeters) +
      ',n' + Math.round(state.northMeters) +
      ',p' + (state.config.paused ? 1 : 0);
    if (!force && key === state.lastViewKey) return;
    state.lastViewKey = key;
    clearCssShift();
    try {
      state.leafletMap.invalidateSize(false);
      state.leafletMap.setView([cam.lat, cam.lng], z, { animate: false });
    } catch (e) {}
  }

  /** 滑条/配置变更：刷新相机偏移 */
  function applyOverlayPixelOffset() {
    syncOverlayFromGoogle(true);
  }

  function updateHostVisibility() {
    var host = document.getElementById(HOST_ID);
    if (!host) return;
    var show = state.config.selfOverlay && !state.config.paused;
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
    } else {
      state.eastMeters = 0;
      state.northMeters = 0;
    }
    syncSliders();
    applyOverlayPixelOffset();
    updateStatusUI();
  }

  function persistCurrentRegion() {
    var view = readMapView();
    var cid = cellIdFor(view.lat, view.lng);
    state.cellId = cid;
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
      '  <div class="meo-ma-actions">' +
      '    <button type="button" class="meo-ma-btn" data-act="pause">暂停偏移</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="reset">重置本区</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="resync">同步视图</button>' +
      '    <button type="button" class="meo-ma-btn" data-act="copydiag">复制诊断</button>' +
      '  </div>' +
      '  <div class="meo-ma-footer meo-ma-warn">偏移写入自建层相机（视口铺满瓦片），不移动 Google 卫星。请关闭 Labels。</div>' +
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
    selfCb.checked = state.config.selfOverlay !== false;
    selfCb.addEventListener('change', function () {
      state.config.selfOverlay = selfCb.checked;
      saveConfig();
      if (selfCb.checked) {
        if (!state.leafletMap) createLeafletOverlay();
        else syncOverlayFromGoogle(true);
      }
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
          state.eastMeters = 0;
          state.northMeters = 0;
          persistCurrentRegion();
          syncSliders();
          applyOverlayPixelOffset();
          updateStatusUI();
        } else if (act === 'resync') {
          syncOverlayFromGoogle(true);
          if (state.leafletMap) state.leafletMap.invalidateSize(false);
        } else if (act === 'copydiag') {
          copyDiagnostics();
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

  function updateStyleButtons() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var cur = state.config.tileStyle || 'googleRoads';
    root.querySelectorAll('input[data-style]').forEach(function (r) {
      r.checked = r.getAttribute('data-style') === cur;
    });
  }

  function updateStatusUI() {
    var root = document.getElementById(ROOT_ID);
    if (!root) return;
    var el = root.querySelector('[data-role="status"]');
    if (!el) return;
    var view = readMapView();
    var px = metersToPixels(state.eastMeters, state.northMeters, view.lat, view.zoom);
    var parts = [];
    if (!state.config.selfOverlay) {
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
      parts.push('本区未校准 · 拖滑条只移自建层');
      el.className = 'meo-ma-status meo-ma-muted';
    } else {
      parts.push('本区已校准');
      el.className = 'meo-ma-status meo-ma-muted';
    }
    parts.push('格 ' + (state.cellId || '—'));
    parts.push(state.config.tileStyle || 'googleRoads');
    parts.push('z≈' + (Math.round(view.zoom * 100) / 100));
    if (view.metersVertical) parts.push(Math.round(view.metersVertical) + 'm↕');
    parts.push('瓦片 ' + state.tileLoads + '/' + (state.tileLoads + state.tileErrors));
    parts.push('≈ ' + Math.round(Math.hypot(px.dx, px.dy)) + ' px');
    if (state.lastDiag && state.lastDiag.note) parts.push(state.lastDiag.note.split('。')[0]);
    el.textContent = parts.join(' · ');

    var pauseBtn = root.querySelector('[data-act="pause"]');
    if (pauseBtn) pauseBtn.textContent = state.config.paused ? '恢复偏移' : '暂停偏移';
    syncSliders();
  }

  function getDiagnostics() {
    var view = readMapView();
    var cam = overlayCameraCenter(view);
    return {
      version: '1.2.5',
      mode: 'moc5-camera-offset',
      href: location.href,
      view: view,
      overlayCenter: cam,
      cellId: state.cellId,
      eastMeters: state.eastMeters,
      northMeters: state.northMeters,
      paused: state.config.paused,
      selfOverlay: state.config.selfOverlay,
      tileStyle: state.config.tileStyle,
      leaflet: typeof L !== 'undefined',
      overlayReady: state.overlayReady,
      tileLoads: state.tileLoads,
      tileErrors: state.tileErrors,
      leafletZoom: state.leafletMap ? state.leafletMap.getZoom() : null,
      leafletCenter: state.leafletMap ? state.leafletMap.getCenter() : null,
      pixelOffset: metersToPixels(state.eastMeters, state.northMeters, view.lat, view.zoom),
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
    syncOverlayFromGoogle(false);
    updateStatusUI();
  }

  function startPolling() {
    stopPolling();
    state.pollTimer = window.setInterval(function () {
      if (document.visibilityState === 'hidden') return;
      onMaybeNavigate();
    }, 500);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = null;
    }
  }

  function teardown() {
    stopPolling();
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
      state.lastViewKey = '';
      syncOverlayFromGoogle(true);
      updateStatusUI();
    }, 120);
  }

  function boot() {
    if (!isMapsContext()) {
      try { console.info('[MeoMapAlign] skip: not maps', location.href); } catch (e) {}
      return;
    }
    state.config = loadConfig();
    ensureHUD();
    loadRegionForView();

    var tries = 0;
    // Wait longer; also accept window.leaflet as L
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
          note: 'Leaflet 未挂到 window.L（若仍失败请重启并确认 Pack 1.2.5）'
        };
        updateStatusUI();
        try { console.warn('[MeoMapAlign] Leaflet missing', typeof define, typeof module); } catch (e) {}
      }
    }
    tryOverlay();

    window.addEventListener('keydown', onKeydown, true);
    window.addEventListener('popstate', onMaybeNavigate);
    window.addEventListener('resize', onViewportResize);
    startPolling();
    try { console.info('[MeoMapAlign] HUD ready (MOC-5 1.2.5 nudge)'); } catch (e3) {}
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
