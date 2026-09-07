# 地图叠加校准（Maps Overlay Calibration）— 设计方案

> 目标：在 MeoBrowser 中为 **Google Maps（及同类 Web 地图）** 提供「卫星底图 ↔ 路网 / POI / 标注」**手动视觉对齐**能力：用户可按方向与距离偏移矢量叠加层，使标注落回正确位置。  
> 状态：**设计定稿 + 机制结论修订** · 2026-09-04（Earth 扩展见 [maps-overlay-calibration-earth-design.md](maps-overlay-calibration-earth-design.md)）  
> 开发计划：[maps-overlay-calibration-development-plan.md](maps-overlay-calibration-development-plan.md)  
> 关联：[page-pack-design.md](page-pack-design.md) · [page-pack-development-plan.md](page-pack-development-plan.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [anti-bot-session-design.md](anti-bot-session-design.md) · [design.md](design.md)

---

## 0. 一句话结论

| 问题 | 定稿 |
|------|------|
| 做什么 | **站点级「地图叠加校准」**：页内 HUD 调东/北偏移；按区域记忆；缩放后按米换算像素 |
| 产品形态 | **内置种子 Page Pack**（`maps-overlay-calibration`）+ 页内校准 UI；**不**进系统设置 |
| 设置入口 | **页内 HUD 为主**；页面插件侧栏管启停 / 编辑；可选 Maps 域名工具栏角标 |
| 能否实现（修订） | **在现行 google.com/maps 卫星页上，用 CSS 单独平移「路网相对卫星」通常不可行**：二者多在同一 WebGL 场景一次画完。「实验层」平移的是整幅场景（像整张图在挪），缩小后露出黑底，易被误认为黑屏 |
| 可行下一路径 | **自建透明路网/标注叠加层**（藏原生 Labels 或盖住标注），与底图同步 pan/zoom，只偏移自建层；或拦截可分离的标注瓦片（若仍存在 DOM/`img` 叠加） |
| 首版范围 | 探测架构 + DOM/分离瓦片 Best-effort；区域记忆 HUD |
| 不做 | 自研完整替代 Google；保证 WebGL 内核改 matrix 长期稳定 |

---

## 0.1 渲染机制结论（2026-09 实测反馈）

用户在 `@…,3579m`（约 1 km 比例尺）勾选「实验层」拖滑条时：**卫星与道路一同平移**。由此可判定：

1. 当前消费级 Maps 卫星+标注 **不是**「底层卫星 DOM + 上层路网 DOM」可分别 `transform` 的结构。  
2. 「黑屏」更可能是整幅 WebGL 画布被移出视口后露出页面黑底，而非 WebGL 绘制崩溃。  
3. 不勾选实验层时无反应，是因为安全模式故意不碰 canvas，而 DOM POI 在该视图几乎不存在或不足以产生体感。

详见 **§7.0 Google Maps 页面加载与图层原理**。

---

## 1. 需求理解

### 1.1 用户原始诉求

打开类似：

`https://www.google.com/maps/@25.69,100.17,2972m/data=!3m1!1e3`

卫星图与路网、POI、地名标注整体错位。希望有一个插件或功能，**手动**把「上面所有标注」向某一方向偏移若干距离，直到与卫星图对齐。

### 1.2 问题根因（产品语境）

| 根因 | 说明 | 对本方案的含义 |
|------|------|----------------|
| **坐标系不一致** | 国内常见：卫星瓦片偏 WGS-84，路网/POI 偏 GCJ-02（或反向） | 局部近似为**近似常值东/北偏移（米）**；跨省不可一套参数 |
| **瓦片配准误差** | 供应商正射/配准本身有偏差 | 同样可用区域偏移近似 |
| **缩放效应** | 固定像素偏移在换 zoom 后立刻漂 | **必须以米（或经纬度 Δ）为权威单位**，运行时换算 px |
| **Web 地图实现** | Google Maps Web 大量 Canvas / WebGL / 混淆 DOM | 只能「找层并平移」；易随改版失效 |

### 1.3 成功标准（用户可感知）

| 级别 | 标准 | 首版是否必须 |
|------|------|----------------|
| **S0 可见** | 某一固定 zoom 下，滑条能明显移动路网/标注相对卫星的位置 | **必须** |
| **S1 可用** | 保存后刷新 / 重进同区域仍恢复；换 zoom 大致仍对齐 | **必须** |
| **S2 舒适** | 多区域多套参数；HUD 不挡操作；一键重置 / 暂停 | 应做 |
| **S3 精确** | 点击、测距、导航折线与视觉层完全同投影 | **非目标**（见 §3.3） |

---

## 2. 相对原始设想的优化

| # | 原始点 | 风险 | 更优做法 |
|---|--------|------|----------|
| U1 | 「全局一个偏移」 | 不同城市偏移不同 | **按地理格子**存多套偏移（§6.3） |
| U2 | 「偏移多少像素」 | 一缩放就失效 | 权威单位用 **东向 / 北向米**；HUD 可同时显示换算后的 px |
| U3 | 「系统设置里调」 | 与站点无关、发现差、无法边看图边调 | **页内 HUD**；系统设置 **禁止** 放主控 |
| U4 | 「做成浏览器内核功能」 | 维护成本 = 维护 Google DOM 逆向 | **Page Pack 种子包**交付；原生只做可选壳（入口 / 诊断） |
| U5 | 「上面所有标注」一次搞定 | 不同层 DOM/WebGL 分离 | **分层开关**：路网 / 标注 / POI / 其他候选层（可探测） |
| U6 | 「永远对齐」 | Maps 改版、WebGL 直绘 | 明示 **Best-effort**；提供「探测层」与「失效提示」 |
| U7 | 独立插件市场 | 仅一站需求、过重 | 复用已有 **页面插件**；Catalog 远期可选 |

---

## 3. 方案定位

### 3.1 产品一句话

**地图叠加校准**：在 Google Maps 网页上叠加一个轻量校准面板，用「东/北米偏移」把矢量路网与标注视觉平移到与卫星底图对齐，并按浏览区域自动记住参数。

### 3.2 产品名

| 用途 | 名称 |
|------|------|
| 对外 | **地图叠加校准** |
| 代码 / Pack id | `maps-overlay-calibration`（模块目录可选 `MapsCalibration/`，若做原生壳） |
| 英文短名 | Map Overlay Calibration / MapAlign |

### 3.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 对 Maps 矢量叠加层做 **CSS transform / 容器平移**（或等价 JS 偏移） | 重写 Google Maps 投影 / 拦截全部瓦片重投影 |
| 页内 HUD：东/北十字方向键、数值、重置、暂停、保存 | 系统偏好里放偏移主控 |
| 按区域格子持久化偏移 | 声称「官方精度」或法律意义上的测绘校正 |
| 分层启用（能探测到的层） | 保证点击 hit-test、Street View、3D 倾斜视角完美 |
| 失效时提示「请刷新或更新 Pack」 | 静默假装一直有效 |
| 仅匹配 Maps 相关 host | 任意站点通用「页面偏移器」 |
| 与 PagePack 启停、人机页抑制策略兼容 | 在 Turnstile /sorry 等页强行注入干扰 |

### 3.4 设计原则

1. **边看边调**：校准控件必须压在地图视口上，而不是躲进设置窗。  
2. **米为权威，像素为派生**：持久化与区域记忆只存米（或 Δlng/Δlat）；px 仅运行时。  
3. **区域记忆**：不同格子不同偏移；切到无记录区时提示「本区未校准」。  
4. **Best-effort，可降级**：探测失败 → HUD 显示「未找到可偏移层」+ 诊断。  
5. **薄原生，厚脚本**：逻辑与 UI 尽量在 Pack JS；原生仅入口、种子安装、可选诊断通道。  
6. **人在回路**：默认不自动「猜」全国偏移；不偷偷改用户未打开的地图。  
7. **不进系统设置**：避免「浏览器全局设置污染」与错误心智模型。

### 3.5 形态选型（定稿）

| 方案 | 说明 | 结论 |
|------|------|------|
| A. 系统设置项 | 全局 dx/dy | **否决** |
| B. 纯用户自建 Page Pack | 零原生改动 | 可作为原型，但发现性差 |
| C. **内置种子 Page Pack + 页内 HUD** | 首次启动或首次打开 Maps 写入只读/可复制种子；侧栏可开关 | **主方案（MVP）** |
| D. 完整原生「地图助手」模块 | AppKit 面板 + ScriptMessage 双向 | **V2 可选**；仅当种子 Pack 不够用时升级 |
| E. Chrome Extension | 无 WebExtensions 运行时 | **否决**（本仓库无此能力） |

**定稿：C（MVP）→ 视需要升级到 D（壳增强）。**

---

## 4. 用户体验

### 4.1 入口（按优先级）

| 入口 | 行为 | 阶段 |
|------|------|------|
| **页内 HUD**「校准」折叠按钮 | 展开方向键；默认右下或右上，可拖移位置 | MVP |
| 页面插件侧栏 | 找到「地图叠加校准」Pack → 启停 / 编辑脚本 | MVP |
| 快捷键（页内） | 例如 `Alt+Shift+M` 切换 HUD（不与浏览器全局抢 ⌘） | MVP |
| Maps 域名下工具栏小按钮 | 注入「打开校准面板」消息或 `evaluateJavaScript` 调起 HUD | V1.1 |
| 查看菜单「地图叠加校准…」 | 仅当前 URL 为 Maps 时启用；否则灰显 + tooltip | V1.1 |
| 系统设置 | — | **永不作为主入口** |

### 4.2 页内 HUD 布局

```text
┌─ 地图叠加校准 ─────────────── ≡ ─ ✕ ─┐
│ 状态：本区已校准 · 东 +312 m  北 −148 m │
│ 图层：☑路网  ☑标注  ☑POI  ☐实验层     │
│ 东向  [────────●──────]  +312 m       │
│ 北向  [──────●────────]  −148 m       │
│ 步进 [1][10][50][100] m   当前 ≈ 12 px │
│ [暂停偏移] [重置本区] [另存为…]         │
│ ⚠ 视觉对齐；点击位置可能仍有偏差       │
└───────────────────────────────────────┘
```

交互细则：

| 项 | 定稿 |
|----|------|
| 默认态 | **收起为小圆钮 / 窄条**「校准」，避免挡地图 |
| 拖动 | 标题栏可拖；记忆 HUD 角落偏好（session 或 local） |
| 滑条范围 | 默认 ±2000 m（可配置）；超限可手动输入 |
| 数值输入 | 可点数值直接编辑米（`SBTextField` 不适用页内 HTML；用原生 `<input>` 即可） |
| 暂停 | 临时 `translate(0,0)`，不删区域记录 |
| 重置本区 | 清当前格子偏移，不删其他区 |
| 另存为 | V1.1：导出 JSON 配置（分享/备份） |
| 深色/浅色 | 跟随 `prefers-color-scheme`；半透明面板，不抢戏 |

### 4.3 典型用户流

| 场景 | 流程 |
|------|------|
| 首次在云南卫星图发现错位 | 打开 Maps → 见收起「校准」→ 展开 → 调东/北至对齐 → 自动写入本区格子 |
| 换城市 | 自动加载该格子记录；无记录则偏移为 0 + 提示 |
| 换 zoom | 脚本按米重算 px，视觉保持大致对齐 |
| 不想用 | 侧栏关闭 Pack；或 HUD「暂停」；或卸载/禁用种子 |
| Pack 失效（Google 改版） | HUD 显示探测失败；侧栏打开脚本更新；文档给「探测层」指引 |

### 4.4 空态与错误

| 状态 | 表现 |
|------|------|
| 非 Maps 页 | 不注入 HUD |
| 探测不到层 | HUD 红/黄条：「未找到可偏移图层。可尝试刷新或更新插件。」+「复制诊断」 |
| 仅部分层成功 | 分层勾选旁显示 ✓ / ✗ |
| 存储失败 | toast：「无法保存本区偏移」 |
| 人机验证 /sorry 页 | 遵循 PagePack 抑制策略，**不注入** |

### 4.5 无障碍与快捷键

| 操作 | 绑定 |
|------|------|
| 切换 HUD | `Alt+Shift+M`（页内） |
| 微调 | 展开后方向键 ±步进（可选） |
| 大步进 | `Shift` + 方向键 |
| Esc | 收起 HUD（不卸载偏移） |

---

## 5. 与现有架构的关系

```text
BrowserWindowController
  └── WKWebView
        └── PagePackInjector（已有）
              └── Pack: maps-overlay-calibration
                    ├── overlay-calibration.js   # 探测层、米→px、持久化、HUD
                    └── overlay-calibration.css  # HUD 样式（可选拆分）

（V1.1 可选）
MapsCalibrationChromeBridge  # 工具栏按钮 → evaluateJavaScript('MeoMapAlign.toggle()')
```

| 现有能力 | 用法 |
|----------|------|
| `PagePackMatcher` / `PagePackInjector` | match Maps URL，document-end / idle 注入 |
| `PagePackSidebarController` | 启停、编辑、热更新 |
| `PagePackStore` | 种子 Pack 落盘到 Application Support |
| Anti-bot 人机页抑制 | 风险 URL **跳过**本 Pack 注入 |
| SBKit | 仅当做 **原生** 设置/面板时使用；页内 HUD 用 DOM |

---

## 6. 数据模型

### 6.1 运行时配置（页内权威）

```text
MeoMapAlignConfig
├── schemaVersion          1
├── enabled                BOOL（暂停时仍可为 true，另用 paused）
├── paused                 BOOL
├── layers                 { roads, labels, pois, experimental } → BOOL
├── stepMeters             number（默认 10）
├── maxAbsMeters           number（默认 2000）
├── hud                    { collapsed, corner, offsetX, offsetY }
└── regions[]              MeoMapAlignRegion
```

### 6.2 区域记录

```text
MeoMapAlignRegion
├── cellId                 字符串，如 "c:25.50:100.00" （见 §6.3）
├── eastMeters             number   # 正 = 向东平移叠加层
├── northMeters            number   # 正 = 向北
├── updatedAt              epoch ms
├── note                   可选
└── sampleCenter           { lat, lng } 可选，便于展示
```

**符号约定（定稿）**：`eastMeters` / `northMeters` 表示 **叠加层（路网/标注）相对卫星底图** 的平移；用户看到「路偏西」时，应增大东向偏移把路往东推。

### 6.3 地理格子

| 项 | 定稿 |
|----|------|
| 默认格子 | **0.5° × 0.5°**（约 55 km 量级，国内城市间够用） |
| cellId | `c:{latFloor}:{lngFloor}`，lat/lng 向下取整到格子 |
| 查找 | 当前视口中心落入的 cell；无则继承最近邻（可选 V1.1）或 0 |
| 为何不用全国一套 | GCJ 偏移空间变化大；一套参数无法覆盖全国 |

V2 可升级：双线性插值邻格、或按「省 / 城市」命名配置档。

### 6.4 持久化位置

| 方案 | 位置 | 选用 |
|------|------|------|
| **A. `localStorage`（Maps origin）** | 与站点同源，Pack 可直接读写 | **MVP 采用** |
| B. Pack 旁 JSON 经原生桥写入 | 需 ScriptMessage | V1.1+ |
| C. 用户 Defaults 全局 | 错误分层 | **否** |

键名建议：`meo.mapsOverlayCalibration.v1`。

导出 / 导入（V1.1）：JSON 下载与文件选择（`<input type=file>`）。

### 6.5 米 → 像素换算

在纬度 `φ`、Web Mercator 近似下：

```text
metersPerPixel ≈ (156543.03392 * cos(φ * π/180)) / 2^zoom

dx_px =  eastMeters / metersPerPixel
dy_px = -northMeters / metersPerPixel   # 屏幕 y 向下为正
```

注意：

- Google 内部 zoom 可能是浮点；优先从 URL / 内部 API / 瓦片级别推断，失败则用视口分辨率启发式。  
- **倾斜 / 指南针旋转 / 3D** 下公式失效 → HUD 提示「请先恢复北朝上、俯视」。  
- 换算误差可接受：目标是肉眼对齐，不是测绘级。

---

## 7. 技术策略（页内）

### 7.0 Google Maps 页面加载与图层原理

#### 7.0.1 URL 与模式

示例：

`/maps/@25.70,100.20,3579m/data=!3m1!1e3`

| 片段 | 含义 |
|------|------|
| `@lat,lng,3579m` | 视口中心与大致高度（米）；也可为 `…z` 表示 zoom |
| `data=!3m1!1e3` | 内部 protobuf 风格状态；`1e3` 一类取值对应 **地球/卫星影像** 视图 |

页面为 **SPA**：首屏壳 HTML + 大量混淆 JS；真正地图在客户端用 **WebGL（为主）** 与网络瓦片数据画出来，而不是服务端画好整图。

#### 7.0.2 逻辑上的两层 vs 实现上的一层

产品语义上始终有两类数据：

| 逻辑层 | 内容 | 典型数据源（概念） |
|--------|------|-------------------|
| **底图** | 卫星 / 航拍影像 | 影像瓦片（历史上 `khms*` 等） |
| **叠加** | 路网、地名、POI、边界 | 矢量或透明标注瓦片（历史上 `mts*` / Vector Tile） |

在 **Maps JavaScript API** 的经典 Hybrid 模型里，二者可以是同一 tile `<div>` 里上下两张 `<img>`（底图 + 透明标注），或 `overlayMapTypes` 再叠一层——DOM 上有时还能分别操作。

但在 **www.google.com/maps 现行前端**（用户实测）：

- 卫星 + 路网/标注通常进入 **同一个 WebGL 场景**：影像作纹理，路网/字作后续（或同一帧内）绘制；  
- 对外往往只有 **一块（或少数）全屏 `<canvas>`**；  
- 对这块 canvas（或其唯一父容器）做 `transform`，等于移动 **整幅合成结果** → 卫星和路一起动。

因此：

```text
期望：  [卫星固定] + [路网/标注平移]
现实：  [卫星+路网 已合成的一帧] —— CSS 无法拆开
```

#### 7.0.3 为何「实验层」会整图移动、「非实验」没变化

| 模式 | 行为 | 原因 |
|------|------|------|
| 实验层 ON | 平移全屏 canvas 的 wrapper | 命中的是整场景，不是「上路网」 |
| 实验层 OFF | 几乎无视觉变化 | 故意不碰 WebGL；DOM POI 在该缩放级很少或没有 |
| 缩小后「黑屏」 | 整幅画布移出视口 | 露出 Maps 背后的黑色/空背景，不是单独黑遮罩层 |

#### 7.0.4 从底层机制上「只移路网」的可选路径

| 路径 | 做法 | 可行性 | 成本 / 风险 |
|------|------|--------|-------------|
| **A. DOM/CSS 分层面** | 找到独立的标注瓦片 `img` / 第二块 canvas，只 transform 它们 | 仅当前端仍分离渲染时 | 低；现行主站多半失败 |
| **B. WebGL 钩子** | Hook `draw*` / `uniformMatrix*`，只改矢量 pass 的矩阵 | 理论可 | 极高；混淆、改版即挂；合规风险 |
| **C. 网络层改瓦片** | 拦截标注矢量/透明瓦片请求并改坐标 | 理论可 | 高；协议私有、加密、会话 |
| **D. 自建叠加层（推荐）** | 保留 Google 卫星；关掉/遮住原生 Labels；用 OSM/MapLibre 等画透明路网+地名，只偏移该层；pan/zoom 与 Maps URL/相机同步 | **产品上最现实** | 中；同步与样式要做细；注意 ToS |
| **E. 换产品形态** | 不做注入，做「校准查看器」自有双图层地图 | 高可控 | 新功能，不再是「改 Google 页」 |

**定稿建议**：承认 A 在现行主站上基本失败；**下一阶段主攻 D**；A 仅作探测与侥幸分支；B/C 不纳入默认交付。

#### 7.0.5 与坐标系问题的关系

国内错位常被解释为影像与路网 **地理参考不一致**（如 WGS-84 vs GCJ-02）。  
这是「数据层」问题；即使用 D 自建路网，仍用 **东/北米偏移** 做局部对齐，模型不变。  
CSS 整场景平移 **不能** 表达「只改路网地理参考」。

### 7.1 总体管线

```text
document idle / spa urlchange
  → detectMapsContext()
  → probeArchitecture()          # webgl-unified | split-tiles | multi-canvas | …
  → ensureHUD()
  → discoverOverlayCandidates()  # 仅可分离目标；禁止误伤整场景（除非实验层明示）
  → loadRegionForMapCenter()
  → applyTransforms(east, north)
  → on(zoom|pan|idle) → recompute px → reapply
```

### 7.2 层发现（Best-effort）

Google Maps DOM **无稳定公开契约**。策略分层：

| 层级 | 策略 | 稳定性 |
|------|------|--------|
| L0 | 探测：canvas 数、是否 WebGL、`khms`/`mts` 等 `img` 瓦片 | 诊断用 |
| L1 | 若存在透明标注瓦片或独立 overlay canvas → 只偏移这些 | 低～中（视版本） |
| L2 | DOM POI chip（无 canvas 祖先） | 低体感 |
| L3 | 「实验层」：整场景 canvas（**会卫星+路一起动**，仅作对照） | 易误导，须文案标明 |
| L4 | **自建叠加层（D）** | 中长期主路径 |

**硬约束**：默认 **禁止** 把「只校准路网」做成整场景 transform；实验层必须标明「整图移动」。

### 7.3 应用偏移

对 **已确认的叠加目标**（非整场景）：

```css
transform: translate3d(dx_px, dy_px, 0);
```

自建叠加层（D）则对其容器应用同样的米→px 换算，底图容器 `transform` 保持恒等。

### 7.4 SPA 与生命周期

| 事件 | 处理 |
|------|------|
| `popstate` / History API | 监听；URL `@lat,lng,zoom` 变化时更新格子 |
| Maps 内部导航不改 history | `MutationObserver` + 定时轻量 poll（≤ 2 Hz）读中心 |
| 页面隐藏 | `visibilitychange` 时暂停重计算 |
| Pack 热更新 | 先 `teardown()` 再重新挂载，避免双 HUD |
| 多标签 | 每页独立；`localStorage` 同源共享区域数据（符合预期） |

### 7.5 Match 规则（种子 Pack）

```text
matches:
  - *://www.google.com/maps*
  - *://maps.google.com/*
  - *://www.google.com/maps/*
  - *://maps.google.*.*/*     # 若 Matcher 支持；否则列常见 TLD
excludes:
  - *://*/maps/reserve*       # 可选：预订等非地图主 UI
```

以 `PagePackMatcher` 实际能力为准；MVP 至少覆盖 `https://www.google.com/maps*`。

### 7.6 与 Anti-bot / PagePack 抑制

若当前 URL 被判定为人机挑战页（`/sorry`、CF 等），跳过注入；**不再**因 `google.com` 整站屏蔽 PagePack（否则本功能无法运行）。

---

## 8. 原生侧（MVP 最小集）

### 8.1 MVP：几乎零原生

| 工作 | 说明 |
|------|------|
| 仓库内置种子源文件 | 如 `SimpleBrowser/PagePack/BundledPacks/maps-overlay-calibration/` |
| 首次启动或首次打开 Maps | `PagePackStore` 安装种子（若不存在）；**不覆盖**用户已改过的同 id Pack |
| 文档 | 本设计 + 开发计划 + 侧栏说明文案 |

判定「用户已改过」：比较 `author`/`sourceURL`/`version` 或 `userModified` 标记。

### 8.2 V1.1：轻量 Chrome 桥（可选）

| 能力 | 实现 |
|------|------|
| 工具栏「校准」仅 Maps 可见 | URL 观察 + ActionGroup 条件显示 |
| 点击 → `MeoMapAlign.toggleHUD()` | `evaluateJavaScript` |
| 菜单项 | `BrowserMenus` |

仍 **不** 把偏移数值放进 `BrowserSettingsWindowController`。

### 8.3 V2：原生面板（仅当页内不够）

AppKit 浮动条 + `WKScriptMessageHandler` 读写配置；仅在页内 HUD 被 CSP / 遮挡严重时考虑。当前 Google Maps **允许**页内 DOM UI，故 V2 非必须。

---

## 9. 安全、隐私与合规

| 项 | 定稿 |
|----|------|
| 数据外传 | **无**；配置仅 localStorage / 本地 Pack |
| 权限 | 仅页面世界 JS；无 GM 跨域 |
| 测绘合规 | UI 文案标明：**个人视觉辅助，非测绘成果** |
| ToS | 用户脚本改 DOM；存在违反站点条款风险 → 文档「自用 / Best-effort」 |
| 供应链 | 种子 Pack 随 App 分发；远程更新走 PagePack Catalog（远期）且需确认 |

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Google 改版导致选择器失效 | 功能整死 | 探测失败 UI；版本化 Pack；L2 点选图层 |
| 只动视觉、不动命中区 | 点击 POI 偏了 | 文案警告；可选「降低偏移用于交互」不做默认 |
| 倾斜 3D / 旋转 | 米→px 错误 | 检测 bearing/tilt ≠ 0 时禁用并提示 |
| 误移卫星底图 | 越调越乱 | 层分类 + 排除；默认黑名单启发式 |
| 性能 | 每帧 transform | 仅在 idle/zoom 结束时更新；`requestAnimationFrame` 节流 |
| 与其他 Page Pack 冲突 | 双改 transform | 专用 wrapper；文档建议勿叠同类脚本 |
| 人机页误伤 | 验证失败 | 走现有抑制 |

---

## 11. 分期产品范围

| 阶段 | 名称 | 交付 |
|------|------|------|
| **MOC-MVP** | 探针 + 像素滑条 | 证明「能挪动某些层」；可暂用 px，不强调区域 |
| **MOC-1** | 米制 + 区域格子 + HUD 定稿 | 可日常使用 |
| **MOC-2** | 种子安装 + 分层 + 诊断导出 | 可分发给本机用户 |
| **MOC-3** | Chrome 入口 + 导入导出 + 点选图层 | 体验完整 |
| **MOC-4** | （可选）原生桥 / Catalog 更新 | 长期维护 |

---

## 12. 验收标准（设计级）

1. 在给定云南卫星链接、俯视北朝上时，用户能在 2 分钟内用 HUD 把路网视觉对齐到可接受程度。  
2. 刷新页面后同区域偏移恢复。  
3. 改变 zoom（至少两档）后偏移仍大致可用（米制）。  
4. 禁用 Pack 或暂停后，地图恢复未偏移外观。  
5. 非 Maps 页无 HUD、无注入副作用。  
6. 探测失败时有明确提示，而非空白无反馈。  
7. 系统设置中 **不出现** 东/北偏移主控项。

---

## 13. 决策记录

| ID | 决策 | 结论 |
|----|------|------|
| D1 | 内置 vs 插件 | **种子 Page Pack**，非系统设置 |
| D2 | 主 UI | **页内 HUD** |
| D3 | 偏移单位 | **东/北米**；px 派生 |
| D4 | 记忆粒度 | **0.5° 地理格子** |
| D5 | 持久化 | MVP 用 **localStorage** |
| D6 | 点击对齐 | **不承诺** |
| D7 | WebGL 内核改写 | **不做** |
| D8 | 系统设置 | **不进** |
| D9 | 原生模块 | MVP 仅种子安装；Chrome 桥 V1.1 |

---

## 14. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-09-04 | 初稿定稿：Page Pack + 页内 HUD + 米制区域记忆 |

---

## 15. 开放问题（实现期关闭）

| # | 问题 | 建议关闭方式 |
|---|------|----------------|
| Q1 | 当前 Google Maps DOM 上哪些节点可稳定 translate？ | MOC-MVP 探针实验记录进开发计划附录 |
| Q2 | 浮点 zoom 如何从页面可靠读取？ | 试 URL → `window.APP_INITIALIZATION_STATE` 类全局 → 启发式 |
| Q3 | Matcher 是否支持 `maps.google.*` 多 TLD？ | 对照 `PagePackMatcher` 测试；不足则显式列举 |
| Q4 | 种子 Pack 升级策略是否覆盖用户修改？ | 默认 **永不覆盖**；侧栏提供「恢复官方种子」 |
