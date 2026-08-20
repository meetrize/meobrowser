# 透明模式 — 右键拖拽移窗 — 交互与实现方案

> 目标：透明模式下，在网页内容区按住鼠标右键拖拽可移动整个浏览器窗口；普通右键点击（弹出上下文菜单）行为保持不变。  
> 状态：**已实现（RD-0～RD-2）**  
> 开发计划：[transparent-mode-right-drag-move-development-plan.md](transparent-mode-right-drag-move-development-plan.md)  
> 关联：[transparent-mode-design.md](transparent-mode-design.md) · 标签条已有 `performWindowDragWithEvent:` 左键拖窗先例

---

## 1. 可行性结论

| 问题 | 结论 |
|------|------|
| 能不能做？ | **能**。macOS 上用「位移阈值」区分点击 / 拖拽是成熟模式。 |
| 难不难？ | **中等偏低**。难点在 WKWebView 会先吃掉鼠标事件，以及拖拽后要拦住上下文菜单。 |
| 会不会破坏普通右键？ | **可控**。未超过阈值时完整放行；超过阈值才进入移窗并抑制菜单。 |
| 是否依赖私有 API？ | **不需要**。`NSEvent` 本地监视 + 改 `NSWindow.frame` 即可。 |

**一句话**：透明壳已无标题栏可拖区域，右键拖窗是合理补偿；用阈值区分点击与拖拽，技术上可落地。

---

## 2. 产品行为（定稿建议）

### 2.1 开启条件

仅当 **当前窗口 `transparentModeEnabled == YES`** 时启用。  
退出透明模式后立即卸监视器，恢复系统默认右键。

### 2.2 手势

| 用户动作 | 期望结果 |
|----------|----------|
| 右键按下 → 几乎不移动 → 抬起 | **普通右键**：WebKit 上下文菜单照常出现 |
| 右键按下 → 移动超过阈值 → 继续拖 | **移窗**：整窗跟随光标；**不出现**上下文菜单 |
| 左键拖 / 滚轮 / 双指滚动 | **不受影响** |
| 右键拖发生在非网页区（若仍有控件） | V1：**仅 content 网页区**（`WKWebView` / NTP 空白内容区） |

### 2.3 阈值（Hysteresis）

- 建议 **4～6 pt**（与 AppKit 拖拽手感接近；定稿 **5 pt**）。  
- 用屏幕坐标或 window base 坐标的欧氏距离：  
  `hypot(dx, dy) >= kThreshold` → 判定为拖拽。

### 2.4 不做什么（V1）

- 不改左键拖窗语义  
- 不做「按住右键悬停显示提示」  
- 不处理页内自定义右键拖（极少见；透明阅读场景可接受）  
- 不全局（非透明窗）启用  

---

## 3. 为什么不能「简单开 mouseDownCanMoveWindow」

| 方案 | 问题 |
|------|------|
| `mouseDownCanMoveWindow = YES` | 主要服务**左键**；且 WKWebView 子视图会抢 hit-test |
| 网页上盖透明 `NSView` 专吃右键 | 易挡滚动/左键；要精细 `hitTest:` 穿透，复杂度高 |
| 纯 JS `mousedown button===2` | 拿不到可靠的原生移窗，且拦菜单不稳 |

因此 V1 采用：**AppKit 本地事件监视 + 阈值状态机**（与标签条「空隙左键 `performWindowDragWithEvent:`」同层思路，但右键用手动改 frame 更稳）。

---

## 4. 推荐实现方案

### 4.1 架构

```
BrowserWindowController (transparent ON/OFF)
  └── BrowserTransparentModeController
        └── BrowserTransparentModeWindowDragMonitor   // 新建，可内嵌在 Controller)
              - install / uninstall local NSEvent monitor
              - 状态机：Idle → Armed → Dragging
              - 移窗 + 抑制菜单标志
```

挂在 `TransparentMode` 模块，避免污染全局 WebView；由 `setTransparentModeEnabled:` 进/出时 `install` / `uninstall`。

### 4.2 状态机

```
Idle
  RightMouseDown（命中本窗 web 内容区）
    → Armed（记录 down 点、window 初始 origin）

Armed
  RightMouseDragged 且 distance < threshold
    → 仍 Armed（事件可继续交给 WebKit，或暂存）
  RightMouseDragged 且 distance >= threshold
    → Dragging（设 suppressContextMenu=YES，开始跟手移窗）
  RightMouseUp
    → Idle（不抑制菜单，正常右键）

Dragging
  RightMouseDragged
    → 更新 window.frame.origin
  RightMouseUp
    → Idle（本次 RightMouseUp 对 WebKit 吞掉 / 菜单取消）
```

### 4.3 命中判定（只在网页区）

事件 `locationInWindow` 转 content 坐标，落在：

- 当前选中标签的 `WKWebView.frame`（相对 `contentContainer`），或  
- NTP 时 `contentContainer` 可见空白区（launchpad 在透明态通常已隐，仍按 content 区处理）

**排除**（若命中则忽略本手势）：其它 App 窗、本窗但非 content（理论上透明态已无 chrome）。

多窗：监视器用 `event.window == self.window` 过滤。

### 4.4 移窗算法

进入 `Dragging` 后：

```objc
NSPoint screenNow = /* 当前事件屏幕坐标 */;
NSPoint delta = { screenNow.x - lastScreen.x, screenNow.y - lastScreen.y };
NSRect frame = window.frame;
frame.origin.x += delta.x;
frame.origin.y += delta.y;
[window setFrame:frame display:YES]; // 或 setFrameOrigin:
```

说明：

- **优先手动改 `frame`**：`performWindowDragWithEvent:` 面向左键 down，右键拖上行为因系统版本可能不一致。  
- 坐标用 **屏幕空间** 累加，避免翻转坐标系踩坑。  
- 拖拽中可设 `NSCursor` 为箭头（可选，V1 可不改）。

### 4.5 不破坏普通右键（关键）

1. **阈值内抬起**：不设 `suppressContextMenu`，监视器 **原样返回 event**，WebKit `willOpenMenu:withEvent:` 正常走（现有 `BrowserWebView` 菜单定制保留）。  
2. **已进入拖拽**：  
   - `RightMouseUp`：监视器返回 `nil`（吞掉），降低菜单弹出概率；  
   - 若仍进入 `willOpenMenu:`：在 `BrowserWebView` 或 WC 查「本窗本次右键已拖拽」标志，**直接 `menu.cancelTracking` / 清空 menu**（双保险）。  
3. **Armed 阶段是否吞 Dragged**：  
   - 定稿 **A（推荐）**：阈值内不吞事件，让页面仍能收到微小移动（几乎无感）；  
   - 备选 B：阈值内也吞 Dragged，进一步降低页内右键拖选副作用（一般网页无右键拖）。

### 4.6 与现有代码的衔接点

| 位置 | 动作 |
|------|------|
| `BrowserWindowController setTransparentModeEnabled:` | ON → `installDragMonitor`；OFF → `uninstall` |
| `BrowserWebView willOpenMenu:withEvent:` | 若 `shouldSuppressContextMenuForTransparentDrag` → 取消菜单 |
| 全屏 | 透明态本就禁进；若日后组合，全屏中可禁用右键拖窗 |
| 置顶 | 无冲突；只改 origin，不改 `level` |

---

## 5. 备选方案（不推荐作 V1）

| 方案 | 评价 |
|------|------|
| content 上覆盖 `NSView`，`rightMouseDragged` 移窗，其它 `hitTest` 返回 nil | 穿透规则难写，易回归滚动 |
| 仅 JS `pointerdown` + `webkit.messageHandlers` | 菜单抑制与移窗手感差 |
| 改用中键 / 双指拖窗 | 偏离需求 |

---

## 6. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 拖拽后仍弹出菜单 | Up 吞事件 + `willOpenMenu` 双保险 |
| 阈值过大 → 右键变「钝」 | 5pt；可后续设为常量或偏好 |
| 阈值过小 → 误触移窗 | 同上；手测普通右键 |
| 微信读书等 Canvas 页 | 事件仍走 WKWebView，与 Canvas 绘制无关，**可用** |
| 多指 / 触控板右键等价 | `NSEventTypeRightMouse*` 覆盖；若来自 Ctrl+左键需单独评估（V1 可不做 Ctrl+左键拖窗） |
| 拖出屏幕 | 系统一般允许；可选贴边限制（V1 不做） |

---

## 7. 决策记录

| ID | 议题 | 定稿建议 |
|----|------|----------|
| RD1 | 作用域 | 仅透明模式 |
| RD2 | 点击/拖拽区分 | 5pt 阈值 |
| RD3 | 移窗 API | 手动 `setFrame`（屏幕 delta） |
| RD4 | 菜单抑制 | 吞 RightMouseUp + willOpenMenu 取消 |
| RD5 | Ctrl+左键当右键 | V1 不支持拖窗（仍可出菜单） |
| RD6 | 覆盖层方案 | V1 不做 |

---

## 8. 验收标准（V1）

- [x] 透明模式下，网页区右键拖拽可平滑移动窗口  
- [x] 透明模式下，网页区右键单击仍出现上下文菜单（链接/选区等）  
- [x] 拖拽移窗过程中及松手后不弹出上下文菜单  
- [x] 退出透明后，右键行为与进入前一致  
- [x] 左键选择文本、滚动、点击链接正常  
- [x] 多窗：仅当前透明窗响应，不带动其它窗  
- [x] `make browser` 通过  

---

## 9. 后续扩展（非 V1）

- 左键按住空白拖窗（更易误触）  
- 设置项：阈值、是否启用右键拖窗  
- Ctrl+左键等同右键拖  
- 拖窗时 Status Item 提示「拖动中」  
