# 跨窗口拖放标签 — 交互与实现方案

> 目标：把标签从窗口 A 的标签条拖到窗口 B 的标签条；B 上出现**空占位槽**；松开后把同一 `BrowserTab` / `WKWebView` **真迁移**到 B（不重新加载页面）。  
> 状态：**已实现（XD-0～XD-2，2026-07-15）**  
> Cursor Plan：[.cursor/plans/tab-cross-window-drop.plan.md](../../.cursor/plans/tab-cross-window-drop.plan.md)  
> 开发计划：[tab-cross-window-drop-development-plan.md](tab-cross-window-drop-development-plan.md)  
> 前置：多窗口、`extractTabKeepingAlive` / `adoptTab`、[tab-drag-ghost-design.md](tab-drag-ghost-design.md)（影子跟手已落地）

---

## 1. 结论：可以实现

技术上可行，且与现有能力契合：

| 已有能力 | 跨窗拖放用法 |
|----------|----------------|
| `extractTabKeepingAlive:` | 源窗摘出 tab，保留 WebView |
| `adoptTab:` | 目标窗接入同一 tab 实例 |
| `BrowserTabDragGhostController` | 跟手影子可跨出源窗（floating panel） |
| 条内插入索引算法 | 目标条复用同一套 slot 计算 |

首版范围：**仅 MeoBrowser 自家窗口之间**；不做拖到 Finder / 其它 App。

---

## 2. 方案定位

### 2.1 做什么

| 能力 | 说明 |
|------|------|
| **跨窗悬停** | 拖到另一浏览器窗的标签条有效区时，进入 `DraggingDropOnForeignStrip` |
| **目标占位槽** | 目标条显示空心/半透明槽，指示插入位置 |
| **松手迁入** | `extract`（源）→ `adopt:atIndex:`（目标），WebView 不重建 |
| **模式优先级** | 外窗标签条 > 本窗标签条排序 > 空白桌面（成新窗） |

### 2.2 不做什么（首版）

- 不拖到非 Meo 窗口 / 桌面以外的系统 UI（桌面空白仍 = 新窗口，沿用现逻辑）
- 不支持一次拖多个标签
- 不把标签条占位做成完整「实体标签克隆」（空槽即可）
- 不改变 pinned 分区规则以外的排序语义

### 2.3 与现拖拽状态机的关系

```
Idle
  → DraggingInStrip（本窗排序）
  → DraggingDetach（离开任何标签条 → 将成新窗）
  → DraggingDropOnForeignStrip（指针在其它 Meo 窗标签条上）  ← 新增
       ├─ 松手 → CommitMoveToForeignWindow
       └─ 离开外条 → 回到 Detach 或回到本条 InStrip
```

设计决策 **D5（跨窗拖入）** 从「延期」升级为本方案交付目标。

---

## 3. 交互设计

### 3.1 典型流程

```
窗口 A：拖起标签（影子出现，源位隐藏/合拢）
  → 指针移出 A 的条
  → Detach 样式（「新窗口」角标）
  → 指针进入窗口 B 的标签条有效区（外扩 8pt，与本条一致）
  → 角标改为「移到此窗口」或隐藏新窗口角标
  → B 条上对应插入下标出现空占位槽；B 上其它标签让位
  → 松手
  → 影子吸附到 B 的占位槽 → extract(A) + adopt(B, index) → 刷新两窗
```

### 3.2 命中与优先级（定稿）

对每一帧指针屏幕坐标，按顺序判定：

1. **若落在任一其它 `BrowserWindowController` 的 strip 有效区** → Foreign drop  
2. **否则若落在源窗 strip 有效区** → InStrip reorder  
3. **否则** → Detach（松手 = 新窗口）

同一屏多窗重叠时：取 **最前（key / ordered）且 contains point** 的浏览器窗；可用 `NSWindow.windowNumberAtPoint` + 过滤 Meo 浏览器窗。

### 3.3 目标占位槽视觉

| 属性 | 规格 |
|------|------|
| 尺寸 | 与目标条当前等宽标签槽一致（`lastLaidOutTabWidth` × 条高） |
| 外观 | 圆角空心；填充 α≈0.12；描边虚线或 1pt accent α≈0.4 |
| 位置 | 插入下标对应的槽位中心 |
| 动画 | 出现/移动 ≤100ms；Reduce Motion 时瞬切 |
| 命中 | 占位符 `hitTest` 返回 nil，不抢事件 |

源窗在 Foreign 模式下：保持合拢（与 Detach 相同），表示「标签将被带走」。

### 3.4 影子在 Foreign 模式

| 项 | 行为 |
|----|------|
| 透明度 | ≈0.85（介于 InStrip 与 Detach） |
| 角标 | 「移到此窗口」或去掉「新窗口」 |
| 缩放 | 1.0（不暗示独立成窗） |

### 3.5 松手结果

| 指针位置 | 结果 |
|----------|------|
| 外窗标签条 | 迁到该窗指定下标；源窗若空则关闭 |
| 本窗标签条 | 本窗重排（现有） |
| 其它（桌面等） | 新窗口（现有真迁移） |

### 3.6 特殊情况

| 情况 | 行为 |
|------|------|
| 固定标签 | 目标插入下标钳制在 pinned 区；迁入后保持 `pinned` |
| 源窗唯一标签 | 迁出后源窗关闭（与拖出新窗一致） |
| 目标窗仅 NTP | 可插入任意合法下标；不强制替换 NTP |
| 拖到自己身上 | 不算 Foreign，走本窗排序 |
| 目标窗被挡住 | 仅当 strip 有效区实际命中（被挡则不进 Foreign） |
| 拖拽中目标窗关闭 | 取消 Foreign，退回 Detach |

### 3.7 右键菜单

「将标签移到新窗口」不变；本方案不新增「移到其它窗口」菜单（靠拖放）。

---

## 4. 架构设计

### 4.1 协调者

推荐 **轻量会话对象**（进程内单例或挂在 AppDelegate）：

```
BrowserTabDragSession（新建）
  - sourceStrip / sourceWindowController
  - draggingTabID
  - ghost（复用现有 Controller，或由 sourceStrip 持有并上报）
  - foreignTarget（weak BrowserTabStripView *）
  - foreignInsertionIndex
```

原因：源条的 tracking loop 在 A 的 `nextEventMatchingMask` 中，**事件仍由 A 收到**；B 不会自动收到 drag moved。必须由 A 在 moved 时做 **全局命中测试** → 通知 B 显示/更新占位。

### 4.2 命中其它窗口

```objc
+ (nullable BrowserWindowController *)browserWindowAtScreenPoint:(NSPoint)pt
                                                   excluding:(BrowserWindowController *)source;
```

实现要点：

- 遍历 `AppDelegate` 的 `_browserWindows`（或 `NSApp.windows` 过滤）
- 用各窗 `tabStripView` 的 `stripEffectiveZoneInScreen` 做 `NSPointInRect`
- 多命中时选 `window` 层级更高者（`NSApp.orderedWindows` 靠前）

### 4.3 目标条 API（新增）

```objc
// BrowserTabStripView
- (void)showForeignDropPlaceholderAtIndex:(NSUInteger)index;
- (void)updateForeignDropPlaceholderAtIndex:(NSUInteger)index;
- (void)hideForeignDropPlaceholder;
- (NSUInteger)insertionIndexForForeignDropAtScreenPoint:(NSPoint)screenPoint
                                                 pinned:(BOOL)pinned;
```

占位用独立轻量 `BrowserTabDropPlaceholderView`，不加入 `tabItems` 模型数组；仅影响布局空隙（与 `layoutTabsExcludingDraggedItem` 类似，在 index 处留槽）。

### 4.4 提交迁入

```objc
// BrowserTabController
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;

// BrowserWindowController
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;

// AppDelegate 或源 WindowController
- (void)moveTab:(BrowserTab *)tab
    fromWindow:(BrowserWindowController *)source
      toWindow:(BrowserWindowController *)destination
       atIndex:(NSUInteger)index;
```

顺序（必须）：

1. 目标先 `showWindow` / `makeKey`（可选）
2. `tab = [source.tabController extractTabKeepingAlive:…]`
3. `[destination adoptTab:tab atIndex:]` + `refreshTabsUI`
4. 源若 `tabs.count==0` → `close`；否则 `refreshTabsUI`
5. 清 Foreign 占位与 ghost

禁止：先关源窗再 extract；禁止对 migrated tab 再 `loadURL`。

### 4.5 源条 moved 伪代码

```
screen = …
foreign = browserWindowAtScreenPoint(excluding: self)
if (foreign) {
  setGhostMode foreign
  idx = foreign.tabStrip insertionIndex…
  [foreign.tabStrip show/update placeholder at idx]
  [self hide local slot / keep collapsed]
  clear detach-new-window intent
} else if (inOwnStrip) {
  [foreign hide placeholder]
  in-strip reorder preview…
} else {
  [foreign hide placeholder]
  detach mode…
}
```

松手：

```
if (foreign && placeholderIndex valid) commitMoveToForeign
else if (own strip) commitReorder
else commitNewWindow
```

---

## 5. 动画

| 事件 | 时长 |
|------|------|
| 外条占位出现 / 换槽 | ≤100ms |
| 松手影子吸附到目标槽 | 120～160ms（与本窗吸附一致） |
| Reduce Motion | 瞬切，仍真迁移 |

Foreign 提交动画完成后再 `extract/adopt`，或先 adopt 再瞬删影子（推荐：**先 adopt 保证状态正确，影子短 fade**——避免动画中途窗关闭边缘情况）。定稿：

- **优先正确性**：松手立即 extract/adopt，影子 fade 80ms（Reduce Motion 则立即 remove）。

---

## 6. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Tracking 只在源窗 | 由源 moved 全局命中，不依赖目标 mouseDragged |
| 两窗同时改 tab 列表 | 单次主线程提交，禁止重入 `dragEnding` |
| 目标布局与源宽度不同 | 占位用**目标** `lastLaidOutTabWidth` |
| KVO / loading 观察 | extract 前后 `stopObservingLoadingProgress`（源已有）；adopt 后 `refreshTabsUI` 重绑 |
| 委派与 Handler | adopt 后 `attachWebViewForTab` 重设 openURL/download handlers |

---

## 7. 验收标准

- [ ] A→B：悬停 B 条出现占位并随指针换槽
- [ ] 松手后标签在 B 指定位置；页面状态保留（滚动/表单/播放）
- [ ] A 无该标签；A 若空则关闭
- [ ] 拖到桌面仍开新窗；拖回 A 条仍为本窗排序
- [ ] 固定标签迁入后仍固定且落在 pinned 区
- [ ] 不拖到非浏览器窗误触发
- [ ] `make browser` 通过；Reduce Motion 无长动画

---

## 8. 分阶段（开发 / Plan）

| 阶段 | 内容 |
|------|------|
| **XD-0** | `browserWindowAtScreenPoint`；Foreign 命中；占位 view 显隐 |
| **XD-1** | 源 moved/ended 分支；`adoptTab:atIndex:`；真迁移提交 |
| **XD-2** | 影子 Foreign 样式、吸附/fade、边界与文档 |

---

## 9. 小结

跨窗拖放是「全局命中 + 目标空槽预览 + 已有 extract/adopt」的组合，**可以实现**且不必碰 WebKit 私有 API。核心新增是 **拖拽会话跨窗协调** 与 **目标条占位布局**；迁移正确性复用现有真迁移路径。
