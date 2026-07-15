---
name: 标签拖拽跟随阴影
overview: 按 DG-0→DG-2 实现标签拖拽半透明影子跟手、条内排序/拖出新窗双模式视觉，以及松手吸附/飞向新窗动画；不改 WebView 真迁移语义。设计依据 docs/minimal-browser/tab-drag-ghost-design.md。
todos:
  - id: dg-0-ghost-module
    content: DG-0：新建 BrowserTabDragGhostController（borderless panel + 截图 NSImage + ignoresMouseEvents）
    status: completed
  - id: dg-0-callbacks
    content: DG-0：BrowserTabItemView 拖拽回调改为传 locationInWindow；阈值可改为欧氏距离
    status: completed
  - id: dg-0-strip-ghost-led
    content: DG-0：Strip Ghost-led——began 藏源标签/占位、moved 更新影子与插入索引、ended 提交/清理
    status: completed
  - id: dg-0-makefile-build
    content: DG-0：Makefile 链入新源文件；make browser 通过；条内拖拽排序仍正确
    status: completed
  - id: dg-1-strip-zone
    content: DG-1：条内有效区（strip bounds 外扩 8pt）；离开即 Detach 模式，松手离开条即新窗口（D1=B）
    status: completed
  - id: dg-1-dual-style
    content: DG-1：InStrip/Detach 双样式（透明度/阴影/缩放/「新窗口」角标）；拖出时条内合拢
    status: completed
  - id: dg-1-snap-animation
    content: DG-1：松手条内影子 120～160ms 吸附目标槽后消失再 commit reorder
    status: completed
  - id: dg-1-verify
    content: DG-1：make browser；手测条内排序、拖出条外成新窗、拖回条内可继续排序
    status: completed
  - id: dg-2-new-window-anim
    content: DG-2：CommitNewWindow 时影子飞向新窗标题栏并与 adopt 并行；Reduce Motion 时跳过位移动画
    status: completed
  - id: dg-2-polish-docs
    content: DG-2：打磨参数；更新 design 状态与 README；make browser 无警告
    status: completed
isProject: true
---

# 标签拖拽跟随阴影 — Cursor 自动开发计划

> **依据**：[tab-drag-ghost-design.md](docs/minimal-browser/tab-drag-ghost-design.md)  
> **构建**：每阶段结束后 `make browser`。  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）。

## Goal

拖过阈值后显示半透明「影子标签」跟手；区分条内排序与拖出新窗口；松手有吸附/落点反馈。真实 `WKWebView` 迁移逻辑保持不变（`extractTabKeepingAlive` + `adoptTab`）。

## 行为定稿（相对设计 §6）

| 决策 | 定稿 |
|------|------|
| D1 松手成新窗 | **离开标签条有效区**（strip bounds 外扩 8pt），不再仅用整窗 `frame` |
| D2 拖出时条内 | **合拢** |
| D3 Detach 角标 | **显示「新窗口」** |
| D4 Esc 取消 | **首版不做** |
| D5 跨窗拖入 | **首版不做** |

## Scope

| 做 | 不做 |
|----|------|
| DG-0～DG-2 | 跨应用拖放、多标签拖栈、整页缩略预览 |
| Ghost-led（源标签隐藏，影子跟手） | Hybrid 实体+影子双显 |
| 截图影子 | 复制 WKWebView |

## 关键代码锚点

- [`BrowserTabItemView.m`](SimpleBrowser/Tabs/BrowserTabItemView.m)：`kReorderDragThreshold`、tracking loop、`onReorderDrag*`
- [`BrowserTabStripView.m`](SimpleBrowser/Tabs/BrowserTabStripView.m)：`beginReorderDrag` / `moveReorderDrag` / `endReorderDrag`、窗外判定
- [`BrowserWindowController.m`](SimpleBrowser/BrowserWindowController.m)：`moveTabIDToNewWindow:screenPoint:`（WebView 真迁移）
- Makefile：显式列举 `SimpleBrowser/Tabs/*.m`

---

## Phase DG-0：影子骨架（Ghost-led）

### dg-0-ghost-module

新建 `SimpleBrowser/Tabs/BrowserTabDragGhostController.h/.m`：

- borderless、`opaque=NO`、`ignoresMouseEvents=YES` 的 `NSPanel`（或等价 window）
- `beginWithSourceView:grabPointInSource:`：对源视图 `bitmapImageRepForCachingDisplayInRect:` → `NSImage`
- `moveToScreenPoint:`：按 grab offset 定位
- `setDetachMode:(BOOL)`：预留样式切换（DG-0 可只设 α）
- `endAndRemove` / `animateToScreenRect:completion:`（DG-1/2 用）

### dg-0-callbacks

[`BrowserTabItemView`](SimpleBrowser/Tabs/BrowserTabItemView.h)：

```objc
onReorderDragMoved(NSPoint locationInWindow); // 替代仅 deltaX
```

阈值：保持 4pt；建议改为 `hypot(Δx, Δy) ≥ 4`。

### dg-0-strip-ghost-led

[`BrowserTabStripView`](SimpleBrowser/Tabs/BrowserTabStripView.m)：

1. `begin`：创建 GhostController；源 `draggingItem.hidden=YES`（或 α=0）；开始插入预览
2. `moved`：用 `locationInWindow` → screen / contentX；更新影子；**不再**靠 clamp 实体 frame 做跟手；插入索引改由指针投影到 `tabsContentView`
3. `ended`：移除影子；按区域 commit reorder 或 move-to-new-window；清 drag 状态

占位：DG-0 可用「源位隐藏 + 其它标签让位」（现有 `layoutTabsExcludingDraggedItem`）；显式空心槽可 DG-1 再加。

### dg-0-makefile-build

- Makefile 加入新 `.m`
- `make browser`
- 手测：条内拖排序正确；影子跟手

---

## Phase DG-1：双模式 + 条内吸附

### dg-1-strip-zone

- 计算「条内有效区」：`tabStrip`（或含 leading/trailing drag area）bounds → window → screen，**外扩 8pt**
- 指针在区内 → InStrip；否则 → Detach
- **松手成新窗**：与影子模式一致——不在有效区即 `didRequestMoveTabIDToNewWindow`（替换「仅窗外 frame」判定）

### dg-1-dual-style

| | InStrip | Detach |
|--|---------|--------|
| α | ≈0.88 | ≈0.78 |
| scale | 1.0 | 1.02～1.04 |
| shadow | 较弱 | 较强 |
| 角标 | 无 | 「新窗口」胶囊 |

拖出进入 Detach：条内合拢（其余标签不留大空隙，约瞬时或 ≤120ms）。

### dg-1-snap-animation

条内松手：影子 120～160ms ease-out 移到目标槽中心 → fade → 再 `didMoveTabID:toIndex:`（避免动画中途 reload 打断）。

### dg-1-verify

- 条内排序 / 拖出条外新窗 / 拖回条内继续排序
- 固定标签、最后一标签拖出语义不变
- `make browser`

---

## Phase DG-2：新窗落点 + 打磨

### dg-2-new-window-anim

- CommitNewWindow：先/并行创建并 `adopt` 新窗；影子飞向新窗标题栏中点（160～200ms）后 remove
- `accessibilityDisplayShouldReduceMotion`：跳过位移动画，瞬切消失

### dg-2-polish-docs

- 微调视觉参数
- 设计文档状态改为已实现；勾选验收项
- `make browser` 无警告

---

## Done when

- [ ] 阈值后影子跟手，源标签不双显
- [ ] 条内/拖出双模式可读；松手结果与模式一致
- [ ] 条内吸附动画；新窗落点动画（Reduce Motion 可关）
- [ ] WebView 真迁移仍不重新加载页面
- [ ] 单击选中、双击关闭、右键菜单无回归
- [ ] `make browser` 通过

## Agent 推进规则

1. 按 todo 顺序：下一个 `pending` → `in-progress` → `completed`
2. 勿实现 Esc 取消、跨窗拖入、整页缩略图
3. 用户未要求时不要 git commit

## 参考

- [docs/minimal-browser/tab-drag-ghost-design.md](docs/minimal-browser/tab-drag-ghost-design.md)
- 先例：[.cursor/plans/multi-window.plan.md](.cursor/plans/multi-window.plan.md)
