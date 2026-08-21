# 标签栏 Chrome 动作区 — 图标排序 / 溢出固定（类 Chrome 插件）

> 目标：标签栏右侧**全部**窗口级能力（含原 ⋯ 内的自动滚动 / 滚动速度 / 窗口缩放）统一为可固定图标；除 ⋯ 外可拖拽改序；拖到 ⋯ 藏入菜单；⋯ 菜单为**单一列表**（文字 + 右侧图钉），交互对齐 Chrome 扩展工具栏固定。  
> 状态：**已实现（CP-0～CP-3）**  
> 开发计划：[chrome-actions-customize-development-plan.md](chrome-actions-customize-development-plan.md)  
> 关联：[tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) · [chrome-more-menu-design.md](chrome-more-menu-design.md) · 地址栏 `BrowserAddressBarActionGroup`（已有拖拽排序 / 隐藏偏好）

---

## 1. 需求理解

### 1.1 现状

```
[…][+]  [摸鱼][透明][精简][置顶][⋯]  ░trailing
```

- 条上四开关来自 `BrowserTabStripChromeActionsView`；顺序固定、不可藏。  
- ⋯ 弹出独立菜单项：自动滚动、滚动速度…、窗口放大↔缩小（**不能**出现在条上）。  
- 旧 CA 设计 V1 不做拖拽；本方案为定制 V2。

### 1.2 要做什么（产品一句话）

**所有 Chrome 动作（含自动滚动 / 滚动速度 / 窗口缩放）同一套「条上图标 ↔ ⋯ 菜单」模型：可拖改序、拖到 ⋯ 隐藏、菜单图钉固定；⋯ 菜单不再分两段。**

### 1.3 功能拆解

| # | 能力 | 说明 |
|---|------|------|
| F1 | 拖拽改序 | 条上可见的非 ⋯ 图标可横向改序；⋯ **永在最右** |
| F2 | 拖到 ⋯ 溢出 | 拖到 ⋯ 松手 → 从条上隐藏；菜单仍列出该项 |
| F3 | 单一菜单列表 | ⋯ 菜单**仅一段**：目录内全部可定制动作，每项「标题 \| 图钉」；**无**「工具下半区」分隔 |
| F4 | 图钉固定 / 取消固定 | 未在条上 → `pin` 钉上条；已在条上 → `pin.slash` 移出条 |
| F5 | 原菜单三项图标化 | `autoScroll` / `scrollSpeed` / `windowLayout` 进入 Catalog，与摸鱼等同等可固定、可拖 |
| F6 | 持久化 | 顺序 + 条上可见集合，App 级跨启动 |

### 1.4 明确不做（V1）

| 不做 | 原因 |
|------|------|
| 拖拽 ⋯ 或把 ⋯ 挪到中间 | 溢出锚点必须最右 |
| 菜单再拆「开关区 / 工具区」两段 | 与本需求冲突；统一列表 |
| 地址栏 ActionGroup 与本区打通 | 语义不同；偏好键独立 |
| 按窗口独立布局 | App 级 + 多窗通知（对齐地址栏） |
| 第三方插件图标 | 仅内置 Catalog |
| 窄窗自动溢出 | V1 仅用户主动藏；自动挤入后续 |

---

## 2. 信息架构

### 2.1 完整 Catalog（除 ⋯ 外均可定制）

| itemID | 菜单/默认标题 | SF Symbol（关/开） | toggles | 点击行为 |
|--------|---------------|--------------------|---------|----------|
| `afkMode` | 摸鱼模式 | `eye` / `eye.slash` | 是 | 现 `toggleAfkMode:` |
| `transparentMode` | 透明模式 | `cube.transparent` | 是 | 现 `toggleTransparentMode:` |
| `compactMode` | 精简模式 | `rectangle.topthird.inset.filled` | 是 | 现 `toggleCompactMode:` |
| `alwaysOnTop` | 窗口置顶 | `pin` / `pin.fill` | 是 | 现 `toggleAlwaysOnTop:` |
| `autoScroll` | 自动滚动 | `arrow.down.to.line.compact` / 同或 `pause` 类 | 是 | 现 `toggleAutoScrollFromMoreMenu:` |
| `scrollSpeed` | 滚动速度… | `gauge.with.dots.needle.67percent`（或 `slider.horizontal.3`） | **否** | 现 `openAutoScrollSpeedSettings:` |
| `windowLayout` | 窗口缩小 / 窗口放大 | `arrow.down.right.and.arrow.up.left` ↔ `arrow.up.left.and.arrow.down.right` | 视态 | 现 `toggleWindowLayoutZoomFromMoreMenu:`；全屏时禁用 |
| `moreMenu` | 更多 | `ellipsis` | 否 | 弹菜单；**不可定制、不可藏、不可拖** |

> Symbol 可在实现时微调，以 macOS 11+ 系统是否提供为准；缺符号则用文字回退（现有逻辑）。

### 2.2 条上布局

```
[+]  [用户可见且已排序的图标…][⋯]  ░trailing
```

**默认布局（七项全部在条上）：**

| 项 | 默认 |
|----|------|
| 默认 order | `afkMode` → `transparentMode` → `compactMode` → `alwaysOnTop` → `autoScroll` → `scrollSpeed` → `windowLayout` |
| 默认 hidden | **空**（新三项与旧四项一并显示在条上） |
| 允许 | 用户把任一项拖藏进 ⋯ / 图钉再钉回；条上可只剩 ⋯ |

默认条上：

```
[+]  [摸鱼][透明][精简][置顶][自动滚][速度][缩放][⋯]
```

### 2.3 ⋯ 菜单结构（定稿：单一列表）

```
  摸鱼模式                            📌/unpin
  透明模式                            …
  精简模式                            …
  窗口置顶                            …
  ☑ 自动滚动                          …     ← 开关类可勾选
  滚动速度…                           …     ← 非开关，无勾选
  窗口缩小                            …     ← 标题随大小窗态切换
```

- **无 separator、无「上半/下半」**。  
- 顺序 = `orderedIDs`（含已隐藏项）。  
- **点标题** = 与点条上图标同一 action。  
- **点图钉** = 只改是否在条上显示。

### 2.4 图钉语义

| 条上状态 | 右侧 Symbol | tooltip | 点击 |
|----------|-------------|---------|------|
| 已固定 | `pin.slash` | 从工具栏移除 | hidden=YES |
| 未固定 | `pin` | 固定到工具栏 | hidden=NO，按全局 order 插入可见序列 |

开关类（摸鱼、自动滚动等）：菜单标题侧 **勾选态** 与条上 `setOn:` 一致。  
`windowLayout`：标题在缩小态显示「窗口放大」，否则「窗口缩小」；全屏时标题行禁用（图钉仍可点，或一并禁用——**定稿：全屏仅禁用标题执行，图钉可用**）。  
`scrollSpeed`：无开态；点标题打开设置并聚焦滑杆。

---

## 3. 交互细则

### 3.1 拖拽改序（F1）

| 规则 | 定稿 |
|------|------|
| 拖源 | 条上任意非 ⋯ 按钮（含已钉上的自动滚 / 速度 / 缩放） |
| 阈值 | 移动 ≥ ~4pt 进入拖拽 |
| 落点 | 可见非 ⋯ 槽位之间；**不得越过 ⋯** |
| 松手 | 写回 order（只重排可见子序列，hidden 槽位保留） |
| 取消 | Esc / 无效区 → 恢复 |

### 3.2 拖到 ⋯（F2）

与前版相同：命中 ⋯ → 高亮 → 松手 hidden=YES；落在图标缝只改序。

### 3.3 图钉（F4）

钉回位置按全局 `orderedIDs` 相对序；允许清空到仅 ⋯。优先点图钉后菜单保持打开。

### 3.4 三项新图标的条上行为

| ID | 条上表现 |
|----|----------|
| `autoScroll` | 开态高亮；与控制器 `enabled` 同步；到底/滚轮打断关时按钮跟关 |
| `scrollSpeed` | 无高亮开关；点击打开设置（与菜单「滚动速度…」相同） |
| `windowLayout` | 小窗模式视为「开」态（高亮 + 可用 onSymbol）；点击在大小窗间切换；全屏 `enabled=NO` |

---

## 4. 数据模型与持久化

### 4.1 Catalog vs Layout

```
Catalog（代码）— 上表 7 个可定制 id + moreMenu
Layout（UserDefaults）
  orderedIDs: 七项全序（不含 moreMenu）
  hiddenIDs:  默认空（七项均可见）
```

```
visibleItems = orderedIDs.filter { !hidden }.map(catalog) + [moreMenu]
menuItems    = orderedIDs.map(catalog)   // 单一列表，每项带图钉
```

### 4.2 存储键

| Key | 说明 |
|-----|------|
| `BrowserChromeActionOrder` | id 数组 |
| `BrowserChromeActionHidden` | 隐藏 id 数组 |

### 4.3 迁移 / 缺省

| 情况 | 行为 |
|------|------|
| 无键 | order=默认七项序；hidden=空 |
| 旧用户仅有四项 order（若中间版本写过） | 合并：保留已存序，**追加**缺失的三 id 到末尾；新 id 默认可见（不进 hidden） |
| 目录再增新 id | 追加到 order 末尾；默认可见（除非该功能另行规定） |
| 未知 id | 从 order/hidden 剔除 |

### 4.4 会话

布局不进 window session；各窗功能态（是否正在自动滚、layoutMode 等）仍按现逻辑。

---

## 5. 交互漏洞与风险

| # | 问题 | V1 定稿 |
|---|------|---------|
| R1 | 拖拽误触 toggle | 阈值 + 拖拽中取消 click |
| R2 | 菜单行双热区 | 自定义 `NSMenuItem.view` |
| R3 | 点图钉关菜单 | 尽量保持打开；否则接受 |
| R4 | VoiceOver | 标题/图钉分 label |
| R5 | 条上图标变多挤标签 | 可接受；用户可拖进 ⋯；极窄窗依赖现有标签溢出 |
| R6 | 置顶 `pin` vs 图钉 | tooltip 区分「窗口置顶」/「固定到工具栏」 |
| R7 | 宽度变化 | `preferredWidth` + strip 约束 |
| R8 | `windowLayout` 标题动态 | 菜单打开时与条上 tooltip 同步刷新 |
| R9 | `scrollSpeed` 钉在条上是否冗余 | 允许；用户可再藏 |
| R10 | 查看菜单是否列新三项 | 若已有入口则保持；**不做图钉**；布局只在条+⋯ |
| R11 | 自动滚打断后条上态 | 现有 `didDisableHandler` 已刷新菜单逻辑 → 扩展为刷新 chrome 按钮 on 态 |

---

## 6. 技术设计

### 6.1 模块

| 模块 | 职责 |
|------|------|
| `BrowserChromeActionItem` + Catalog API | 七项元数据 + `moreMenu`；统一 `menuTitle` |
| `BrowserChromeActionLayoutStore` | order/hidden、默认值、迁移、通知 |
| `BrowserTabStripChromeActionsView` | 按 layout 渲染、拖拽、drop-⋯ |
| `BrowserChromeActionMenuRowView` | 单一菜单行：标题 + 图钉 |
| `BrowserWindowController` | `wire` 七项 action；`showChromeMoreMenu:` **只**建统一列表；同步 autoScroll/windowLayout 的 on/标题/enabled |

### 6.2 `showChromeMoreMenu:`（无两段）

```text
menu = empty
for id in orderedIDs:
    row = MenuRow(title, pinState, action)
    add item with view=row
popUp below ⋯
```

不再 append 独立的自动滚/大小窗 `NSMenuItem`。

### 6.3 拖拽

同前：指针跟踪复用 ActionGroup 模式；可见子序列重排写回完整 order。

### 6.4 按钮绑定（WC）

`wireChromeActionButtons` / `reloadChromeActionsFromStore` 末尾：

| ID | selector |
|----|----------|
| afk / transparent / compact / alwaysOnTop | 现有 toggle |
| autoScroll | `toggleAutoScrollFromMoreMenu:`（可改名 `toggleAutoScroll:`） |
| scrollSpeed | `openAutoScrollSpeedSettings:` |
| windowLayout | `toggleWindowLayoutZoomFromMoreMenu:` |
| moreMenu | `showChromeMoreMenu:` |

并在 autoScroll / layoutMode 变更时：

```text
[chromeActionsView setOn:forItemID:BrowserChromeActionAutoScrollID]
刷新 windowLayout 的 title/symbol/enabled
```

### 6.5 变更面

| 路径 | 变更 |
|------|------|
| `BrowserChromeActionItem.*` | 新常量 id；catalog 扩三项 |
| `BrowserChromeActionLayoutStore.*` | **新建** |
| `BrowserTabStripChromeActionsView.*` | layout 渲染 + 拖拽 |
| `BrowserChromeActionMenuRowView.*` | **新建** |
| `BrowserWindowController.m` | 统一菜单；三项 wire；态同步 |
| `Makefile` | 新源 |
| `chrome-more-menu-design.md` | 脚注：入口改为可固定图标，菜单结构见本文 |

---

## 7. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | ⋯ 可拖？ | **否**，永在最右 |
| D2 | 可定制范围 | Catalog 除 `moreMenu` 外 **全部七项** |
| D3 | 菜单是否两段 | **否**；单一列表 + 图钉 |
| D4 | 自动滚/速度/缩放 | **进入 Catalog**，可钉可拖可藏 |
| D5 | 三项默认可见？ | **是**；默认 hidden 为空，七项均在条上 |
| D6 | hidden 存法 | `BrowserChromeActionHidden` 数组 |
| D7 | 偏好范围 | App 级 + 通知 |
| D8 | 钉回位置 | 按全局 order 相对序 |
| D9 | 拖拽实现 | 指针跟踪（ActionGroup 模式） |
| D10 | 菜单行 | 自定义 `NSMenuItem.view` |
| D11 | 空条 | 允许仅 ⋯ |
| D12 | 查看菜单 | 不做图钉 |
| D13 | 全屏与 windowLayout | 禁用执行；图钉仍可用 |
| D14 | scrollSpeed | 非 toggle；点击开设置 |

---

## 8. 验收标准（V1）

- [x] 默认条上为七图标 + ⋯：摸鱼、透明、精简、置顶、自动滚动、滚动速度、窗口缩放  
- [x] ⋯ 菜单为**单一列表**七项，每项有图钉；无分段 separator  
- [x] 非 ⋯ 图标可拖改序；重启保持  
- [x] ⋯ 不可拖离最右  
- [x] 拖到 ⋯ 隐藏；图钉可钉回正确相对位置  
- [x] 条上「自动滚动」「滚动速度…」「窗口缩小」点击行为与原 ⋯ 菜单一致  
- [x] 自动滚开/关、大小窗切换时，条上图标态与菜单勾选/标题同步  
- [x] 全屏时窗口缩放不可执行（条上与菜单标题禁用）  
- [x] 短按不误拖；多窗布局同步  
- [x] `make browser` 通过  

---

## 9. 后续扩展（非 V1）

- 窄窗自动溢出  
- 菜单行 leading 小图标  
- 右键「从工具栏移除」  
- 「恢复默认布局」  
- 滚动速度用 popover 代替跳转设置  

---

## 10. 与旧文档关系

| 文档 | 关系 |
|------|------|
| `tab-strip-chrome-actions-design.md` | §1.4「不做拖拽」由本方案取代 |
| `chrome-more-menu-design.md` | ⋯ **不再**独占自动滚/大小窗；三者升为 Catalog 图标；菜单结构以本文为准 |
| `BrowserAddressBarActionGroup` | 仅参考拖拽/偏好模式 |
