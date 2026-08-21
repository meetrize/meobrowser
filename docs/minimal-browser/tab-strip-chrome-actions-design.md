# 标签栏右侧 Chrome 动作区 — 交互与实现方案

> 目标：在标签栏最右侧提供可扩展的窗口级图标区；首版交付「精简模式」与「窗口置顶」，并为后续图标预留统一挂载点。  
> 状态：**已实现（CA-0～CA-2，2026-08-20）**  
> 开发计划：[tab-strip-chrome-actions-development-plan.md](tab-strip-chrome-actions-development-plan.md)  
> Cursor 计划：[.cursor/plans/tab-strip-chrome-actions.plan.md](../../.cursor/plans/tab-strip-chrome-actions.plan.md)  
> 关联：[multi-tab-design.md](multi-tab-design.md) · [tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md) · [multi-window-design.md](multi-window-design.md) · [find-in-page-design.md](find-in-page-design.md)（ActionGroup 范式）

---

## 1. 方案定位

### 1.1 产品一句话

**标签栏右侧常驻窗口级开关；精简时只留标签 + 前进后退，置顶时窗口始终压在最前。**

### 1.2 为什么放在标签栏右侧（而非地址栏 ActionGroup）

| 维度 | 地址栏 ActionGroup（现有） | 本方案 Chrome 动作区 |
|------|---------------------------|----------------------|
| 语义 | 页面/站点工具（查找、下载、互联…） | **窗口壳**能力（精简、置顶、日后可能： denseness、分屏…） |
| 生命周期 | 精简模式会整行隐藏 | **必须始终可见**（否则无法退出精简） |
| 排序/溢出 | 可拖拽排序、可隐藏进「更多」 | 固定少量开关；默认不进地址栏溢出逻辑 |
| 视觉层级 | 第二行工具栏 | 标题栏 / 标签条同一行，与 `+` 并列 |

结论：**新建独立模块**，不要往 `BrowserAddressBarActionGroup` 塞窗口级开关。

### 1.3 做什么（V1）

| 能力 | 说明 |
|------|------|
| Chrome 动作区 | 标签条最右侧固定图标组 + 可扩展注册表 |
| 精简模式 | 隐藏整行地址栏（含前进后退刷新 + 地址栏 + 右侧 ActionGroup）；前进/后退迁到标签条左侧（交通灯右侧）；条高与间距收紧 |
| 窗口置顶 | 本窗 `window.level` 升为浮动级，始终压在普通窗口之上；图标呈「开」态 |
| 状态持久化 | 每窗随 `sessionDictionary` 保存/恢复 |
| 菜单镜像 | 「查看」菜单提供同等开关（可勾选），便于键盘党与可发现性 |
| 预留扩展 | 注册表 + 布局槽位，后续加图标不改标签条主布局算法 |

### 1.4 不做什么（V1）

- 不做应用级「全部窗口置顶」一键（每窗独立）
- 不做精简模式下把 ActionGroup 图标「挤」进标签条（会挤爆标签宽度）
- 不做精简模式下刷新按钮进标签条（用 ⌘R / 菜单；避免左侧过挤）
- 不做全局默认「启动即精简」（可后续用偏好；V1 仅窗口会话记忆）
- ~~不做拖拽排序 / 隐藏单个 Chrome 图标（数量少，固定顺序即可）~~ → **已由** [chrome-actions-customize-design.md](chrome-actions-customize-design.md) **承接（可拖改序 / 拖入 ⋯ / 图钉固定）**
- 不改变交通灯系统按钮本身，仅调整其旁侧留白与导航落点

### 1.5 设计原则

1. **可逆一眼可见**：精简 / 置顶的出口永远在标签条右侧，绝不随地址栏一起消失。  
2. **搬家不复制**：前进/后退只有一套 `NSButton` 实例，模式切换时改 superview，避免双份状态。  
3. **隐藏优于销毁**：地址栏行用 `hidden` + 高度约束收起，不 teardown WebView / 不卸菜单。  
4. **紧凑但不伤可读**：条高、inset、按钮尺寸有下限，交通灯与标签命中区不被压坏。  
5. **性能零轮询**：置顶只改 `level`；精简只改布局约束；无 timer、无 display-link。  
6. **多窗隔离**：状态挂在 `BrowserWindowController`，互不串扰。

---

## 2. 用户场景

### 2.1 精简模式 — 专注阅读 / 小屏

```
正常浏览（两行 chrome）
  → 点标签条右侧「精简」图标
  → 地址栏整行收起（含右侧工具图标）
  → 前进/后退出现在交通灯右侧；标签区略变宽（少了一行 chrome 高度）
  → 图标呈「开」态（filled / 高亮）
  → 再点一次 → 恢复完整工具栏，前进/后退回到地址栏左侧
```

### 2.2 精简模式下改网址

```
精简模式中需要跳转
  → ⌘L（或菜单「打开位置…」）
  → 地址栏行短暂展开并聚焦输入（「Peek」）
  → Return 导航后自动重新收起；Esc 取消编辑并收起
  → 精简开关本身保持「开」
```

若用户在 Peek 时点精简图标关闭精简：保持展开并退出精简（回到常态）。

### 2.3 窗口置顶 — 对照文档 / 跟课

```
对照另一应用阅读
  → 点「置顶」图标
  → 本窗压在其它普通窗口之上；图标呈「开」态
  → 再点取消；恢复 NSNormalWindowLevel
```

全屏时：系统全屏空间内置顶语义弱化；退出全屏后按保存的置顶状态重新应用 `level`。

### 2.4 多窗口

```
窗口 A 精简 + 置顶；窗口 B 常态
  → 互不影响
  → 重启后按各窗 session 恢复
```

---

## 3. 布局与视觉

### 3.1 常态（非精简）

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🔴🟡🟢  [Tab][Tab][Tab] … [▾?][+]     [精简][置顶][…]  ░  │  ← 标签条
├─────────────────────────────────────────────────────────────────────────────┤
│  ◀  ▶  ↻   │  地址栏 … │  [ActionGroup …]                 │  ← 工具栏行
├─────────────────────────────────────────────────────────────────────────────┤
│                              内容区                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

标签条结构（相对现网）：

```
[ leadingInset(交通灯) ][ tabsClip ][ overflow? ][ + ][ chromeActions ][ trailingDrag ]
```

现网 `trailingDrag` 宽 16pt；引入动作区后：

- `chromeActions` 位于 `+` 与 `trailingDrag` 之间  
- `trailingDrag` 保留 ≥ 8pt，保证右缘仍可拖窗  
- 标签可用宽度 = 总宽 − leading − chromeActions − add − overflow? − trailing − gaps

### 3.2 精简模式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🔴🟡🟢  ◀ ▶  [Tab][Tab]… [▾?][+]     [精简●][置顶][…]  ░  │
├─────────────────────────────────────────────────────────────────────────────┤
│                              内容区（贴标签条）                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

| 项 | 常态 | 精简 |
|----|------|------|
| 工具栏行（nav + 地址栏 + ActionGroup） | 显示 | **隐藏**（高度 0） |
| 前进 / 后退 | 工具栏左侧 | **标签条**、交通灯右侧 |
| 刷新 | 工具栏 | 隐藏（⌘R） |
| 标签条高度 | 36 pt | **32 pt** |
| 标签顶 inset | 5 pt | **5 pt**（与常态相同；高度 = 条高 − inset，底边贴齐） |
| 交通灯 leading | 78 pt | **72 pt**（略收，仍避开系统按钮） |
| 左侧导航簇宽 | — | 两枚 22×22 + spacing 2 ≈ **46 pt** |
| chrome 图标尺寸 | 22×22 | 22×22（不变，保证命中） |
| chrome 区间距 | 2 pt | 1 pt |
| `+` / 溢出按钮 | 24 / 22 | 22 / 20 |

**动画（可选、轻量）**：工具栏高度 0↔自然高，时长 **120–160 ms**，`allowsImplicitAnimation`；Reduce Motion 时瞬时切换。不动画 WebView 内容，避免卡顿感。

### 3.3 图标与状态

| ID | SF Symbol（关） | SF Symbol（开） | Tooltip 关 / 开 |
|----|-----------------|-----------------|-----------------|
| `compactMode` | `rectangle.topthird.inset.filled` 或 `menubar.arrow.up.rectangle` | 同符号 + `contentTintColor` 强调 / `*.fill` 变体 | 精简模式 / 退出精简模式 |
| `alwaysOnTop` | `pin` | `pin.fill` | 窗口置顶 / 取消置顶 |

视觉对齐现有工具栏按钮：`NSBezelStyleInline`、无边框、SF Symbol medium ~12–13 pt（条高更矮时略缩）。开态用 `NSControlStateValueOn` + template tint（与侧栏/互联圆点同一套强调色，避免另起主题）。

Hover：系统按钮默认即可；不必自定义 layer 阴影（性能与风格）。

### 3.4 交通灯垂直对齐

现有 `positionTrafficLightButtons` 按标签条垂直中心对齐。精简改条高后：

- 切换模式结束布局后调用 `scheduleTrafficLightPositioning`  
- 不新增私有 API；继续用现有 center-Y 算法

### 3.5 拖窗命中

| 区域 | 拖窗 |
|------|------|
| leading 空白（交通灯旁非按钮） | ✅ |
| 前进/后退按钮 | ❌（点击导航） |
| 标签本体 | ❌（选标签 / 拖标签） |
| chrome 图标 | ❌ |
| trailingDrag | ✅ |
| 标签条背景空隙 | ✅（现有 DragArea） |

---

## 4. 交互细则

### 4.1 精简模式 Toggle

| 操作 | 结果 |
|------|------|
| 点精简图标 / 菜单「精简模式」 | toggle；图标与菜单勾选同步 |
| Peek（⌘L）中再点精简关 | 退出精简并保持工具栏展开 |
| Peek 中 Esc | 取消编辑、收起工具栏、焦点回 WebView |
| Peek 中 Return | 提交导航（沿用现有地址栏逻辑）后收起 |
| 全屏进入/退出 | 保持精简布尔值；仅重布局 |

**⌘L 定稿**：精简开启时 = Peek（临时展开）；精简关闭时 = 聚焦地址栏（与现网一致，若尚无菜单项则 V1 补「打开位置…」⌘L）。

### 4.2 置顶 Toggle

| 操作 | 结果 |
|------|------|
| 开 | `window.level = NSFloatingWindowLevel`；可选 `collectionBehavior` 保持默认（不强制 AllSpaces，避免打扰） |
| 关 | `window.level = NSNormalWindowLevel` |
| 与子浮层关系 | 下载面板 / 查找条 / 补全面板 / 拖拽影子等 **相对父窗 orderFront**，或 level ≥ 父窗；避免置顶后面板被压在父窗下（见 §6.3） |

不使用 `NSStatusWindowLevel` / `NSPopUpMenuWindowLevel`（过高，干扰系统 UI）。

### 4.3 键盘与菜单

| 菜单项 | 位置 | 快捷键 V1 |
|--------|------|-----------|
| 精简模式 | 查看（可勾选） | 无（图标为主；可选后续 ⌘⇧.） |
| 窗口置顶 | 窗口（可勾选） | 无 |
| 打开位置… | 文件或查看 | ⌘L（Peek / 聚焦） |

菜单 `state` 绑定当前 key 窗口的布尔值；`validateMenuItem:` 仅对浏览器窗启用。

### 4.4 无障碍

- 每个图标 `toolTip` + `accessibilityLabel`（与 Tooltip 同文案）  
- 开态反映在 `accessibilityValue`（`"开"` / `"关"`）或 `accessibilitySelected`

---

## 5. 架构设计

### 5.1 模块边界

```
SimpleBrowser/ChromeActions/
  BrowserChromeActionItem.h/.m          // id / symbols / tooltip / toggle?
  BrowserTabStripChromeActionsView.h/.m // 右侧图标条 UI + 注册表
  （逻辑编排仍在 BrowserWindowController）
```

不新建独立 Controller（状态少）；`BrowserWindowController` 持有：

```objc
@property (nonatomic, getter=isCompactModeEnabled) BOOL compactModeEnabled;
@property (nonatomic, getter=isAlwaysOnTopEnabled) BOOL alwaysOnTopEnabled;
@property (nonatomic, strong) BrowserTabStripChromeActionsView *chromeActionsView;
@property (nonatomic, strong) NSLayoutConstraint *toolbarHeightConstraint; // 或 stack 内 hidden
@property (nonatomic, strong) NSStackView *toolbar; // 已有
@property (nonatomic, strong) NSStackView *navButtons; // 抽出强引用，便于搬家
```

### 5.2 标签条 API 扩展（`BrowserTabStripView`）

新增能力（保持现有 delegate 风格）：

| API | 作用 |
|-----|------|
| `chromeActionsView` 嵌入点 | strip 负责布局宽度与 `layoutTabs` 扣减 |
| `setLeadingNavigationView:` | 精简时传入装有 ◀▶ 的容器；常态传 `nil` |
| `compactMetricsEnabled` | 切换条高 / inset 常量组 |
| 回调或 target/action | 由 WindowController 直接设 chrome 按钮 action |

布局公式更新（精简开）：

```
leadingWidth = trafficLightInset + (navView ? navWidth + gap : 0)
middle = bounds.width - leading - chromeActionsWidth - add - overflow? - trailing - gaps
```

`layoutTabs` 已有 frame 布局；仅扩展宽度扣减与 leading 起点，**不**改为 Auto Layout 标签项（保持现网性能路径）。

### 5.3 前进/后退「搬家」

```
常态:  navButtons ∈ toolbar stack（address 行左侧）
精简:  navButtons ∈ tabStrip.leadingNavigationView
       toolbar.hidden = YES（或高度约束 = 0）
恢复:  逆操作；enabled 状态随 canGoBack/Forward 原逻辑刷新，无需重置
```

同一 `backButton` / `forwardButton` 指针；`reloadButton` 留在 `navButtons` 内但精简时整组若只含 ◀▶，则：

**定稿 D1**：精简迁移时 **只移动 back + forward**；`reloadButton` 留在工具栏行（随行隐藏）。实现上可用两个小容器，或精简前从 stack 临时移除 reload 的可见性——更简单：**navButtons 始终含三键，精简搬家后在 leading 容器里把 reload.hidden = YES**，恢复时再显示。

### 5.4 Chrome 动作注册表（扩展点）

```objc
@interface BrowserChromeActionItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy, nullable) NSString *onSymbolName; // 可选
@property (nonatomic, copy) NSString *toolTip;
@property (nonatomic, copy, nullable) NSString *onToolTip;
@property (nonatomic, assign) BOOL toggles; // YES = 开关型
@end

// BrowserTabStripChromeActionsView
- (void)reloadWithItems:(NSArray<BrowserChromeActionItem *> *)items;
- (nullable NSButton *)buttonForItemID:(NSString *)itemID;
- (void)setOn:(BOOL)on forItemID:(NSString *)itemID;
```

V1 `defaultItems`：

1. `compactMode`  
2. `alwaysOnTop`  

后续加图标：只改 `defaultItems` + WindowController wire，**不改** `BrowserTabStripView` 布局内核。若未来超过 ~4 个，再引入「⋯」溢出（V2），布局已预留 `chromeActionsView.intrinsicContentWidth`。

### 5.5 与地址栏 ActionGroup 的关系

| | AddressBar ActionGroup | TabStrip ChromeActions |
|--|------------------------|-------------------------|
| 精简时 | 随工具栏隐藏 | **始终显示** |
| 排序/隐藏偏好 | 有 UserDefaults | 无（固定） |
| 通知 | Visibility/Order 通知 | 仅按钮 action |

精简隐藏 ActionGroup **不**改其 UserDefaults 可见性偏好；退出精简后原样恢复。

---

## 6. 实现要点与性能

### 6.1 精简切换成本

| 做法 | 说明 |
|------|------|
| ✅ `toolbar.hidden = YES` + 垂直 stack 不占位 | AppKit StackView 对 hidden 子视图不分配空间 |
| ✅ 或 `heightConstraint.constant = 0` + `clipsToBounds` | 若 hidden 在某系统版仍占位则用此兜底 |
| ❌ removeFromSuperview 销毁行 | 会拆约束、丢第一响应者，成本高 |
| ❌ 每帧改 frame | 禁止 |

切换时调用一次：`layoutSubtreeIfNeeded` → `scheduleTrafficLightPositioning` → `tabStrip layoutTabs`。

### 6.2 条高变化

`BrowserTabStripHeight` 今日为 `extern const`。精简需可变高度时：

- 改为运行时属性 / 双常量 `BrowserTabStripHeightRegular` / `Compact`  
- accessoryRoot 高度约束更新  
- `collapseSystemTitlebarDecoration` 仍设 0，不变  

### 6.3 置顶与浮层 level

置顶开启后，检查并统一策略（实现阶段扫一遍）：

| 浮层 | 策略 |
|------|------|
| `BrowserDownloadPanel` | `orderFront:` 相对 key window；必要时 `level = window.level + 1` |
| 查找条 | 已在 contentContainer 内，无独立 window → 无问题 |
| 地址栏补全 panel | 跟随父窗；打开时 `orderFront` |
| 标签拖拽 ghost | 已 `NSFloatingWindowLevel`；置顶窗拖标签时 ghost `level = MAX(own, parent.level+1)` |
| Captcha 等 panel | 同 download |

**禁止**在 runloop 里反复 `orderFront` 抢焦点。

### 6.4 会话持久化

`sessionDictionary` 增补（缺省 = 关，兼容旧会话）：

```json
{
  "tabs": [...],
  "selectedIndex": 0,
  "pinnedCount": 0,
  "frame": "...",
  "compactMode": true,
  "alwaysOnTop": false
}
```

键名建议：`BrowserWindowSessionCompactModeKey` / `BrowserWindowSessionAlwaysOnTopKey`。  
`applySessionDictionary:` 在 UI 就绪后应用（先建窗再 set level / compact）。

### 6.5 多窗 / 性能约束

- 置顶窗数量不设硬顶（用户自控）；文档注明过多浮动窗可能挡桌面  
- 精简不改变 WebView 休眠预算  
- 图标刷新仅在 toggle / 恢复会话时，不 KVO window.level 轮询  

---

## 7. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | 精简是否带刷新进标签条 | **否**；仅 ◀▶；刷新用 ⌘R |
| D2 | 精简下如何改 URL | **⌘L Peek** 临时展开地址栏行 |
| D3 | 动作区放哪 | **标签条右侧**独立模块，不进 AddressBar ActionGroup |
| D4 | 置顶 level | **`NSFloatingWindowLevel`** |
| D5 | 状态范围 | **每窗口** + session 持久化 |
| D6 | 按钮实例 | **搬家同一套** back/forward，不双份 |
| D7 | 动画 | **可选 120–160ms** 高度；Reduce Motion 关闭 |
| D8 | 超多图标 | V1 固定排列；V2 再做 ⋯ 溢出 |

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 精简后左侧 leading 变宽，标签更易溢出 | 可接受；溢出菜单已存在；紧凑 metrics 略回收 inset |
| 置顶后面板被挡住 | §6.3 统一 level/order |
| Peek 与补全面板锚点 | Peek 展开后补全锚到地址栏，逻辑与常态相同 |
| 交通灯与 ◀▶ 重叠 | leadingInset 标定 + 手测 13/14/15；Retina 取整 |
| accessory 高度与 contentLayoutGuide 空隙 | 更新高度约束后依赖现有 guide 顶约束，手测无双缝 |

---

## 9. 验收标准（V1）

- [ ] 标签条右侧可见精简、置顶两图标；样式与现网工具栏协调  
- [ ] 开精简：地址栏整行消失；◀▶ 在交通灯右侧；内容区上移；再点恢复  
- [ ] 精简下 ⌘L Peek：展开→编辑→Return/Esc 行为正确  
- [ ] 开置顶：切换到其它 App 窗口后本窗仍可见于上；关后恢复  
- [ ] 多窗状态独立；重启后 session 恢复正确  
- [ ] 菜单勾选与图标状态同步  
- [ ] 标签拖拽 / 溢出 / 跨窗拖放 / 交通灯对齐不回归  
- [ ] `make browser` 通过；切换模式无可见卡顿（主观：瞬时或 ≤160ms）  
- [ ] 新增第三个 chrome 图标只需改注册表 + wire，不改标签布局公式主干  

---

## 10. 后续扩展（预留，不做 V1）

| 候选项 | 说明 |
|--------|------|
| 侧栏快捷开关 | 通知 / 助手侧栏一键 |
| 专注/勿扰 | 隐藏更多 chrome |
| 窗口透明度 | 需谨慎，易伤可读 |
| 动作区 ⋯ 溢出 | 图标 ≥ 5 时 |
| 全局默认精简偏好 | Settings |
| 精简下标题显示当前 URL 微缩 | 可选美化 |

扩展时只追加 `BrowserChromeActionItem` 并在 `BrowserWindowController` 接线即可。
