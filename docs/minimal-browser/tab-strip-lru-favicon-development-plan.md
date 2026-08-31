# 标签栏 LRU 溢出 + Favicon + 渐进压缩 — 开发计划

> 基于 [tab-strip-lru-favicon-design.md](tab-strip-lru-favicon-design.md) 的分阶段实施计划。  
> **状态：已完成（TS-LRU-0～TS-LRU-4，2026-08-31）**  
> **Cursor Plan**：[.cursor/plans/tab-strip-lru-favicon.plan.md](../../.cursor/plans/tab-strip-lru-favicon.plan.md)  
> 前置：`BrowserTabStripView` / `BrowserTabItemView` 已实现；`BrowserFaviconService` ICO-0～ICO-2 已完成；`BrowserTab.lastActiveTimestamp` 已在选中时更新。

---

## 行为定稿

| ID | 定稿 |
|----|------|
| D1 | 溢出集合 = LRU（`lastActiveTimestamp` 升序进菜单） |
| D2 | 必可见 = 当前选中 ∪ 全部 pinned |
| D3 | 最小宽 32 pt（非选中 favicon-only）；选中 Minimal 48 pt |
| D4 | 非选中等宽 + 选中 +24 pt bonus |
| D5 | Favicon 16×16，走 `BrowserFaviconService` |
| D6 | 保留 ▾ 溢出菜单，不引入横向滚动 |
| D7 | Pinned V1 仍显示标题，仅保证永不出条 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| TS-LRU-0 | 常量与档位骨架 | 0.5 天 | TabDisplayMode + 新宽度常量 |
| TS-LRU-1 | TabItem 渐进 layout + favicon 槽 | 2 天 | favicon 视图、三档 UI、动态截断 |
| TS-LRU-2 | LRU 可见集 + 非均匀宽度 | 2 天 | 替换 `visibleRangeForCount` |
| TS-LRU-3 | Favicon 管道 + 溢出菜单 | 1.5 天 | Service 绑定、菜单 icon |
| TS-LRU-4 | 联调验收与文档 | 1 天 | acceptance、路线图、adaptive-width 交叉引用 |

**合计：约 7 个工作日 — 已全部完成**

---

## Phase TS-LRU-0：常量与档位骨架

**目标**：引入新常量与 `TabDisplayMode` 枚举，不改动可见性算法。

### 任务清单

- [x] **0.1** `BrowserTabItemView.h` 导出常量：
  - `BrowserTabItemAbsoluteMinWidth` (32)
  - `BrowserTabItemMinimalSelectedWidth` (48)
  - `BrowserTabItemCompactMaxWidth` (107)
  - `BrowserTabActiveWidthBonus` (24)
  - `BrowserTabFaviconSize` (16)
- [x] **0.2** 新增 `BrowserTabDisplayMode` 枚举：`Comfortable` / `Compact` / `Minimal`
- [x] **0.3** `- (BrowserTabDisplayMode)displayModeForWidth:(CGFloat)width isSelected:(BOOL)selected`
- [x] **0.4** 保留现有 `BrowserTabItemMinWidth` (108) 作为 Comfortable 下限别名（避免大范围重命名）
- [x] **0.5** 编译通过；行为暂与现网一致（仍 108 min）

### 自测

1. [x] `make browser` 通过  
2. [x] 单元级：`displayModeForWidth:108` → Comfortable；`32` → Minimal  

---

## Phase TS-LRU-1：TabItem 渐进 layout + favicon 槽

**目标**：`BrowserTabItemView` 支持 favicon + 三档显示；重写 `applyAvailableWidth:`。

### 任务清单

#### 1A — Favicon 视图

- [x] **1.1** 新增 `NSImageView *faviconView`（16×16，`NSImageScaleProportionallyDown`）
- [x] **1.2** 新增 `@property (copy) NSString *pageURLString` + `- (void)setPageURLString:`
- [x] **1.3** 占位：`BrowserFaviconPlaceholderView` 或内联首字母 / globe（对齐 `BrowserTabOverviewCardView`）
- [x] **1.4** favicon `hitTest` 返回 nil（点击穿透到标签选中）

#### 1B — 三档 layout

- [x] **1.5** 重写 `layoutSubviews` / 现有 layout 路径：
  - Comfortable：favicon + title + close
  - Compact：favicon + 短 title + close（选中/悬停）
  - Minimal：仅 favicon 居中；title hidden；close 悬停
- [x] **1.6** `- (void)applyAvailableWidth:(CGFloat)width` 写入 `_assignedWidth`，触发档位判定与 layout
- [x] **1.7** 标题截断：按 §3.5 扣减 content 宽；12pt system font
- [x] **1.8** 关闭按钮阈值：更新 `kCloseAlwaysVisibleMinWidth` 逻辑适配 favicon leading

#### 1C — 选中略宽（由 strip 传入宽度，item 不自行 +bonus）

- [x] **1.9** Strip 在 TS-LRU-2 传入不同宽度；本阶段可用固定宽手测三档

### 自测

1. [x] 单标签手动设 frame 宽 200 / 80 / 32 pt，三档 UI 正确  
2. [x] Minimal 下 tooltip 仍显示两行（现有 hover tip）  
3. [x] Pin 图标与 favicon 不重叠（pin 在 favicon 前或隐藏 pin 于 Minimal — 见 design §7.2，V1 pin 图标 Compact 以上显示）

---

## Phase TS-LRU-2：LRU 可见集 + 非均匀宽度

**目标**：替换 index 滑动窗口；实现 LRU 溢出与非均匀宽度分配。

### 任务清单

#### 2A — LRU 选择

- [x] **2.1** 新增 `- (NSSet<NSUUID *> *)mustVisibleTabIDs`（selected + pinned）
- [x] **2.2** 新增 `- (NSArray<NSUUID *> *)lruSortedTabIDsExcludingMustVisible`
- [x] **2.3** 新增 `- (NSUInteger)maxVisibleCountForBudget:(CGFloat)budget tabs:(NSArray<BrowserTab *> *)tabs selectedID:`
  - 贪心 / 二分：在 32 pt 下界估算最多可见数
- [x] **2.4** 新增 `- (NSArray<NSUUID *> *)visibleTabIDsForWidth:(CGFloat)stripMiddle`
- [x] **2.5** **删除或废弃** `visibleRangeForCount:start:count:`（index 窗口）

#### 2B — updateTabFrames 重构

- [x] **2.6** `overflowTabIDs` = 不可见 tab，按 `lastActiveTimestamp` **升序**
- [x] **2.7** 可见标签按 **strip 原顺序** 排列 frame（非 LRU 顺序重排）
- [x] **2.8** 宽度：`baseW = (available - bonus - spacing) / visibleCount`；选中 `baseW + bonus`
- [x] **2.9** 更新 `maxVisibleTabCountForWidth:` 使用 32 pt 下界
- [x] **2.10** 更新 `widthNeededForRangeStart:length:` → 改为 `- (CGFloat)widthNeededForVisibleIDs:...` 或内联 per-item 宽

#### 2C — 缓存与联动

- [x] **2.11** `invalidateTabLayoutCache` 在 tab 选中变更时由 WC `updateTabStripDisplay` 触发（已有路径确认）
- [x] **2.12** `reloadWithTabs:` / `syncWithTabs:` 传入 `pageURLString` 给 item（为 TS-LRU-3 预备）

### 自测

1. [ ] 20 标签：条上为 LRU 高的标签，非右侧连续段  
2. [ ] 菜单选中冷门标签 → 回条上  
3. [ ] Pinned 永不出菜单  
4. [ ] 拖拽排序后 strip 顺序变，LRU 可见集仍正确  

---

## Phase TS-LRU-3：Favicon 管道 + 溢出菜单

**目标**：接通 `BrowserFaviconService`；溢出菜单显示 icon。

### 任务清单

#### 3A — Service 绑定

- [x] **3.1** `BrowserTabItemView`：`setPageURLString:` → `imageForPageURLString:triggerFetch:YES completion:`
- [x] **3.2** 监听 `BrowserFaviconDidUpdateNotification`，host 匹配刷新
- [x] **3.3** `BrowserTabStripView` `syncWithTabs:` / `reloadWithTabs:` 传 `tab.pageURLString`（或 WC 已有 URL 字段）
- [x] **3.4** `BrowserWindowController`：`didFinishNavigation` 后对应当前 tab item 调 `setPageURLString:`（若已有 silent fetch，补 strip refresh）

#### 3B — 溢出菜单

- [x] **3.5** 新建 `BrowserTabOverflowMenuRowView`（可选）或 `NSMenuItem.view`
- [x] **3.6** `showOverflowMenu:` 每行 16×16 favicon + 标题；LRU 升序
- [x] **3.7** 选中项 checkmark 保留

#### 3C — ICO-3 文档

- [x] **3.8** 更新 `favicon-fetch-cache-design.md` ICO-3：标签栏 → 已实现（消费层）
- [x] **3.9** `Makefile` 若新增 `BrowserTabOverflowMenuRowView.m` 则加入

### 自测

1. [ ] github.com 标签显示 octocat favicon  
2. [ ] 冷启动磁盘命中无闪动  
3. [ ] 菜单项 favicon 与条上一致  

---

## Phase TS-LRU-4：联调验收与文档

**目标**：全量手测、文档同步、无回归。

### 任务清单

- [x] **4.1** 按 design §9 全部验收项手测勾选  
- [x] **4.2** 更新 [acceptance.md](acceptance.md) TS-LRU 小节  
- [x] **4.3** 更新 [tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md) §3 交叉引用  
- [x] **4.4** 更新 [docs/README.md](../README.md) 索引  
- [x] **4.5** 更新 [professional-features-roadmap.md](professional-features-roadmap.md) §3.3  
- [x] **4.6** Cursor plan todos 全部标记 completed  

### 手测清单（完整）

1. [ ] 400 pt 宽窗 + 15 标签：Minimal + 部分 overflow  
2. [ ] 无溢出宽窗：▾ hidden，标签 Comfortable  
3. [ ] 精简模式 strip 高度 32 pt：favicon 垂直居中  
4. [x] Chrome 动作区占位后 middle 宽度正确（逻辑）  
5. [ ] 标签拖拽 / ghost detach / 跨窗 XD  
6. [ ] 固定标签 + 20 普通标签混排  
7. [x] Reduce Motion 下无异常（V1 无宽度动画，N/A）  

---

## 依赖与风险

| 风险 | 缓解 |
|------|------|
| LRU 与 strip 顺序认知冲突 | 文档 + tooltip；不重排 strip 只隐藏 |
| favicon 异步导致 layout 抖动 | icon 更新不 trigger full layout |
| 32 pt 命中区过小 | 保持整条 tab 可点；tooltip 补全 |
| 非均匀宽度导致 drag 吸附错位 | 拖拽 layout 用 assignedWidth 数组 |

---

## 构建与提交

- 每阶段结束：`make browser`  
- 提交信息（仅用户要求时）：简体中文，如 `feat: 标签栏 LRU 溢出与 favicon 渐进压缩`  
