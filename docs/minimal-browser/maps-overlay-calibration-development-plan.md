# 地图叠加校准（Maps Overlay Calibration）— 开发计划

> 基于 [maps-overlay-calibration-design.md](maps-overlay-calibration-design.md)（**已确认定稿**）。  
> 前置：PagePack MVP（Store / Matcher / Injector / 侧栏）、`WKWebView` 导航挂钩、Anti-bot PagePack 抑制策略。  
> 状态：**MOC-0～MOC-2 代码已落地（待真机 Maps 验收）** · 2026-09-04  
> 关联设计：[page-pack-design.md](page-pack-design.md) · [page-pack-development-plan.md](page-pack-development-plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 产品名 | 地图叠加校准；Pack id `maps-overlay-calibration` |
| 形态 | **种子 Page Pack** + **页内 HUD**；不进系统设置 |
| 偏移单位 | 东/北 **米**；运行时换算 px |
| 记忆 | `localStorage` + **0.5°** 地理格子 |
| Match | 至少 `https://www.google.com/maps*` |
| 成功线 | 视觉对齐；**不**承诺点击/几何对齐 |
| 3D/旋转 | 非北朝上俯视时提示并建议暂停自动换算 |

**首版交付目标：MOC-0 + MOC-MVP + MOC-1 + MOC-2。**  
MOC-3 / MOC-4 为体验增强，可另开迭代。

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| **MOC-0** | 探针与可行性记录 | **进行中（运行时探测）** | 层发现内置；附录 A 待真机填写 |
| **MOC-MVP** | 最小可感脚本 | **完成（代码）** | Pack JS/CSS + HUD + transform |
| **MOC-1** | 米制 + 区域记忆 | **完成（代码）** | 米↔px、格子、localStorage、poll |
| **MOC-2** | 种子安装与打磨 | **完成（代码）** | SeedInstaller、Bundle 拷贝、分层/诊断 |
| **MOC-3** | Chrome 入口与导入导出 | 可选 | 工具栏/菜单、JSON 备份、点选图层 |
| **MOC-4** | 原生桥 / Catalog | 可选 | ScriptMessage、远程更新种子 |
| **MOC-5** | **自建透明路网叠加层** | **进行中（1.2.x）** | Leaflet 叠加 + 相机同步 + 仅偏移自建层 |
| **MOC-E** | **Google Earth Web 扩展** | **拆成独立 Pack 1.0.0** | `earth-overlay-calibration`；Maps 1.3.1 不再匹配 Earth |

---

## Phase MOC-5：自建透明路网叠加层

**目标**：不碰 Google WebGL；在上方自建 Leaflet 透明标注/路网层，东/北偏移只作用于该层。

### 任务清单

- [x] **5.1** 打包 Leaflet 1.9.4（`leaflet.js` / `leaflet.css`）进种子 Pack
- [x] **5.2** 全屏透明 overlay host（`pointer-events: none`），与 Google 交互不抢
- [x] **5.3** 从 URL `@lat,lng,zoom|m` 同步 Leaflet `setView`
- [x] **5.4** 东/北米 → px，只 `transform` `#meo-mapalign-leaflet-shift`
- [x] **5.5** 瓦片样式：CARTO 仅标注 / OSM 半透 / 深色标注
- [x] **5.6** HUD：自建层开关、样式、暂停/重置/同步；文案提示关闭 Google Labels
- [ ] **5.7** 真机验收：卫星不动、自建层可移；CSP 下瓦片能否加载
- [ ] **5.8** （可选）更「纯路网」矢量源 / MapLibre

### 验收

1. [ ] 拖东/北滑条时 Google 卫星底图不动，自建标注/路网移动  
2. [ ] 平移/缩放 Google 地图后自建层跟手（约 0.5s 内）  
3. [ ] 关闭「自建叠加层」后叠加消失  
4. [ ] 重启后区域偏移恢复  

---

## Phase MOC-0：探针与可行性记录

**目标**：在真实 Google Maps 卫星页上确认「至少一类叠加层可被平移」，并留下可复现笔记，避免后续盲写。

### 任务清单

- [ ] **0.1** 用 MeoBrowser 打开设计文档中的云南卫星示例 URL（及至少 1 个对照城市）
- [ ] **0.2** Web Inspector / 临时 Pack：枚举全屏 canvas、常见容器、带 `transform` 的祖先
- [ ] **0.3** 对候选节点试 `translate3d(Npx,0,0)`，记录：路网 / 标注 / POI / 卫星底图 各自是否移动
- [ ] **0.4** 记录误伤情况（是否带动底图、控件、搜索框）
- [ ] **0.5** 记录 zoom 变化后固定 px 是否明显错位（验证米制必要性）
- [ ] **0.6** 将选择器启发式与截图结论写入本文 **附录 A**（可只文字，不强制贴图）

### 验收

1. [ ] 至少一种「路网或标注」层可稳定肉眼平移  
2. [ ] 明确列出「禁止平移」的节点特征（底图 / chrome）  
3. [ ] 若 **完全不可行**：停止后续阶段，回写设计文档状态为「阻塞」，并说明原因  

### 退出准则

| 结果 | 动作 |
|------|------|
| 可平移矢量相关层 | 进入 MOC-MVP |
| 仅能平移无关 DOM | 调整策略或降级为「实验性」文案后谨慎进入 MVP |
| 完全无法影响叠加 | **中止**；不交付种子 Pack |

---

## Phase MOC-MVP：最小可感脚本

**目标**：用户在 Maps 页看到 HUD，拖动滑条即可看到叠加层移动（此阶段可用 **px**，不强制米与格子）。

### 任务清单

#### MVP-A — Pack 骨架

- [ ] **1.1** 新建源码目录，建议：  
      `SimpleBrowser/PagePack/BundledPacks/maps-overlay-calibration/`  
      含 `manifest.json`、`overlay-calibration.js`、`overlay-calibration.css`（可先单文件 JS）
- [ ] **1.2** `manifest` 字段对齐 `PagePack` 模型：`name`、`matches`、`files`、`version`、`author`、`description`
- [ ] **1.3** Match 至少：`*://www.google.com/maps*`；按 Matcher 能力补 `maps.google.com`
- [ ] **1.4** `runAt`：`document-end` 或 `document-idle`（优先 idle，减少与 Maps 启动竞争）

#### MVP-B — 层应用

- [ ] **1.5** 实现 `discoverCandidates()`（基于附录 A）
- [ ] **1.6** 实现 `applyPixelOffset(dx, dy)`：wrapper + `translate3d`；幂等（不重复包层）
- [ ] **1.7** 实现 `clearOffset()` / `teardown()`
- [ ] **1.8** 排除启发式：不碰明显 chrome / 搜索框 / 底图候选

#### MVP-C — 最小 HUD

- [ ] **1.9** 注入可拖动面板：东/北两个 range（单位先标 px）
- [ ] **1.10** 折叠 / 展开；默认折叠小钮
- [ ] **1.11** 重置按钮；页内 `Alt+Shift+M` 切换
- [ ] **1.12** 警告文案：「视觉对齐；点击可能仍偏差」
- [ ] **1.13** 样式独立、半透明、不挡住 Maps 主要操作区（默认可拖）

#### MVP-D — 接入注入

- [ ] **1.14** 开发期：用页面插件侧栏「新建 / 粘贴」或手动拷入 Application Support 验证
- [ ] **1.15** 热更新：侧栏保存后当前页重挂载不出现双 HUD
- [ ] **1.16** 确认人机 /sorry 抑制路径下不注入（沿用现有 Injector 行为即可）

### 验收（手工）

1. [ ] 打开卫星图 → 展开 HUD → 拖东向滑条 → 路网或标注明显横移  
2. [ ] 重置后外观恢复  
3. [ ] 折叠后不严重挡图  
4. [ ] 刷新后若未做持久化，偏移丢失可接受（本阶段）  
5. [ ] 非 Maps 页无 HUD  

---

## Phase MOC-1：米制 + 区域记忆

**目标**：日常可用——换 zoom 仍大致对齐；同区域刷新后恢复。

### 任务清单

#### 1A — 地理与换算

- [ ] **2.1** 从 URL / 页面状态读取 `lat, lng, zoom`（失败则启发式；记录日志到诊断对象）
- [ ] **2.2** 实现 `metersPerPixel(lat, zoom)` 与 `metersToPixels(east, north)`
- [ ] **2.3** HUD 滑条改为 **米**；副文案显示当前约合 px
- [ ] **2.4** 步进按钮：1 / 10 / 50 / 100 m；`maxAbsMeters` 默认 2000
- [ ] **2.5** 检测非北朝上或明显 tilt 时提示（能读则读；读不到则文档说明局限）

#### 1B — 区域格子

- [ ] **2.6** `cellId`：0.5° 向下取整
- [ ] **2.7** `localStorage` 键 `meo.mapsOverlayCalibration.v1`；schemaVersion = 1
- [ ] **2.8** 视口中心变化 → 切换 cell → 加载或创建记录
- [ ] **2.9** 滑条变更防抖写入（如 300 ms）
- [ ] **2.10** 「重置本区」只清当前 cell
- [ ] **2.11** 「暂停偏移」：视觉归零，保留存储

#### 1C — 生命周期

- [ ] **2.12** 监听 history / 轻量 poll（≤ 2 Hz）更新中心与 zoom
- [ ] **2.13** zoom/pan idle 后重算 px 并 `apply`
- [ ] **2.14** `visibilitychange` 时降频或暂停
- [ ] **2.15** SPA 多次进入 Maps 不泄漏多份 listener（`teardown` 成对）

### 验收（手工）

1. [ ] 调好云南区偏移 → 刷新 → 自动恢复  
2. [ ] 改变 zoom 两档以上，对齐不显著崩溃  
3. [ ] 平移到远距离另一城市 → 偏移为 0 或该区记录；回云南恢复云南记录  
4. [ ] 暂停后视觉无偏移；取消暂停恢复  
5. [ ] 重置本区后该 cell 为 0，其他 cell 不受影响  

---

## Phase MOC-2：种子安装与打磨

**目标**：普通用户安装 MeoBrowser 后，打开 Maps 即可用，无需手写脚本。

### 任务清单

#### 2A — 种子分发

- [ ] **3.1** Makefile / 拷贝资源：将 `BundledPacks/maps-overlay-calibration/**` 打进 App Resources  
- [ ] **3.2** `PagePackStore`（或小型 `PagePackSeedInstaller`）：  
      - App 启动或首次需要时：若本地无该 `packID`，从 Bundle 安装  
      - 若已存在且 `userModified` / 版本由用户编辑过：**不覆盖**  
- [ ] **3.3** 侧栏显示名称「地图叠加校准」；description 含 Best-effort 说明  
- [ ] **3.4** 「恢复官方种子」操作（确认框）：强制用 Bundle 覆盖本地同 id  

#### 2B — 分层与诊断

- [ ] **3.5** 图层开关：roads / labels / pois / experimental（按附录 A 映射；探不到则禁用勾选）  
- [ ] **3.6** 探测失败横幅 +「复制诊断」JSON（选择器命中数、lat/lng/zoom、schema）  
- [ ] **3.7** 状态行：本区已校准 / 未校准 / 已暂停  

#### 2C — 文档与路线图

- [ ] **3.8** `docs/README.md` 已索引本设计与计划（本迭代完成）  
- [ ] **3.9** `professional-features-roadmap.md` 增加一行指向本方案（可选同 PR）  
- [ ] **3.10** 页面插件侧栏空态或 Pack 描述中给一句话引导  

#### 2D — 回归

- [ ] **3.11** 总开关「启用页面插件」关闭时本功能不出现  
- [ ] **3.12** 与另一测试 Pack 同页共存不出现双 transform 破坏（尽量）  
- [ ] **3.13** `make browser` 通过  

### 验收（手工）

1. [ ] 干净 Application Support：启动 App → 侧栏可见种子 Pack（或首次打开 Maps 后出现）  
2. [ ] 用户改过脚本后升级 App **不丢**修改  
3. [ ] 「恢复官方种子」可还原  
4. [ ] 探测失败有明确 UI  
5. [ ] 设计文档 §12 验收标准 1～7 全部满足  

---

## Phase MOC-3：Chrome 入口与导入导出（可选）

**目标**：发现性与备份；仍不进系统设置。

### 任务清单

- [ ] **4.1** Maps URL 下 ActionGroup 显示「校准」按钮 → `MeoMapAlign.toggleHUD()`  
- [ ] **4.2** 查看菜单「地图叠加校准…」（非 Maps 灰显）  
- [ ] **4.3** HUD：导出 / 导入 JSON（全 regions）  
- [ ] **4.4** 「点选图层」模式：用户点击元素加入偏移目标（写入 localStorage 覆盖默认发现）  
- [ ] **4.5** HUD 位置记忆  

### 验收

1. [ ] 仅在 Maps 显示工具栏按钮  
2. [ ] 导出文件可在另一台干净环境导入后恢复区域偏移  
3. [ ] 点选图层在改版后可作为临时自救  

---

## Phase MOC-4：原生桥 / Catalog（可选）

- [ ] **5.1** `WKScriptMessageHandler`：原生读写配置文件（可选替代 localStorage）  
- [ ] **5.2** PagePack Catalog 条目：远程更新种子（需安装确认）  
- [ ] **5.3** 原生诊断窗（展示附录级信息）— 仅当页内不够时  

**默认不纳入首版交付。**

---

## 建议目录与文件

```text
SimpleBrowser/PagePack/BundledPacks/maps-overlay-calibration/
├── manifest.json
├── overlay-calibration.js
└── overlay-calibration.css

SimpleBrowser/PagePack/
├── PagePackSeedInstaller.h/.m          # MOC-2，可内嵌 Store
└── （现有 Injector / Store / Sidebar）

docs/minimal-browser/
├── maps-overlay-calibration-design.md
└── maps-overlay-calibration-development-plan.md   # 本文件
```

页内全局 API（约定）：

```js
window.MeoMapAlign = {
  toggleHUD() {},
  setOffsetMeters(east, north) {},
  pause(boolean) {},
  resetCurrentRegion() {},
  getDiagnostics() {},
  teardown() {}
};
```

---

## 测试矩阵（手工）

| # | 场景 | 期望 |
|---|------|------|
| T1 | 云南卫星 @~3 km | 可对齐路网 |
| T2 | 同城换 zoom | 大致保持 |
| T3 | 跨城 | 独立 cell |
| T4 | 刷新 / 新标签同 URL | 恢复 |
| T5 | 禁用 Pack | 无偏移无 HUD |
| T6 | 暂停 | 无偏移，数据仍在 |
| T7 | 北朝上以外（若可测） | 提示 |
| T8 | 非 Maps | 无注入 |
| T9 | 热更新 Pack | 单 HUD |
| T10 | 页面插件总开关关 | 不运行 |

---

## 工时量级（参考）

| 阶段 | 粗估 |
|------|------|
| MOC-0 | 0.5～1 天（含踩坑） |
| MOC-MVP | 1～2 天 |
| MOC-1 | 1～2 天 |
| MOC-2 | 1 天 |
| MOC-3 | 1～2 天 |
| **首版合计** | **约 4～6 天** |

若 MOC-0 失败，则总工时止于探针阶段。

---

## 风险检查点（实现中复勾）

| 检查点 | 何时 | 动作 |
|--------|------|------|
| 层发现成功率 | MOC-0 / 每次 Maps 大改版 | 更新启发式或发 Pack 小版本 |
| 性能（拖图卡顿） | MOC-1 | 降 poll 频率、仅 idle 应用 |
| localStorage 被清 | MOC-1 | 文档说明；MOC-3 导出备份 |
| 与透明模式 / 查找条 z-index | MOC-2 | HUD z-index 策略避开 chrome |

---

## 附录 A — 层探测笔记（MOC-0 填写）

> 实现期维护；下列为模板。

| 日期 | Maps 版本线索（UA/UI） | 选择器 / 路径 | 移动的是 | 是否误伤底图 | 备注 |
|------|------------------------|---------------|----------|--------------|------|
| 2026-09-04 | 代码启发式（未真机确认） | 全屏 `canvas`：按 z-index/DOM 排序，**跳过最底层**，平移其余 | 预期为路网/标注叠加 canvas | 若仅 1 个 canvas 则默认不移（需勾选「实验层」） | 见 `discoverCandidates()` |
| 2026-09-04 | 同上 | `div[role=button][aria-label]` 等小面积节点 | POI/可点标注（Best-effort） | 排除 chrome/search | 上限 80 个 |

**当前结论**：运行时策略已编码；**须在真实 Google Maps 卫星页验收**。若「层 0」且单 canvas，勾选「实验层」或点「复制诊断」反馈。

**落地文件**：

- `SimpleBrowser/PagePack/BundledPacks/maps-overlay-calibration/`
- `SimpleBrowser/PagePack/PagePackSeedInstaller.h/.m`
- 启动时 `AppDelegate` → `installBundledSeedsIfNeeded`

---

## 附录 B — 示例 localStorage schema

```json
{
  "schemaVersion": 1,
  "paused": false,
  "layers": {
    "roads": true,
    "labels": true,
    "pois": true,
    "experimental": false
  },
  "stepMeters": 10,
  "maxAbsMeters": 2000,
  "hud": {
    "collapsed": true,
    "corner": "bottom-right"
  },
  "regions": [
    {
      "cellId": "c:25.5:100.0",
      "eastMeters": 312,
      "northMeters": -148,
      "updatedAt": 1756960000000,
      "sampleCenter": { "lat": 25.6903, "lng": 100.1732 }
    }
  ]
}
```

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-09-04 | 初稿；MOC-0～MOC-4 分期；待开工 |
| 0.2 | 2026-09-04 | 落地种子 Pack + SeedInstaller；MOC-MVP/1/2 代码完成，待 Maps 真机验收 |
