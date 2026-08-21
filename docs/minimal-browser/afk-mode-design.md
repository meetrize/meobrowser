# 摸鱼模式（AFK / Hover-Conceal）— 交互与实现方案

> 目标：在标签栏 Chrome 动作区「透明」图标左侧增加「摸鱼模式」；开启后，鼠标移出本窗 `frame` 即整窗视觉消失；鼠标回到本窗区域则立刻恢复进入摸鱼前的显示形态（透明 / 非透明原样还原）。**V1 不做点击穿透。**  
> 状态：**首版已完成（AFK-0～AFK-2）**  
> 开发计划：[afk-mode-development-plan.md](afk-mode-development-plan.md)  
> Cursor 计划：[.cursor/plans/afk-mode.plan.md](../../.cursor/plans/afk-mode.plan.md)  
> 关联：[tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) · [transparent-mode-design.md](transparent-mode-design.md) · [multi-window-design.md](multi-window-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**鼠标一离开窗口，浏览器整窗在视觉上消失；鼠标一回来，刚才什么样还什么样。**

### 1.2 典型场景

- 透明模式叠在文档/聊天上阅读，同事走近时鼠标移开 → 窗内容不可见  
- 非透明普通浏览同样适用：移出即整窗隐去，移入即恢复 chrome + 网页  
- 与「置顶」组合：移回后若仍置顶则继续浮在上层  

### 1.3 为什么不需要「点击穿透」（需求修订）

移出后鼠标已不在本窗 `frame` 内，用户随后的点击落点也在窗外 → **命中的本就是其它 App / 桌面**，不经过本窗。  
因此 V1 **不**设置 `ignoresMouseEvents`，也 **不**把「点穿窗矩形下的下层内容」列为目标。

| 场景 | V1 行为 |
|------|---------|
| 鼠标在窗外点击 | 自然点到落点处的其它 UI（与是否摸鱼无关） |
| 隐身后面板矩形仍占位 | 仍可接收落到该矩形上的事件（极少：需把指针移回窗区才会点到）；**不**为穿透改事件模型 |
| 若未来要「看不见也能点穿原窗位置」 | 另开扩展（`ignoresMouseEvents` 或 `orderOut`），不进 V1 |

### 1.4 做什么（V1）

| 能力 | 说明 |
|------|------|
| Chrome 入口 | 标签条右侧，**透明图标左侧**新增「摸鱼模式」开关图标 |
| 开关语义 | Toggle：开 = 启用「移出隐藏 / 移入还原」监视；关 = 立刻保证窗口可见，并停止监视 |
| 移出隐藏 | 鼠标离开**本窗口 `frame`（屏幕坐标）** → 整窗**视觉**消失（`alphaValue = 0`） |
| 移入还原 | 鼠标再次进入本窗 `frame` → 恢复隐藏前的可见性；**不改变**透明/精简/置顶等布尔状态 |
| 透明可叠加 | 摸鱼开着时，若当前是透明模式，移入后仍是透明模式观感；非透明则恢复完整窗口 |
| 多窗隔离 | 每窗独立 `afkMode`；仅对本窗做隐藏/现身 |
| 会话 | 每窗 `afkMode` 写入 session（建议默认恢复） |
| 菜单镜像 | 「查看」菜单「摸鱼模式」可勾选（与图标同步） |

### 1.5 不做什么（V1）

- **不做点击穿透**（`ignoresMouseEvents` / 幽灵点穿）  
- 不做「移出后 `orderOut` / 缩到 Dock」为主路径（V1 用 `alpha=0` 保 frame，便于回入命中）  
- 不做全局热键 Boss Key（可后续扩展）  
- 不做「仅隐藏网页文字、保留壳」的半隐藏  
- 不做跨窗口「一键全摸鱼」  
- 不做自定义「移出延迟 / 渐隐动画」偏好（V1 即时；可选极短 fade ≤120ms）  
- 不全屏下启用摸鱼（与透明一致：**全屏禁止开启**；已开摸鱼再进全屏则强制关摸鱼并还原可见）  
- 不在摸鱼「已隐身」态依赖标签条退出（壳可能已随透明隐去；见 §3.3 出口）

### 1.6 设计原则

1. **状态正交**：摸鱼只管「现在要不要因鼠标位置而隐身」；**不**改写 `transparentMode` / `compactMode` / `alwaysOnTop`。  
2. **可逆优先**：隐身只叠加 `alphaValue`（及必要快照）；现身严格还原。  
3. **只藏显示、不改命中模型**：V1 不碰 `ignoresMouseEvents`。  
4. **回入侦测可靠**：App 失活、跨屏时仍能发现「指针又进了本窗 frame」→ 用全局鼠标监视（或等价 ActiveAlways 跟踪）；**不是**因为穿透收不到事件。  
5. **与 ChromeActions 同构**：注册表加一项，不新开平行按钮体系。  
6. **性能克制**：全局 monitor 仅在「摸鱼开启」时安装；回调里只做 frame 命中判断 + 状态切换。

---

## 2. 用户场景

### 2.1 开启摸鱼（非透明）

```
普通窗口浏览
  → 点标签条「摸鱼」（在透明左侧）
  → 图标呈「开」态；鼠标仍在窗内 → 窗口照常显示、可点
  → 鼠标移出窗口矩形 → 窗口立刻不可见
  → 鼠标移回窗口矩形 → 窗口立刻恢复为普通非透明完整界面
```

### 2.2 开启摸鱼 + 已在透明模式

```
已透明阅读
  → 再开摸鱼（或先摸鱼再透明，顺序不限）
  → 鼠标在窗内：继续透明观感（壳隐、文字在）
  → 鼠标移出：文字与窗一并不见
  → 鼠标移回：回到透明观感（不是变成有标签条的普通窗）
```

### 2.3 关闭摸鱼

```
摸鱼「开」态下再点图标（或菜单取消勾选）
  → 若当前正处于隐身：先现身（还原 alpha）
  → 卸载全局监视
  → 之后鼠标移出不再隐藏
```

### 2.4 与精简 / 置顶 / 透明

| 组合 | 行为 |
|------|------|
| 摸鱼 + 精简 | 正交；现身时仍是精简布局 |
| 摸鱼 + 置顶 | 允许；现身后仍置顶 |
| 摸鱼 + 透明 | **核心路径**；隐身不 `setTransparentModeEnabled:NO`，只叠 `alpha` |
| 先隐身再关透明 | 若仍摸鱼开：关透明按透明退出逻辑；隐身层若仍开着，保持 alpha=0 直至鼠标回入或关摸鱼 |

---

## 3. UI 入口

### 3.1 标签条 Chrome 动作区顺序（定稿）

```
[…][+]  [摸鱼][透明][精简][置顶]  ░trailing
```

| 项 | 定稿 |
|----|------|
| 位置 | **透明左侧**（最左 Chrome 动作） |
| SF Symbol（建议） | 关：`eye` / 开：`eye.slash`（或 `moon.zzz` / `eyeglasses`，实现时统一一款） |
| Tooltip | 「摸鱼模式」/「退出摸鱼模式」 |
| 行为 | Toggle；`on` 态高亮 |

### 3.2 菜单

「查看」菜单增加「摸鱼模式」勾选，与图标、`afkModeEnabled` 同步；`validateMenuItem` 读 key 窗状态。

### 3.3 隐身时的出口（重要）

| 出口 | V1 |
|------|----|
| 鼠标移回窗区 | **主路径**：自动现身 |
| 再点标签条图标 | 仅现身后可点；隐身时壳/窗不可见，不便依赖 |
| Status Item | **建议**：菜单增加「退出摸鱼模式」（与透明出口同构） |
| Esc | V1 **不**绑退出摸鱼（避免与网页冲突） |

---

## 4. 状态机

### 4.1 每窗布尔

| 属性 | 含义 |
|------|------|
| `afkModeEnabled` | 用户是否打开摸鱼监视 |
| `afkConcealed`（内部） | 当前是否因移出而处于视觉隐身态 |

`transparentModeEnabled` 等**独立**，隐身不翻转它们。

### 4.2 转移

```
                  开摸鱼
    Idle ──────────────────► Armed（监视中，未隐身）
                                │
                    鼠标出 frame │
                                ▼
                           Concealed（alphaValue ≈ 0）
                                │
                    鼠标入 frame │
                                ▼
                              Armed
                                │
                  关摸鱼 / 全屏强制关
                                ▼
                              Idle（保证可见）
```

### 4.3 开/关时强制不变量

- 进入 `Idle`：`afkConcealed=NO`，窗口 `alphaValue` 回到摸鱼快照（见 §5）  
- 进入 `Concealed`：不得修改透明模式布尔；不得卸 WebView；**不**改 `ignoresMouseEvents`  
- `Armed` 且鼠标已在窗外（开启瞬间鼠标已在窗外）：**立即**进入 `Concealed`

---

## 5. 核心技术设计

### 5.1 回入侦测：为何仍建议全局 Monitor

V1 **不做穿透**，隐身窗理论上仍可收到本窗上的 `mouseEntered`（`NSTrackingActiveAlways`）。  
但摸鱼场景常伴随 **App 失活、指针在其它 App 上移动**，仅靠本窗 tracking 不够稳。

→ **`Armed`/`Concealed` 仍使用 `NSEvent addGlobalMonitorForEventsMatchingMask:`**（`NSEventMaskMouseMoved`，必要时含 `LeftMouseDragged`）：

```text
NSPoint p = [NSEvent mouseLocation];
BOOL inside = NSMouseInRect(p, window.frame, NO);
```

多屏适用。`frame` 含标题栏（「窗口区域」= 整窗矩形）。  
备选：contentView `NSTrackingArea`（ActiveAlways）作辅助；V1 以全局监视为主即可。

### 5.2 隐身实现（定稿）

| 属性 | 隐身时 | 现身时 |
|------|--------|--------|
| `alphaValue` | `0` | 恢复快照值（通常 `1`） |
| `ignoresMouseEvents` | **不修改** | **不修改** |
| `orderOut` / `setIsVisible:NO` | **不用** | — |

理由：

- 只藏显示，符合「无须穿透」的修订需求  
- 保持 `frame` 在屏幕上，全局坐标命中简单  
- 不与透明模式的鼠标/拖窗逻辑抢 `ignoresMouseEvents`

可选：`animator.alphaValue` 极短过渡（≤120ms）。

### 5.3 快照

摸鱼模块在**首次进入 Concealed 前**（或开启 Armed 时）记录：

```text
afkAlphaValue
```

现身 / 关摸鱼时写回。透明模式继续管 opaque / backgroundColor / WebView drawsBackground 等；**摸鱼只碰 `alphaValue`**。

### 5.4 全局 Monitor 生命周期

| 时机 | 动作 |
|------|------|
| `afkModeEnabled` 变为 YES | 安装 global monitor（进程级单例分发优先） |
| 变为 NO / 窗关闭 | 卸载责任；现身 |
| App 失活 | **保持**监视（用户去点其它 App 是常态） |
| 多窗 | 每个窗独立 `afkConcealed`；事件里按各窗 `frame` 判断 |

### 5.5 与透明右键拖窗

隐身仅 `alpha=0`，不改 `ignoresMouseEvents`；指针不在窗内时本就不会拖到本窗。现身后右键拖窗行为不变。

### 5.6 性能

- Global `MouseMoved` 回调内仅 `NSMouseInRect` + 布尔比较；**仅在 inside 边沿变化时**调 `conceal`/`reveal`  
- 禁止在回调里 `evaluateJavaScript` / 重注样式  
- 禁止 timer 轮询鼠标  

---

## 6. 模块与文件

| 区域 | 路径 |
|------|------|
| 新模块（建议） | `SimpleBrowser/AfkMode/`：`BrowserAfkModeController`（监视 + conceal/reveal + alpha 快照） |
| Chrome 注册 | `BrowserChromeActionItem` 新 ID；`defaultItems` 插到透明前 |
| 窗口编排 | `BrowserWindowController`：`afkModeEnabled`、菜单、session、全屏拦截 |
| Status Item | `BrowserStatusItemController`：增加「退出/进入摸鱼」（至少「退出摸鱼」） |
| 会话键 | `BrowserWindowSessionAfkModeKey = @"afkMode"` |
| 构建 | `Makefile` 链入新 `.m` |
| 文档 | 本文 + development-plan + README 索引 |

---

## 7. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | 图标位置 | 透明**左侧**：摸鱼 → 透明 → 精简 → 置顶 |
| D2 | 隐身手段 | **仅** `alphaValue=0`（不用 orderOut；**不用** `ignoresMouseEvents`） |
| D3 | 回入侦测 | 全局 `NSEvent` + `window.frame` 命中 |
| D4 | 与透明关系 | 正交叠加；隐身不退出透明布尔 |
| D5 | 全屏 | 禁止开启；已开则进全屏时强制关摸鱼并现身 |
| D6 | 持久化 | 每窗 session `afkMode` |
| D7 | 隐身出口 | 鼠标移回为主；Status Item 可关摸鱼 |
| D8 | Esc | V1 不退出摸鱼 |
| D9 | 开启时鼠标已在窗外 | 立即 Concealed |
| D10 | 动画 | V1 可做极短 fade |
| D11 | 点击穿透 | **V1 明确不做**（移出后点击本就不在窗内） |

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 全局 monitor 权限 / 沙盒 | AppKit global monitor 常规可用；回调不读其它 App 内容 |
| 隐身后找不到窗口 | Status Item「退出摸鱼」+ 鼠标移回 frame 现身 |
| 隐身窗矩形仍占命中 | **接受**（V1 不做穿透）；指针在窗外时点击不受影响 |
| 与透明 alpha 叠加 | 摸鱼只快照/恢复自身写入的 alpha |
| Stage Manager / 多桌面 | 以当前 `window.frame` 屏幕坐标为准 |
| 边沿抖动 | 可选 30～50ms 去抖（V1 可先无） |

### 8.1 Dock 点击策略（V1 定稿）

**保持隐身优先**：Dock 激活不强制 reveal。鼠标移入窗区再现身。  
Status Item「退出摸鱼模式」可在隐身时操作。

---

## 9. 验收标准（V1）

- [x] 标签条顺序：摸鱼 → 透明 → 精简 → 置顶  
- [x] 摸鱼开 + 鼠标在内：窗口正常显示、可点  
- [x] 鼠标移出：整窗视觉不可见（不要求点穿窗矩形）  
- [x] 鼠标在窗外点击其它 App：行为正常（落点本就不在本窗）  
- [x] 鼠标移入：恢复；若开着透明则仍是透明观感；若未开透明则是完整窗  
- [x] 关摸鱼：立刻可见，移出不再隐藏  
- [x] 隐身前后 `ignoresMouseEvents` 未被摸鱼改写  
- [x] 多窗：仅操作窗受影响  
- [x] 全屏无法开启摸鱼  
- [x] 重启后 session 恢复 `afkMode`（若实现持久化）  
- [x] `make browser` 通过；鼠标移动无显著卡顿  

---

## 10. 后续扩展（非 V1）

- 移出延迟 / 渐隐时长偏好  
- 全局热键强制隐身/现身  
- **可选点击穿透**（`ignoresMouseEvents` 或 `orderOut`，让原窗矩形下可点）  
- Dock 点击强制现身选项  
- 菜单栏「当前摸鱼窗」指示灯  
