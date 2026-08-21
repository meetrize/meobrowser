# 透明模式 — 鼠标移出自动藏壳（标签条 / 地址栏）

> **需求**：透明模式下，鼠标移出本窗 `frame` → 自动隐藏标签条；移入 → 自动再显示。地址栏跟精简走：精简则始终不显示；非精简则与标签条同进同出（移出藏、移入显）。  
> 状态：**已完成（TH-0～TH-2）**  
> 开发计划：[transparent-mode-chrome-autohide-development-plan.md](transparent-mode-chrome-autohide-development-plan.md)  
> Cursor 计划：[.cursor/plans/transparent-mode-chrome-autohide.plan.md](../../.cursor/plans/transparent-mode-chrome-autohide.plan.md)  
> 关联：[transparent-mode-chrome-revision-design.md](transparent-mode-chrome-revision-design.md)（TC：进入透明保留标签条）· [afk-mode-design.md](afk-mode-design.md)（整窗 alpha 隐身，正交）· [transparent-mode-design.md](transparent-mode-design.md)

---

## 1. 需求理解

### 1.1 用户原话（拆解）

| 条件 | 行为 |
|------|------|
| 处于**透明模式**，鼠标**移出**窗口区域 | **自动隐藏标签条** |
| 透明模式，鼠标**移入**窗口区域 | **自动显示标签条** |
| **精简模式** | 地址栏**始终不显示**（与是否在窗内无关） |
| **非精简** + 透明，鼠标移出 | **同时隐藏地址栏** |
| **非精简** + 透明，鼠标移入 | **显示地址栏** |

非透明模式：本能力**关闭**，壳显隐仍按精简常态（TC / CA 原逻辑）。

### 1.2 与已有能力的关系

| 能力 | 关系 |
|------|------|
| TC（保留标签条） | 本方案建立在「透明态可有标签条」之上；再叠加「按鼠标进出自动藏/显」 |
| 精简模式 | 决定地址栏是否参与「移入显示」；精简时地址栏永不因移入而出现 |
| 摸鱼（AFK） | **正交**：摸鱼管整窗 `alpha=0`；本方案只管壳（条/栏）。可同时开 |
| Status Item | 壳藏起后仍可进出透明 / 摸鱼 |

### 1.3 产品一句话

**透明阅读时：指针在窗内露出标签条（非精简时还有地址栏）；指针一出，壳收起，只留透明正文。**

---

## 2. 行为定稿

### 2.1 显隐矩阵（仅 `transparentModeEnabled == YES`）

记 `pointerInside = 鼠标在 window.frame 内`。

| UI | 精简 + 指针内 | 精简 + 指针外 | 非精简 + 指针内 | 非精简 + 指针外 |
|----|---------------|---------------|-----------------|-----------------|
| 标签条 | 显示 | **隐藏** | 显示 | **隐藏** |
| 交通灯 | 显示 | **隐藏**（随条） | 显示 | **隐藏**（随条） |
| 地址栏 | **隐藏** | **隐藏** | **显示** | **隐藏** |
| 网页区 | 显示 | 显示 | 显示 | 显示 |

说明：

- 精简下 ◀▶ 在标签条 leading：条藏则导航一并不可见（可接受；移入即恢复）。  
- Peek：仅当精简且用户主动 ⌘L；Peek 展开时视为「需要地址栏」，**强制显示 toolbar**，且建议**暂时抑制自动藏壳**（或 Peek 期间指针外仍保持 Peek 栏，直到 Esc/Return）。**定稿：Peek 激活期间不因移出藏地址栏；标签条仍可按指针藏/显。** 若 Peek 时条已藏，Peek 仍可单独展开 toolbar。

### 2.2 状态机（每窗）

```
非透明 ──开透明──► Armed（监视指针；按 inside 刷新壳）
                      │
         指针外 / 内   │  边沿变化 → applyChromeChromeVisibility
                      │
非透明 ◄──关透明──────┘  （卸监视；按精简常态还原壳）
```

内部布尔（建议）：

| 名 | 含义 |
|----|------|
| `transparentChromeAutoHideActive` | 是否启用本监视（= 透明开） |
| `transparentChromePointerInside` | 最近一次指针是否在 frame 内 |
| （复用）`compactModeEnabled` / `addressBarPeekActive` | 参与地址栏公式 |

### 2.3 显隐公式（定稿）

```text
showTabStrip   = transparent && pointerInside
                 （非透明时：始终按系统/accessory 常态显示，不走本公式）

showToolbar    = !compact || peek
               当 transparent 时再与：
                 showToolbar = showToolbar && (peek || pointerInside)
               即：
                 精简且无 Peek → 永不显示
                 非精简 → 仅 pointerInside 时显示
                 Peek → 显示（无视 pointerInside）

showTrafficLights = showTabStrip   // 透明态与条同步；非透明不改
```

### 2.4 进出透明瞬间

| 时机 | 动作 |
|------|------|
| 进入透明 | 装监视；按**当前**鼠标是否在 frame 内立刻 `apply`（若已在窗外 → 条立即藏） |
| 退出透明 | 卸监视；标签条强制可见；交通灯可见；toolbar 仅按精简/Peek（不再看 pointer） |
| 透明中切精简 | 重算 `showToolbar`（精简则立刻藏栏；非精简则看 pointer） |
| 窗关闭 | 卸监视 |

### 2.5 与摸鱼叠加

| 场景 | 行为 |
|------|------|
| 摸鱼 Concealed（整窗 alpha=0） | 壳显隐可照算，用户看不见；现身后按 pointer 再刷一次 |
| 仅本方案藏壳 | 网页仍可见可点；条/栏没有 |

### 2.6 延迟（防抖）

| 项 | 定稿 |
|----|------|
| 移出 → 藏 | **可选** 80～120ms 延迟（避免擦边闪烁）；V1 建议 **有** |
| 移入 → 显 | **立即**（0ms） |
| 实现 | `performSelector:afterDelay:` / GCD；边沿翻转时 cancel 未执行的 hide |

---

## 3. 技术设计

### 3.1 为何仍用全局/本地鼠标监视

指针在窗外时本窗可能非 key，单靠 `NSTrackingArea` 不可靠（与摸鱼同理）。  
→ 复用或并列 **AfkMode 的 MouseRouter 模式**：`MouseMoved` + `NSMouseInRect(mouse, window.frame)`。

推荐：

- **方案 A（优先）**：抽公共 `BrowserWindowPointerMonitor`（进程级单例分发），摸鱼与透明藏壳都注册回调。  
- **方案 B（更快落地）**：透明藏壳自建轻量 Router（可与摸鱼各一份 monitor；数量少时可接受）。  

V1 允许 B，避免大重构；后续再合并为 A。

### 3.2 藏条实现（定稿）

| 手段 | 选用 |
|------|------|
| `removeTitlebarAccessoryViewController` | **不用**（进出频繁、易抖） |
| `tabStripAccessoryRoot.hidden = YES` + 高度约束 → 0 | **采用** |
| `tabStripAccessory.fullScreenMinHeight` / layout | 随高度约束更新；`layoutSubtree` + `scheduleTrafficLightPositioning` |
| 交通灯 | `setStandardWindowButtonsHidden:!showTabStrip`（仅透明态走此逻辑） |

退出透明时：`hidden=NO`、高度恢复 `effectiveStripHeight`、交通灯显示。

### 3.3 藏地址栏

继续走 `toolbar.hidden`，由统一方法计算（扩展现有 `applyToolbarVisibilityForCompactState` 或新建 `applyTransparentChromeAutoHideVisibility` 再调用 toolbar API）。

建议拆方法：

```text
- applyChromeVisibilityForCurrentMode
    非透明：applyToolbarVisibilityForCompactState；条可见；灯可见
    透明：按 §2.3 公式设条/灯/toolbar
```

`setCompactModeEnabled:` / Peek / 指针边沿 都调用同一入口，避免双路径。

### 3.4 模块与文件

| 区域 | 建议 |
|------|------|
| 新类（可选） | `SimpleBrowser/TransparentMode/BrowserTransparentChromeAutoHideController`：监视 + `pointerInside` + 通知 WC |
| 或挂 WC | WC 内直接注册 monitor（逻辑少时可先内聚，再抽类） |
| WC | enter/exit 透明启停；统一 `applyChromeVisibility…` |
| Makefile | 若新 `.m` 则链入 |

### 3.5 明确不改

- 窗口/页面透明、字色 JS  
- 右键拖窗  
- 摸鱼 alpha  
- 全屏禁透明  
- session 键（本能力随透明布尔，**无需**新 session 键）  

---

## 4. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| H1 | 作用域 | 仅透明模式 |
| H2 | 标签条 | 指针外藏、内显 |
| H3 | 地址栏精简 | 始终藏 |
| H4 | 地址栏非精简 | 与条同：外藏内显 |
| H5 | 交通灯 | 随标签条 |
| H6 | Peek | 可强制显 toolbar；Peek 中移出不藏栏 |
| H7 | 移出延迟 | V1 建议 80～120ms；移入立即 |
| H8 | 藏条手段 | hidden + 高度 0，不卸 accessory |
| H9 | 与摸鱼 | 正交 |
| H10 | 持久化 | 无独立键；随透明开关 |

---

## 5. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 擦边闪烁 | 移出延迟 + cancel |
| 条藏后难关透明 | Status Item；移入再点图标 |
| 标题栏高度残留空白 | 高度约束真正改为 0 + layout |
| 与摸鱼双 monitor | V1 可各一份；注意回调幂等 |
| Peek 与藏壳冲突 | H6：Peek 优先保栏 |

---

## 6. 验收标准

- [x] 透明 + 指针在内：标签条可见；非精简有地址栏；精简无地址栏  
- [x] 透明 + 指针外：标签条隐藏；地址栏隐藏（无论精简）  
- [x] 指针移回：条再显；非精简地址栏再显；精简仍无地址栏  
- [x] 透明中切精简：地址栏规则立即符合 §2.3  
- [x] Peek：精简+透明下 ⌘L 出栏；移出不强制关 Peek 栏  
- [x] 退出透明：条常显；toolbar 仅跟精简；监视已卸  
- [x] 摸鱼叠加无回归  
- [x] `make browser` 通过；移动鼠标无明显卡顿  

---

## 7. 后续扩展（非 V1）

- 顶缘热区「仅碰到屏幕顶才显条」  
- 用户可关「自动藏壳」偏好  
- 与摸鱼共用 PointerMonitor 单例  
