# 透明模式 Chrome 修订 — 保留标签栏 / 地址栏随精简

> **修订动机**：进入透明模式后仍需操作标签与 Chrome 动作区（摸鱼 / 透明 / 精简 / 置顶）；地址栏是否显示应与「精简模式」一致，而非一律隐藏。  
> 状态：**已完成（TC-0～TC-2）**  
> 开发计划：[transparent-mode-chrome-revision-development-plan.md](transparent-mode-chrome-revision-development-plan.md)  
> Cursor 计划：[.cursor/plans/transparent-mode-chrome-revision.plan.md](../../.cursor/plans/transparent-mode-chrome-revision.plan.md)  
> 关联：[transparent-mode-design.md](transparent-mode-design.md)（原「全壳隐藏」被本修订覆盖相关条款）· [tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) · [afk-mode-design.md](afk-mode-design.md)

---

## 1. 需求理解

### 1.1 用户原话（要旨）

1. **进入透明模式时，要显示顶部的标签栏**  
2. **是否显示地址栏，由是否处于精简模式决定**  
   - 非精简 → 显示地址栏（工具栏行）  
   - 精简 → 不显示地址栏（与常态精简一致；⌘L Peek 仍可用）

### 1.2 与现状的差异

| 项 | 现状（TM-1） | 修订后 |
|----|-------------|--------|
| 标签条 accessory | **移除**，透明态无标签条 | **保留并显示** |
| 交通灯 | 隐藏 | **显示**（与标签条同级，可关窗/缩放） |
| 地址栏 / toolbar | **一律** `hidden=YES` | **跟随 `compactModeEnabled`（+ Peek）** |
| 侧栏 / 浮层 | 进入时收起 | **保持**（本修订不放宽） |
| 窗口 / 页面透明 | 有 | **不变** |
| 页面字色注入 | 有 | **不变** |
| Status Item | 进出透明主出口之一 | **保留**（仍可进出；壳内也可点透明图标） |

### 1.3 产品一句话（修订后）

**透明阅读时仍留标签条操控窗口；地址栏只在非精简时出现，精简时藏栏专注正文。**

---

## 2. 行为定稿

### 2.1 进入透明后的壳显隐矩阵

| UI | 透明 + 非精简 | 透明 + 精简 | 说明 |
|----|---------------|-------------|------|
| 标签条（含 Chrome 动作区） | 显示 | 显示 | 含摸鱼 / 透明 / 精简 / 置顶 |
| 交通灯 | 显示 | 显示 | 与标签条一并可用 |
| 地址栏行（toolbar） | **显示** | **隐藏**（除非 Peek） | 与 `applyToolbarVisibilityForCompactState` 同规则 |
| ◀▶ 位置 | toolbar 内 | 标签条 leading | 精简搬家逻辑不变 |
| 侧栏 | 隐藏 | 隐藏 | 进入时 `hideAll`；不在透明态默认打开 |
| 查找条 / 下载面板 / 概览等 | 进入时关掉 | 同左 | `dismissTransientUIForTransparentMode` 保留 |
| NTP Launchpad | 隐藏或按既有透明规则 | 同左 | 不因本修订改为常显 |

### 2.2 透明态下切换精简

```
透明开着
  → 点「精简」开：地址栏收起；◀▶ 迁到标签条左侧
  → 点「精简」关：地址栏展开；◀▶ 回 toolbar
  → 透明布尔不变；窗口/页面透明样式不变
```

实现要点：透明态下 **允许** `setCompactModeEnabled:` 正常跑布局；**禁止**再写死 `if (transparent) toolbar.hidden = YES`。

### 2.3 透明 + 精简下改址（Peek）

| 项 | 定稿 |
|----|------|
| ⌘L / 「打开位置」 | **允许**（去掉「透明则直接 return」） |
| Peek 展开 | 临时显示 toolbar，与非透明精简一致 |
| Return / Esc | 导航或取消后收起；仍保持透明 + 精简 |

### 2.4 退出透明

- 标签条本就在 → 不必「加回 accessory」（若从未移除则 `transparentModeAccessoryRemoved` 可废弃或恒为 NO）  
- 按当前 `compactModeEnabled` 重放 toolbar / ◀▶（与现 `exitTransparentModeChrome` 后半段一致）  
- 还原窗口 opaque / 背景 / WebView / 页面样式（不变）

### 2.5 与摸鱼 / 置顶

| 组合 | 行为 |
|------|------|
| 透明 + 摸鱼 | 移出整窗 `alpha=0`（含标签条）；移入仍透明且标签条仍在 |
| 透明 + 置顶 | 不变 |
| 透明态点摸鱼 / 置顶 | 标签条可见，可直接操作 |

### 2.6 出口

| 出口 | 修订后 |
|------|--------|
| 标签条「透明」图标 | **可用**（主路径之一） |
| Status Item | 保留 |
| Esc | 仍不退出透明 |

---

## 3. 实现要点（对照代码）

### 3.1 核心改动面

| 位置 | 现状问题 | 修订动作 |
|------|----------|----------|
| `enterTransparentModeChrome` | `removeTitlebarAccessoryViewController` 卸标签条；`setStandardWindowButtonsHidden:YES`；`toolbar.hidden = YES` | **不卸** accessory；交通灯 **显示**；toolbar 改走 `applyToolbarVisibilityForCompactState`（或等价） |
| `exitTransparentModeChrome` | 按 `transparentModeAccessoryRemoved` 加回 accessory | 简化：若未移除则跳过；仍 `setStandardWindowButtonsHidden:NO` + 精简重放 |
| `applyToolbarVisibilityForCompactState` | 透明时强制 `toolbar.hidden = YES` | **删除该短路**；统一：`show = !compact \|\| peek` |
| `beginAddressBarPeek` | 透明时直接 return | **允许** Peek |
| `transparentModeAccessoryRemoved` | 标记是否卸过 accessory | 可删或保留但进入路径不再置 YES |

### 3.2 进入路径伪代码（定稿）

```text
enterTransparentModeChrome:
  dismissTransientUI
  hide sidebars
  captureSnapshot (窗口/WebView 外观)
  // 不再 remove tabStripAccessory
  setStandardWindowButtonsHidden:NO   // 或保持系统默认可见
  apply toolbar/nav for compact       // 非强制藏 toolbar
  applyWindowTransparency + page style
  enable right-drag move
  layout
```

### 3.3 视觉注意（V1 可轻量）

透明窗 + 系统标题栏/标签条时，条背景可能过透导致字难读。V1 策略：

1. **优先**：沿用现有 titlebar accessory 材质，不额外大改  
2. 若手测难读：给 `tabStripAccessoryRoot` / strip 加半透明底（如 `NSVisualEffectView` 或浅色 `alpha≈0.85`），**仅透明态**开关  

本修订 **不**把标签条做成完全透明不可读。

### 3.4 明确不改

- 窗口 `opaque` / clear 背景 / WebView `drawsBackground`  
- 页面 `transparent-mode-style.js` 注入与设置色  
- 右键拖窗  
- 全屏禁透明  
- session 键 `transparentMode`  
- 摸鱼 alpha 逻辑  

---

## 4. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| R1 | 透明态标签条 | **显示** |
| R2 | 透明态地址栏 | **跟随精简**（非精简显、精简藏） |
| R3 | 透明态交通灯 | **显示** |
| R4 | 透明态侧栏 | 进入仍收起；不默认开 |
| R5 | 透明态可切精简 | **是**，即时改地址栏显隐 |
| R6 | 透明+精简 Peek | **允许** |
| R7 | Status Item | 保留 |
| R8 | 标签条可读性 | V1 先系统默认；难读再加半透明底 |

---

## 5. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 标题栏在 clear 窗上发灰/发花 | R8；手测后可选 effect view |
| 旧逻辑「透明=全壳隐」散落多处 | 全文搜 `transparentModeEnabled` + `toolbar.hidden` / `AccessoryRemoved` / Peek return |
| 与 compact 双路径打架 | 单一 `applyToolbarVisibilityForCompactState`，透明不再短路 |
| 文档/验收仍写「壳全隐」 | 本修订文档为准；更新原 design 交叉引用 |

---

## 6. 验收标准

- [x] 进入透明：顶部标签条可见，可点摸鱼/透明/精简/置顶  
- [x] 透明 + 非精简：地址栏可见，可改址导航  
- [x] 透明 + 精简：地址栏隐藏；⌘L Peek 可临时展开再收起  
- [x] 透明态下开关精简：地址栏显隐与 ◀▶ 位置正确切换  
- [x] 退出透明：页面/窗口样式还原；精简布尔保持；壳布局正确  
- [x] 侧栏进入透明时仍收起  
- [x] 交通灯可见可用  
- [x] `make browser` 通过；与摸鱼叠加：移出隐身、移入标签条仍在  

---

## 7. 后续（非本修订）

- 透明态标签条专用视觉主题  
- 透明态「自动藏条、鼠标移顶再显」  
- 侧栏在透明态可选保留  
