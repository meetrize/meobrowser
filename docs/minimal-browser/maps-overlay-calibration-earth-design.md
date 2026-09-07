# 地图叠加校准 — Google Earth Web 扩展方案与开发计划

> 基于已落地的 Maps MOC-5（自建 Leaflet 叠加 + 相机偏移）。  
> 触发 URL 示例：  
> `https://earth.google.com/web/search/云南省大理/@25.93560168,100.1204795,1963.95a,4715.59d,35y,0h,0t,0r/...`  
> 状态：**1.3.0 已接入代码（E1+E2）；E0 真机探针用诊断 `probe` 字段验收** · 2026-09-04  
> 关联：[maps-overlay-calibration-design.md](maps-overlay-calibration-design.md) · [maps-overlay-calibration-development-plan.md](maps-overlay-calibration-development-plan.md)

---

## 0. 一句话结论

| 问题 | 定稿 |
|------|------|
| 能不能做 | **能试**。Earth Web 为地球投影，平面 Web Mercator 叠加只能近似；须解决 **pointer-events 抢拖拽** 与 **全局 CSS 弄碎瓦片** |
| 一个插件还是两个 | **两个 Pack（已定稿修订）**：`maps-overlay-calibration` 只打 Maps；`earth-overlay-calibration` 只打 Earth，互不影响启停与改版 |
| 何时可用 | **仅推荐俯视**（`tilt≈0`，`heading≈0`） |
| 偏移记忆 | 两 Pack **共用** `localStorage` 键与地理格子 |
| 不做 | 保证倾斜 3D 透视对齐；保证地球边缘与平面瓦片严丝合缝 |

---

## 1. 需求与场景

用户在 Google Earth Web 看云南大理一带卫星影像时，地名/路网（若开启）与影像错位，希望与 Maps 相同：

1. 页内 HUD 调东/北偏移（滑条 + ± 微调）  
2. 只移动自建路网/标注，卫星不动  
3. 区域记忆、暂停、重置、诊断  

示例相机串：

```text
@25.93560168,100.1204795,1963.94951112a,4715.59050465d,35y,0h,0t,0r
```

| 后缀 | 含义 | 对本方案 |
|------|------|----------|
| `lat,lng` | 视点目标 | Leaflet 中心基准 |
| `…a` | 目标海拔（米，ASL） | 俯视时次要；倾斜时与 `d` 共同定义相机 |
| `…d` | 相机到目标距离（米） | **换算地面跨度 / zoom 的主输入** |
| `…y` | 视场角 FOV（度） | 与 `d` 一起算垂直地面跨度 |
| `…h` | 航向 heading | ≠0 时 2D 叠加难对齐 → 降级 |
| `…t` | 俯仰 tilt（0=正俯视） | ≠0 时 **不承诺对齐** |
| `…r` | 滚转 | 通常 0 |

---

## 2. 产品形态：一个 Pack vs 两个 Pack

### 2.1 对比

| 维度 | **A. 单 Pack 多站点（推荐）** | B. 两个 Pack |
|------|------------------------------|--------------|
| 用户心智 | 「地图叠加校准」一处开关 | 侧栏两个插件，易漏开 |
| 偏移数据 | 同格子 Maps↔Earth 共用 | 需同步或用户重复校准 |
| Leaflet 体积 | 一份进 Bundle | 翻倍或抽公共包（更复杂） |
| HUD / 步进 / 诊断 | 一套 UI | 两套易漂移 |
| 改版风险隔离 | Adapter 隔离即可 | 物理隔离略强，收益不大 |
| 匹配与注入 | `matches` 加 Earth 规则 | 两个 manifest |
| 版本发布 | 一次升版两边受益 | 双轨发版 |

### 2.2 定稿修订：**方案 B — 两个 Pack**

> 2026-09-04 真机反馈：单 Pack 注入 Earth 后出现 **路网瓦片断裂混乱**、**整页无法拖拽**。根因包括 leaflet.css 的 `pointer-events: auto` 抢事件，以及 Earth 页全局样式弄碎 `img.leaflet-tile`。为避免 Maps 回归风险，改为物理隔离。

| Pack id | 站点 | 版本线 |
|---------|------|--------|
| `maps-overlay-calibration` | Google Maps | **1.3.2**（地理固定 Δlat/Δlng） |
| `earth-overlay-calibration` | Google Earth Web | **1.0.10**（屏幕像素锚定，放大不左右跳） |

共享：同一套 `overlay-calibration.js`（`pack-identity.js` 区分）；偏移配置键分离（Earth=`meo.earthOverlayCalibration.v1`）。  
隔离：各自 manifest / 启停 / Seed 安装。

> 2026-09-04：**1.0.10** 放大偏左再跳右：Earth 改为 setView(卫星中心)+地理Δ→屏幕像素 translate；noWrap。Maps 仍用相机中心偏移。

```text
BundledPacks/
  maps-overlay-calibration/   # Maps only
  earth-overlay-calibration/  # Earth only（构建时拷贝共享 js/css/leaflet）
```

---

## 3. 技术可行性

### 3.1 与 Maps 相同的结论

| 点 | Earth Web | 策略 |
|----|-----------|------|
| 卫星 + 标注 | 多为同一 WebGL 场景 | **自建 Leaflet 叠加**，提示关闭 Earth 地名/路网层（若 UI 有） |
| CSP | `earth.google.com` 可能拦第三方瓦片 | 默认继续 **`mt*.google.com` 路网瓦片**（同源系，Maps 已验证） |
| 交互 | 全屏拖拽/滚轮 | overlay `pointer-events: none` |
| PagePack 注入 | 非 challenge 页应可注入 | 确认 `BrowserRiskHostPolicy` 不误伤；必要时补 Earth 白名单笔记 |

### 3.2 Earth 特有难点

| 风险 | 等级 | 处理 |
|------|------|------|
| **倾斜 / 透视**（`t≠0`） | 高 | `\|tilt\| > 阈值`（建议 2°）→ 暂停相机同步，HUD 黄字：「请先调到正俯视」 |
| **航向非北**（`h≠0`） | 中 | `\|heading\| > 閾值` → 同上或仅提示；首版可与 tilt 一并降级 |
| **`d`≠ Maps 的 `m`** | 中 | 用 FOV 几何换算垂直地面跨度，再复用现有 `metersVerticalToZoom` |
| URL 飞行中高频变化 | 低 | 保持 300–500ms poll；`lastViewKey` 去抖 |
| 登录墙 / 搜索壳 | 低 | `matches` 盯 `/web/`；无 `@` 时不启叠加 |
| 高 DPI / 多 canvas | 低 | 仍取最大 canvas 的 CSS 尺寸作 viewport |

### 3.3 俯视时 `d` + `y` → zoom（首版公式）

正俯视（`tilt≈0`）时，相机距目标约 `d`，垂直视场 `fovY`：

```text
metersVertical ≈ 2 * d * tan(fovY_rad / 2)
zoom = log2( C · cos(lat) · heightPx / (256 · metersVertical) )
```

与 Maps 已落地的「垂直跨度 → zoom」同一套后半段；仅 **跨度来源** 不同。

验收：同一地点、相近比例尺下，Earth 与 Maps 上路网线宽视觉接近（允许 ±0.3 zoom 内人工微调后再记文档常数）。

### 3.4 偏移方式

继续 **方案 A 相机偏移**（Pack 1.2.4+）：

```text
leafletCenter = earthTarget − Δ(east, north)
```

禁止再对整层做 CSS translate，避免底边缺口。

---

## 4. 架构设计

### 4.1 站点探测

```javascript
function detectSite() {
  var h = location.hostname.toLowerCase();
  var p = location.pathname || '';
  if (h === 'earth.google.com' || h.endsWith('.earth.google.com')) return 'earth';
  if (h.indexOf('google.') !== -1 && p.indexOf('/maps') === 0) return 'maps';
  if (h === 'maps.google.com') return 'maps';
  return null;
}
```

### 4.2 Adapter 接口（约定）

| 方法 | 职责 |
|------|------|
| `parseView(href)` | → `{ lat, lng, zoom, heading, tilt, raw, source }` |
| `isCalibrationSupported(view)` | tilt/heading 是否在安全窗 |
| `unsupportedReason(view)` | HUD 文案 |
| `siteHints()` | 页脚提示（关 Labels / 关 Earth 图层名） |

Maps / Earth 各自实现；核心只依赖该接口。

### 4.3 配置与存储

| Key | 说明 |
|-----|------|
| `meo.mapsOverlayCalibration.v1` | **保持不变**；`regions[]` 按 `cellId` 存东/北米 |
| 可选 `sitePrefs.earth` | 仅存 Earth 专用 UI 偏好（若有），不拆偏移 |

同一 `c:25.5:100.0` 在 Maps 校准后，Earth 打开同区应直接可用。

### 4.4 manifest `matches` 增补

```json
"*://earth.google.com/web*",
"*://earth.google.com/web/*",
"*://*.earth.google.com/web*"
```

保留现有 Maps 规则。

### 4.5 HUD 差异（尽量共用）

| 元素 | Maps | Earth |
|------|-------|-------|
| 标题 | 地图叠加校准 | 同左，状态条可标 `Earth` |
| 步进 / ± | 相同 | 相同 |
| 3D 降级条 | 无 | tilt/heading 超限时显示 |
| 页脚 | 关 Maps Labels | 「建议正俯视；关闭 Earth 地名/边界层（若有）」 |

---

## 5. 非目标与边界

- 不支持倾斜浏览时的像素级贴合。  
- 不替代 Earth 的 3D 建筑物/街景。  
- 不保证点击 Earth 原生 POI 与视觉层同点。  
- 不实现 KML/项目图层编辑。  
- ToS：个人校准用途；默认用 Google 公开瓦片端点，与 Maps 包一致。

---

## 6. 开发计划（MOC-E）

总原则：**先探针 → 再 Adapter → 再体验**；不复制第二份 Leaflet。

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| **MOC-E0** | Earth 探针 | 0.5–1 日 | CSP、canvas、图层 UI、URL 更新节奏笔记 |
| **MOC-E1** | Adapter + match | 0.5–1 日 | `earthAdapter`、manifest、site 探测 |
| **MOC-E2** | 俯视同步可用 | 1–1.5 日 | `d+y→zoom`、相机偏移、3D 降级 |
| **MOC-E3** | 打磨与文档 | 0.5 日 | HUD 文案、诊断字段、设计/计划回写、真机验收 |
| **MOC-E4** | （可选）增强 | 另开 | heading 补偿旋转叠加；Earth 专用路网样式 |

建议版本线：在现有 **1.2.5** 上继续 **1.3.0**（Earth 首版）。

---

### Phase MOC-E0：探针与可行性记录

**目标**：用给定大理 URL 在 MeoBrowser 确认注入与瓦片策略。

- [x] **E0.1–E0.6** 代码侧：诊断 JSON 含 `probe`（canvas 尺寸、site、Leaflet）；真机打开大理链接后点「复制诊断」验收 CSP/瓦片

**验收**：诊断 `version=1.3.0`、`site=earth`、`probe.canvasCount≥1`；瓦片 `tileLoads>0` 则探针通过。

---

### Phase MOC-E1：单 Pack 接入 Earth

- [x] **E1.1** Maps / Earth URL 解析分流（`detectSite` + `parseMaps*` / `parseEarth*`）
- [x] **E1.2** manifest 增加 Earth `matches`
- [x] **E1.3** `isSupportedMapSite`（maps|earth）
- [x] **E1.4** Seed 升版 **1.3.0**

**验收**：Earth 页出现「校准」；Maps 回归。

---

### Phase MOC-E2：俯视同步 + 降级

- [x] **E2.1** 解析 `@lat,lng,Aa,Dd,Yy,Hh,Tt,Rr`
- [x] **E2.2** `rangeFovToMetersVertical(d, fovY)` + 复用 zoom 公式
- [x] **E2.3** 相机偏移（与 Maps 相同东/北米）
- [x] **E2.4** `|t|>2°` 或 `|h|>5°`：banner + poll 暂停跟飞；force 仍 setView
- [x] **E2.5** 诊断含 `site` / `tilt` / `heading` / `rangeM` / `fovY` / `probe`

**验收**（大理示例、正俯视）：见下文测试表；真机待用户确认。

---

### Phase MOC-E3：打磨与文档

- [x] **E3.1** HUD 标题/页脚区分 Maps vs Earth；3D banner
- [x] **E3.2** 本文件与主开发计划回写 1.3.0
- [ ] **E3.3** roadmap 一行（可选）
- [ ] **E3.4** 真机回归：Maps + Earth 大理链接 

---

### Phase MOC-E4（可选）

- [ ] Leaflet 容器按 heading 做 CSS `rotate`（仅 heading≠0、tilt≈0）  
- [ ] 更密的 Earth 专用标注源  
- [ ] 原生 `WKWebView` 透明叠加（仅当页内 CSP 彻底失败）  

---

## 7. 测试计划（摘要）

| # | 用例 | 期望 |
|---|------|------|
| T1 | 打开本文首段大理 Earth URL | HUD 出现；`site=earth` |
| T2 | 正俯视拖东/北 | 卫星不动，路网动；无底边空白 |
| T3 | 缩放（改 `d`） | 比例大致跟手 |
| T4 | 同格子先在 Maps 校准再开 Earth | 偏移自动带上 |
| T5 | tilt=45 | 降级提示，不跟飞乱飘 |
| T6 | Maps 云南卫星页 | 与 1.2.5 行为一致 |
| T7 | 诊断 JSON | `version ≥ 1.3.0`，含 tilt/range |

---

## 8. 风险与回滚

| 风险 | 缓解 |
|------|------|
| Earth 改 URL 格式 | Adapter 单测 + 诊断贴 URL；失败只影响 Earth |
| CSP 升级 | 先 Google 瓦片；不行再原生代理 |
| 单 Pack 回归 Maps | E1/E3 强制 Maps 回归清单 |
| 用户在 3D 模式抱怨不准 | 文案写死「仅正俯视」 |

回滚：Seed 保留版本比较；可将 Earth `matches` 临时从 manifest 去掉发 1.2.x hotfix。

---

## 9. 建议实施顺序（给你拍板用）

1. **采纳单 Pack + Adapter**（本文定稿）  
2. 先做 **MOC-E0** 半日探针（用你给的大理链接）  
3. 再 **E1→E2** 打出 1.3.0  
4. E4 仅在正俯视体验满意后考虑  

若 E0 发现页内完全无法加载任何瓦片，再单开「原生透明 WKWebView 叠加」子项目，仍建议挂在同一产品名下，而不是第二个用户可见插件。
