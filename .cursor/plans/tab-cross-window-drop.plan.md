---
name: 跨窗口拖放标签
overview: 把标签从窗口 A 拖到窗口 B 的标签条：B 显示空占位槽，松手后 extract+adopt 真迁移 WKWebView。基于已有多窗口与拖拽影子。设计见 docs/minimal-browser/tab-cross-window-drop-design.md。
todos:
  - id: xd-0-hit-test
    content: XD-0：AppDelegate/工具方法 browserWindowAtScreenPoint:excluding:（orderedWindows + strip 有效区）
    status: completed
  - id: xd-0-placeholder
    content: XD-0：BrowserTabDropPlaceholderView + Strip show/update/hideForeignDropPlaceholder + 插入下标 API
    status: completed
  - id: xd-0-moved-detect
    content: XD-0：源 Strip moved 时全局命中外窗并驱动目标占位；离开则 hide
    status: completed
  - id: xd-1-adopt-index
    content: XD-1：BrowserTabController/WindowController adoptTab:atIndex:（含 pinned 钳制）
    status: completed
  - id: xd-1-commit-move
    content: XD-1：松手 Foreign 分支 extract→adopt:atIndex:→刷新/关空源窗；清占位与 ghost
    status: completed
  - id: xd-1-verify-migrate
    content: XD-1：make browser；手测 A→B 滚动位置保留；拖桌面仍新窗；拖回 A 仍排序
    status: completed
  - id: xd-2-ghost-style
    content: XD-2：Foreign 时影子角标「移到此窗口」；松手短 fade；Reduce Motion
    status: completed
  - id: xd-2-docs
    content: XD-2：更新 design/development-plan 状态与 README；勾选验收项
    status: completed
isProject: true
---

# 跨窗口拖放标签 — Cursor 自动开发计划

> **依据**：[tab-cross-window-drop-design.md](docs/minimal-browser/tab-cross-window-drop-design.md)  
> **前置**：[`extractTabKeepingAlive`](SimpleBrowser/Tabs/BrowserTabController.m)、[`adoptTab`](SimpleBrowser/BrowserWindowController.m)、[`BrowserTabDragGhostController`](SimpleBrowser/Tabs/BrowserTabDragGhostController.m)、[`endReorderDrag`](SimpleBrowser/Tabs/BrowserTabStripView.m)  
> **构建**：每阶段 `make browser`。用户未要求时不要 commit。

## Goal

拖到另一 Meo 窗口标签条时显示空占位；松手将同一 `BrowserTab`/`WKWebView` 迁入目标窗指定下标。

## 行为定稿

1. 命中优先级：**外窗 strip > 本窗 strip > Detach 新窗**
2. 事件仍在源窗 tracking loop；由源 `moved` 做全局命中
3. 提交顺序：`extractTabKeepingAlive` → `adoptTab:atIndex:` → 源空则 close
4. **禁止**迁入后对同一 tab `loadURL` 重载
5. 首版不做 Esc、不拖到非 Meo 窗、不拖多标签

## Scope

| 做 | 不做 |
|----|------|
| XD-0～XD-2 | 跨应用 DnD、整页缩略预览 |
| 目标空心占位槽 | 目标条上克隆实体标签 |

---

## Phase XD-0：命中 + 占位

### xd-0-hit-test

`AppDelegate`（或 `BrowserTabDragSession` 工具）：

```objc
- (nullable BrowserWindowController *)browserWindowAtScreenPoint:(NSPoint)point
                                                       excluding:(nullable BrowserWindowController *)source;
```

用 `orderedWindows` / 窗口列表 + 各窗 `tabStripView` 的 strip 有效区（外扩 8pt）。

暴露 strip 有效区查询（可把 `stripEffectiveZoneInScreen` 改为 public/category）。

### xd-0-placeholder

- 新建 `BrowserTabDropPlaceholderView`（空心槽，ignores mouse）
- `BrowserTabStripView`：
  - `showForeignDropPlaceholderAtIndex:`
  - `updateForeignDropPlaceholderAtIndex:`
  - `hideForeignDropPlaceholder`
  - `insertionIndexForForeignDropAtScreenPoint:pinned:`
- 布局：在 index 处留出与 `lastLaidOutTabWidth` 相同空隙

### xd-0-moved-detect

在源 `moveReorderDragForItem:locationInWindow:` 中：

1. `foreign = browserWindowAtScreenPoint:excluding:self.windowController`
2. 有 foreign → 算 insertionIndex → 目标 `show/update`；本条合拢；清其它窗占位
3. 无 foreign → 所有外条 `hide`；走现有 InStrip / Detach

记录 `weak foreignStrip` + `foreignIndex` 供 ended 使用。

---

## Phase XD-1：真迁移

### xd-1-adopt-index

```objc
- (void)adoptTab:(BrowserTab *)tab atIndex:(NSUInteger)index;
```

pinned 钳制与本窗 `moveTab:toIndex:` 规则一致。无参 `adoptTab:` 可保留为 append/选中封装。

### xd-1-commit-move

`endReorderDrag` 增加分支：

```
if (foreignStrip && foreignIndex valid) {
  fade/remove ghost
  [sourceWC moveTabID:toWindow:atIndex:]  // extract + adopt
  hide placeholders
  return
}
// else existing InStrip / Detach
```

`BrowserWindowController`：

```objc
- (void)transferTabID:(NSUUID *)tabID
             toWindow:(BrowserWindowController *)destination
              atIndex:(NSUInteger)index;
```

内部：`stopObserving`（若选中）→ extract → destination adopt → refresh 双方。

### xd-1-verify-migrate

- A→B 页面状态保留
- 拖到桌面 = 新窗
- 拖回 A = 排序
- 最后一标签迁走后 A 关闭
- `make browser`

---

## Phase XD-2：打磨

### xd-2-ghost-style

- Foreign：角标「移到此窗口」，取消「新窗口」强调
- 松手：短 fade；Reduce Motion 立即 remove

### xd-2-docs

- 设计/开发计划状态 → 已实现
- 更新 ghost 设计 §6 D5 备注：由跨窗方案交付
- README 索引（若未加全）

---

## Done when

- [ ] 外窗悬停出现占位并跟插入点移动
- [ ] 松手真迁移，不重载页面
- [ ] 本窗排序与拖出新窗回归通过
- [ ] `make browser` 无警告

## Agent 规则

1. 按 todo 顺序推进并更新 status  
2. 勿扩大到跨应用 DnD  
3. 未要求勿 commit  

## 参考

- [tab-cross-window-drop-design.md](docs/minimal-browser/tab-cross-window-drop-design.md)
- [tab-drag-ghost.plan.md](.cursor/plans/tab-drag-ghost.plan.md)
- [multi-window.plan.md](.cursor/plans/multi-window.plan.md)
