# 标签栏 LRU 溢出 + Favicon + 渐进压缩 — 交互与实现方案

> 目标：多标签时按**最近激活时间（LRU）**决定谁进溢出菜单；标签条显示 **favicon**；宽度可渐进压缩至**仅图标**；当前选中标签略宽。  
> 状态：**TS-LRU-0～TS-LRU-4 已完成（2026-08-31）**  
> 开发计划：[tab-strip-lru-favicon-development-plan.md](tab-strip-lru-favicon-development-plan.md)  
> Cursor 计划：[.cursor/plans/tab-strip-lru-favicon.plan.md](../../.cursor/plans/tab-strip-lru-favicon.plan.md)  
> 关联：[tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md) · [multi-tab-design.md](multi-tab-design.md) · [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md) § ICO-3 · [tab-overview-design.md](tab-overview-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**标签栏像 Safari 一样越挤越瘦（favicon → 截断标题 → 仅图标），仍放不下时把最久未用的标签收进 ▾ 菜单——而不是把刚打开的标签藏起来。**

### 1.2 背景与问题

| 现状 | 问题 |
|------|------|
| 溢出按**位置滑动窗口**（`visibleRangeForCount`） | 右侧 / 新标签容易被挤进菜单，与使用频率无关 |
| 最小宽 **108 pt**，等宽分配 | 窄窗口下可见标签数少；无法「仅 favicon」 |
| 标签无 favicon | 多标签时辨识度差；与概览卡片 / 历史侧栏不一致 |
| `lastActiveTimestamp` 仅用于休眠 | 已有数据未参与条上可见性 |

### 1.3 做什么（V1）

| 能力 | 说明 |
|------|------|
| **LRU 溢出** | 溢出集合 = 最久未激活的标签；选中 + pinned 永不出条 |
| **Favicon** | 每条标签 leading 16×16 图标；走 `BrowserFaviconService` |
| **渐进压缩档位** | Comfortable → Compact → Minimal（32 pt favicon-only） |
| **选中略宽** | 非选中等宽；选中 + bonus（默认 +24 pt） |
| **溢出菜单增强** | 列表项带 favicon；按 LRU 升序；保留「显示全部标签…」 |
| **动态标题截断** | 按分配宽度扣 favicon / 关闭 / padding 后算可显字符 |

### 1.4 不做什么（V1）

- **不**改为主路径横向滚动（仍保留 ▾ 溢出菜单，见 §2.2）
- **不**抬高 `window.minSize`（维持 400×300，与 adaptive-width 一致）
- **不**重做拖拽 / 跨窗 / ghost（仅 layout 算法变更，拖拽仍按 strip 顺序）
- **不**为 pinned 做 Safari 式「仅图标固定宽」（V1 pinned 仍显示标题，但永不出条）
- **不**在 V1 做 Safari 15+ 的 scroll-snap 动画
- **不**新增 favicon 渠道（复用 ICO-0～ICO-2 管道；ICO-3 偏好开关仍延后）

### 1.5 设计原则

1. **使用频率优先于位置**：可见性由 `lastActiveTimestamp` 决定，而非 index 滑动窗口。  
2. **渐进压缩优于突然消失**：先瘦到 favicon-only，再 LRU 进菜单。  
3. **选中永远可见**：当前标签永不出条；从菜单选中后立即回条并更新时间戳。  
4. **Pinned 特权**：固定标签永不出条（与 Safari 一致）。  
5. **一次拉取处处复用**：标签 favicon 只读 `BrowserFaviconService`，不另起缓存。  
6. **性能零轮询**：layout 仅在 bounds / tab 集合 / 选中 / 时间戳变更时重算；favicon 异步回调局部刷新。

---

## 2. 交互设计

### 2.1 用户场景

#### 场景 A — 打开很多标签，窗口不变

```
用户已打开 20 个标签，窗口宽度 1200 pt
  → 条上显示最近用过的 ~15 个（等宽 + 选中略宽）
  → 最久未点的 5 个在 ▾ 菜单
  → 每个可见标签：favicon + 截断标题
```

#### 场景 B — 窗口变窄

```
用户拖窄窗口至 ~500 pt
  → 标签进入 Compact：标题更短，关闭按钮仅选中/悬停
  → 继续变窄至 ~400 pt（minSize）
  → 进入 Minimal：多数标签仅 favicon；选中仍 48 pt 可辨
  → 仍放不下 → LRU 最少的进菜单
```

#### 场景 C — 从菜单唤醒冷门标签

```
冷门标签在 ▾ 菜单中
  → 用户点击该菜单项
  → selectTab → lastActiveTimestamp = now
  → layout 重算：该标签回条上，另一 LRU 最低者进菜单
```

#### 场景 D — 刚打开的新标签

```
用户 ⌘T 新开标签（尚未切换走）
  → 若当前即选中：已在条上
  → lastActiveTimestamp 在创建/选中时已写入
  → 不会因「在右侧」 alone 被挤进菜单
```

### 2.2 为何保留溢出菜单而非 Safari 横向滚动

| 方案 | 优点 | 缺点 |
|------|------|------|
| **本方案：压缩 + LRU 菜单** | 400 pt 窄窗仍可用；与现架构一致；favicon-only 可放 10+ 标签 | 极多标签需点菜单 |
| Safari 横向滚动 | 标签永不隐藏 | 窄窗难操作；需重写 scroll 容器与 hit-test |

**定稿**：保留 ▾ 菜单；吸收 Safari 的**渐进压缩**与**选中加宽**，不引入 scroll 主路径。

### 2.3 交互流程图

```
窗口变窄 / 标签变多
        ↓
① 计算 stripMiddle 可用宽（扣 leading / + / chromeActions / trailing）
        ↓
② LRU 选出可见集合 V（必含 selected + pinned）
        ↓
③ 若 |V| == N → 无溢出，隐藏 ▾
   否则显示 ▾，overflow = 其余（按 lastActiveTimestamp 升序）
        ↓
④ 对 V 分配宽度：非选中等宽 baseW，选中 baseW + bonus
        ↓
⑤ 每标签 applyAvailableWidth → 档位 Comfortable / Compact / Minimal
        ↓
⑥ favicon + 动态截断标题 + 关闭按钮策略
```

---

## 3. 数值规范

### 3.1 宽度常量

| 常量 | 值 (pt) | 说明 |
|------|---------|------|
| `BrowserTabItemAbsoluteMinWidth` | **32** | Minimal 非选中：仅 favicon + 内边距 |
| `BrowserTabItemMinimalSelectedWidth` | **48** | Minimal 选中：略宽便于识别 |
| `BrowserTabItemCompactMaxWidth` | **107** | Compact 上限 |
| `BrowserTabItemComfortMinWidth` | **108** | Comfortable 下限（与现 `MinWidth` 对齐） |
| `BrowserTabItemMaxWidth` | **200** | 少标签时上限 |
| `BrowserTabActiveWidthBonus` | **24** | 选中相对 base 的加宽 |
| `BrowserTabFaviconSize` | **16** | 图标边长 |
| `BrowserTabFaviconLeadingPad` | **6** | favicon 左内边距 |
| `BrowserTabFaviconTitleGap` | **4** | favicon 与标题间距 |
| `kCloseAlwaysVisibleMinWidth` | **120** | ≥ 此宽：关闭常显（非选中亦可见） |
| `kTabSpacing` | **2** | 标签间距（不变） |
| `kOverflowButtonWidth` | **22** | ▾ 按钮（不变） |

### 3.2 显示档位（TabDisplayMode）

| 档位 | 宽度条件（非选中） | 内容 |
|------|-------------------|------|
| **Comfortable** | ≥ 108 | favicon + 标题（尾部 …）+ 关闭（≥120 常显，否则选中/悬停） |
| **Compact** | 56～107 | favicon + 短标题 + 关闭仅选中/悬停 |
| **Minimal** | 32～55 | **仅 favicon**；标题隐藏；关闭仅悬停；tooltip 仍两行 |

选中标签宽度 = `MAX(assignedWidth, MinimalSelectedWidth)` 当档位为 Minimal 时。

### 3.3 LRU 可见集算法

**输入**：标签数组 `tabs[]`（strip 顺序）、`selectedID`、`stripMiddleWidth`  
**输出**：`visibleIDs`、`overflowIDs`

```
MUST_VISIBLE = { selectedID } ∪ { tab.isPinned }

candidates = tabs \ MUST_VISIBLE
sort candidates by lastActiveTimestamp DESC   // 最近用过优先

budget = stripMiddleWidth - (needsOverflow ? overflowBtn : 0)

// 二分或递减贪心：求最大 k 使得 MUST + top-k candidates 在 budget 内放得下
// 宽度估算用 AbsoluteMinWidth（32）作下界快速判定；精确分配在 step ④

visible = MUST_VISIBLE ∪ top-k(candidates)
overflow = tabs \ visible
sort overflow by lastActiveTimestamp ASC     // 菜单：最冷门在上
```

**同 timestamp  tie-break**：保持 strip 原顺序（稳定排序）。

**新标签**：创建时 `lastActiveTimestamp = now`，与选中行为一致。

### 3.4 宽度分配（非均匀）

设可见数为 `v`，bonus 为 `B`，间距总和 `S = (v-1)*2`：

```
// 先假定全 Minimal 能否放下
if v * 32 + S <= budget:
    baseW = (budget - B - S) / v        // 选中另 +B
    selectedW = baseW + B
    clamp selectedW ≤ MaxWidth, inactive ≤ MaxWidth
else:
    // 必须溢出，visible 已在 LRU 步骤确定
    baseW = (budget - B - S) / v
    ...
```

每个 `BrowserTabItemView` 收到 `applyAvailableWidth:` 后自行判定档位并 layout 子视图。

### 3.5 标题截断

```
contentW = assignedWidth
         - faviconLeadingPad - faviconSize - faviconTitleGap
         - trailingPad - closeButtonWidth(if visible)

mode = displayModeForWidth(assignedWidth)
if mode == Minimal: hide title
else: titleLabel.stringValue = truncatedString(tabTitle, font 12pt, contentW)
```

截断实现：复用 `NSString` size 二分或 `NSMutableParagraphStyle` lineBreak tail truncation（与现 title field 一致）。

---

## 4. Favicon（ICO-3 标签栏消费）

### 4.1 数据流

```
BrowserTab.pageURLString
  → BrowserTabItemView.setPageURLString:
  → BrowserFaviconService imageForPageURLString:triggerFetch:YES
  → 命中内存/磁盘 → 立即 setImage
  → 异步完成 → BrowserFaviconDidUpdateNotification → 匹配 host 刷新
  → 失败：首字母占位（与 BrowserTabOverviewCardView 一致）
```

### 4.2 触发时机

| 时机 | 行为 |
|------|------|
| `reloadWithTabs:` / `syncWithTabs:` | 绑定 URL，triggerFetch=YES |
| `didFinishNavigation` | Silent 刷新（WC 已有顺手 fetch 可复用） |
| 标签标题/URL 变更 | 重新 bind |
| 溢出菜单弹出 | 菜单项 lazy bind favicon |

### 4.3 占位策略

1. 磁盘/内存命中 → 显示图标  
2. 无图标 → 域名首字母（10pt 圆角底，与 Launchpad cell 同色板）  
3. 无 URL / about:blank → 系统 `globe` SF Symbol  

### 4.4 不做

- 标签栏不单独 `fetchAndCache` 新渠道  
- 不在 layout 主路径同步读盘（仅 `cachedImageForHost:` 同步，miss 则占位 + 异步）

---

## 5. 溢出菜单

### 5.1 结构

```
[✓] [icon] GitHub — Pull Requests
    [icon] Stack Overflow
    [icon] 固定 · 文档
    ─────────────────
    显示全部标签…
```

### 5.2 行为

| 项 | 行为 |
|----|------|
| 排序 | `lastActiveTimestamp` **升序**（最久未用在上） |
| 选中标记 | 若选中标签在 overflow 中，该项 `state = on` |
| 固定前缀 | `"固定 · "` + 标题（与现逻辑一致） |
| Favicon | 16×16，与条上同源 |
| 底部分隔 | 「显示全部标签…」→ 标签概览（不变） |

### 5.3 实现选项

**推荐**：`NSMenuItem` + 自定义 `NSView`（`BrowserTabOverflowMenuRowView`）含 icon + label，避免纯 title 字符串。

---

## 6. 架构与文件

### 6.1 改动范围

| 文件 | 变更 |
|------|------|
| `BrowserTabItemView.h/.m` | favicon 视图、TabDisplayMode、`applyAvailableWidth:` 重写、layout 子视图 |
| `BrowserTabStripView.m` | LRU 可见集、非均匀宽度、`updateTabFrames` 重构 |
| `BrowserTabStripView.h` | 可选：`BrowserTabStripLayoutMetrics` 暴露调试 |
| `BrowserWindowController.m` | navigation 完成时通知 strip 刷新 favicon |
| `BrowserTabOverflowMenuRowView.m`（新，可选） | 菜单行 favicon |
| `tab-strip-adaptive-width-design.md` | 增补交叉引用，标注 min width 演进 |

### 6.2 不改

- `BrowserTab` 模型（已有 `lastActiveTimestamp`）  
- `BrowserTabController` 选中逻辑（已写 timestamp）  
- 拖拽 / ghost / 跨窗  
- `BrowserFaviconService` 渠道与缓存格式  

### 6.3 布局缓存失效条件

在现有 `invalidateTabLayoutCache` 基础上，增加：

- 任一 tab 的 `lastActiveTimestamp` 变更（选中切换）  
- favicon 异步到达（**不**触发 full relayout，仅 `item setNeedsDisplay` / icon view 更新）

---

## 7. 与拖拽 / 固定标签的协调

### 7.1 拖拽排序

- Strip **显示顺序**仍由用户拖拽决定（`tabItems` 数组顺序）  
- **可见性**由 LRU 决定，与 index 解耦  
- 拖拽中标签：`draggingItem` 仍 force visible，宽度跟随 layout  

### 7.2 Pinned

- `MUST_VISIBLE` 集合成员，永不出 overflow  
- 宽度参与 baseW 分配（V1 不单独固定 32 pt）  
- 仍显示 pin 图标 + 标题（档位规则同普通标签）  

---

## 8. 性能与边界

| 场景 | 策略 |
|------|------|
| 100+ 标签 | LRU 排序 O(n log n) 可接受；避免每次 keystroke relayout |
| 快速切换标签 | 仅 `updateTabFrames`；不 `reloadWithTabs:` |
| 休眠标签 | favicon 仍显示；与 overview 一致 |
| 无 URL 新标签页 | globe 占位；Launchpad 页无 host 时不 fetch |
| Reduce Motion | 宽度变化可 instant frame（V1 不做动画或 respect 系统设置） |
| 精简模式 strip 高度 | favicon 16 pt 在 31 pt 行高内垂直居中（与现 title 一致） |

---

## 9. 验收标准

### 9.1 LRU

- [x] 20 标签、宽窗：条上为最近使用的 N 个，非「最右侧 N 个」  
- [x] 从菜单选中冷门标签后，该标签出现在条上，另一冷门标签替换进菜单  
- [x] 新开并选中的标签不会被立即挤进菜单（除非物理宽度不足）  
- [x] Pinned 标签永不出 ▾ 菜单  

### 9.2 渐进压缩

- [ ] 窗口从 1200 pt 缩至 400 pt：可见标签经历 Comfortable → Compact → Minimal（待手测）  
- [x] Minimal 下非选中标签仅显示 favicon（宽 32 pt）  
- [x] 选中标签在 Minimal 下宽 48 pt，可辨认为当前页  

### 9.3 Favicon

- [ ] 已访问站点显示正确 favicon（如 github.com）（待手测）  
- [x] 未缓存站点先首字母占位，异步到位后替换  
- [x] 与标签概览卡片同源缓存，不重复下载  

### 9.4 回归

- [x] 无溢出时 ▾ 不占位  
- [ ] 拖拽排序 / 拖出新窗 / 跨窗拖放正常（待手测）  
- [x] 精简模式 + Chrome 动作区宽度扣减正确（逻辑未改路径）  
- [x] `window.minSize` 仍为 400×300  

---

## 10. 决策记录

| ID | 决策 | 理由 |
|----|------|------|
| D1 | 溢出按 LRU 而非 index 窗口 | 用户需求；避免新标签被藏 |
| D2 | 最小宽 32 pt favicon-only | 用户需求；对齐 Safari 压缩终点 |
| D3 | 选中 +24 pt bonus | Safari 式选中强调；可微调 |
| D4 | 保留 ▾ 菜单不引入 scroll | 现架构 + 窄窗可用性 |
| D5 | Pinned 永不出条 | Safari 语义 |
| D6 | Favicon 走现有 Service | ICO-3 范围；零新网络层 |
| D7 | V1 pinned 仍显示标题 | 改动最小；Safari 式 pin 仅图标可 V2 |

---

## 11. 文档与路线图

| 文档 | 动作 |
|------|------|
| [tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md) | §3 最小宽 108 → 补充「见 LRU 方案 32 pt 档」 |
| [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md) | ICO-3 标签栏条目链到本文 |
| [acceptance.md](acceptance.md) | 增加 TS-LRU 手测项 |
| [professional-features-roadmap.md](professional-features-roadmap.md) §3.3 | 标签栏 favicon 标记进行中 |

---

## 12. 后续（V2，不在 V1）

- Pinned 标签 Safari 式固定 32 pt 仅 favicon  
- 溢出菜单搜索/filter  
- 标签宽度变化 120 ms 动画（非 Reduce Motion）  
- 偏好：「溢出菜单排序 / 显示 favicon」开关  
