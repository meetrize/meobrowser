---
name: 标签栏 LRU + Favicon
overview: 按 TS-LRU-0→TS-LRU-4 实现标签栏 LRU 溢出（lastActiveTimestamp）、Safari 式渐进压缩（32pt favicon-only）、选中标签加宽、BrowserFaviconService 接入与溢出菜单 favicon。
todos:
  - id: ts-lru-0-constants
    content: TS-LRU-0：TabDisplayMode 枚举与新宽度常量（32/48/107/24/16）
    status: completed
  - id: ts-lru-0-display-mode
    content: TS-LRU-0：displayModeForWidth 档位判定；make browser 通过
    status: completed
  - id: ts-lru-1-favicon-view
    content: TS-LRU-1：BrowserTabItemView faviconView + pageURLString + 占位
    status: completed
  - id: ts-lru-1-three-tier-layout
    content: TS-LRU-1：Comfortable/Compact/Minimal 三档 layout + applyAvailableWidth 重写
    status: completed
  - id: ts-lru-1-title-truncate
    content: TS-LRU-1：按剩余宽动态截断标题；关闭按钮档位策略
    status: completed
  - id: ts-lru-2-lru-selection
    content: TS-LRU-2：LRU 可见集（mustVisible=selected+pinned）；废弃 visibleRangeForCount
    status: completed
  - id: ts-lru-2-uneven-width
    content: TS-LRU-2：updateTabFrames 非均匀宽度（选中 +bonus）；overflowTabIDs LRU 升序
    status: completed
  - id: ts-lru-2-max-visible
    content: TS-LRU-2：maxVisibleTabCountForWidth 改用 32pt 下界；strip 顺序排 frame
    status: completed
  - id: ts-lru-3-favicon-service
    content: TS-LRU-3：BrowserFaviconService 绑定 + DidUpdateNotification + WC navigation 刷新
    status: completed
  - id: ts-lru-3-overflow-menu
    content: TS-LRU-3：溢出菜单 favicon 行；showOverflowMenu 增强
    status: completed
  - id: ts-lru-4-acceptance
    content: TS-LRU-4：design §9 手测 + acceptance.md + 文档索引 + 路线图同步
    status: completed
isProject: true
---

# 标签栏 LRU 溢出 + Favicon + 渐进压缩 — Cursor 自动开发计划

> **依据**：[tab-strip-lru-favicon-design.md](docs/minimal-browser/tab-strip-lru-favicon-design.md) · [tab-strip-lru-favicon-development-plan.md](docs/minimal-browser/tab-strip-lru-favicon-development-plan.md)  
> **范围**：**TS-LRU-0～TS-LRU-4** · **已完成（2026-08-31）**  
> **构建**：每阶段结束后 `make browser`  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）

## Goal

优化标签栏三项体验：

1. **LRU 溢出**：最久未激活的标签进 ▾ 菜单，而非按位置隐藏右侧标签  
2. **Favicon**：每条标签 16×16 站点图标（复用 `BrowserFaviconService`）  
3. **渐进压缩**：宽度可瘦至 32 pt（仅 favicon）；选中 48 pt；非选中等宽 + 选中 +24 pt

## 行为定稿

| 决策 | 定稿 |
|------|------|
| D1 溢出排序 | `lastActiveTimestamp` 升序进菜单 |
| D2 必可见 | 当前选中 + 全部 pinned |
| D3 最小宽 | 32 pt（非选中）/ 48 pt（选中 Minimal） |
| D4 宽度分配 | 非选中等宽 baseW，选中 baseW + 24 |
| D5 Favicon | 16×16，`BrowserFaviconService`，首字母占位 |
| D6 溢出 UI | 保留 ▾ 菜单，不引入横向 scroll |
| D7 Pinned V1 | 仍显示标题；永不出条 |

## Scope

| 做 | 不做 |
|----|------|
| LRU 可见集算法 | 横向滚动主路径 |
| 三档 TabDisplayMode | Pinned Safari 式 32pt 仅图标（V2） |
| Favicon 接入 ICO-3 消费层 | 新 favicon 渠道 / 偏好开关 |
| 溢出菜单 favicon | 溢出菜单搜索 |
| 更新 adaptive-width 交叉引用 | 改 window.minSize |
| 非均匀宽度分配 | 宽度动画（V2） |

## 关键文件

| 区域 | 路径 |
|------|------|
| 标签 cell | `SimpleBrowser/Tabs/BrowserTabItemView.h/.m` |
| 标签条 layout | `SimpleBrowser/Tabs/BrowserTabStripView.h/.m` |
| Tab 模型 | `SimpleBrowser/Tabs/BrowserTab.h/.m`（只读 timestamp） |
| Favicon | `SimpleBrowser/Favicon/BrowserFaviconService.h/.m` |
| 窗口壳 | `SimpleBrowser/BrowserWindowController.m` |
| 溢出菜单行（新） | `SimpleBrowser/Tabs/BrowserTabOverflowMenuRowView.h/.m`（可选） |
| 参考实现 | `SimpleBrowser/TabOverview/BrowserTabOverviewCardView.m` |
| 文档 | `docs/minimal-browser/tab-strip-lru-favicon-*.md` |
| 构建 | `Makefile` |

## 实现顺序

### TS-LRU-0 — 常量与档位（~0.5 天）

1. 在 `BrowserTabItemView.h` 导出新宽度常量  
2. 新增 `BrowserTabDisplayMode` + `displayModeForWidth:isSelected:`  
3. `make browser`；现网行为不变  

**完成标志**：枚举与常量就位，档位函数可单测。

---

### TS-LRU-1 — TabItem UI（~2 天）

1. 添加 `faviconView`（16×16）+ `pageURLString` 属性  
2. 占位：首字母 / globe（抄 overview card 逻辑，抽共用 helper 可选）  
3. 重写 `applyAvailableWidth:` → 判定档位 → layout favicon / title / close  
4. 动态标题截断（扣 favicon + padding + close 宽）  
5. 手测：单 item 宽 200 / 80 / 32 pt 三档正确  

**完成标志**：无 strip 改动即可预览三档 UI。

---

### TS-LRU-2 — LRU + 非均匀宽度（~2 天）

1. 实现 `mustVisibleTabIDs`（selected ∪ pinned）  
2. 对其余 tab 按 `lastActiveTimestamp` DESC 贪心填充 budget  
3. `overflowTabIDs` 按 timestamp ASC  
4. 替换 `visibleRangeForCount` / index 滑动窗口  
5. `updateTabFrames`：逐 tab 分配宽（选中 +24）；**frame 顺序仍按 strip index**  
6. `maxVisibleTabCountForWidth:` 下界改 32 pt  
7. `syncWithTabs:` 传 URL 给 item  

**完成标志**：20 标签 LRU 手测通过；pinned 不出条。

---

### TS-LRU-3 — Favicon + 菜单（~1.5 天）

1. `setPageURLString:` → `BrowserFaviconService imageForPageURLString:triggerFetch:YES`  
2. 监听 `BrowserFaviconDidUpdateNotification`  
3. WC `didFinishNavigation` 刷新当前 tab item  
4. `showOverflowMenu:` 增加 favicon（`BrowserTabOverflowMenuRowView` 或 NSView item）  
5. 更新 `favicon-fetch-cache-design.md` ICO-3 消费层状态  

**完成标志**：github.com 等站点条上与菜单均有 favicon。

---

### TS-LRU-4 — 验收（~1 天）

1. design §9 全部勾选  
2. 更新 `acceptance.md`、`docs/README.md`、`professional-features-roadmap.md`  
3. 更新 `tab-strip-adaptive-width-design.md` §3 交叉引用  
4. 回归：拖拽 ghost、跨窗 XD、精简模式、Chrome 动作区、400×300 minSize  

**完成标志**：文档 synced，plan todos completed。

---

## 核心算法伪码（TS-LRU-2）

```objc
// 1. 必可见
mustVisible = { selectedID } ∪ pinnedIDs;

// 2. 候选按 LRU 降序
candidates = allTabs - mustVisible;
sort candidates by lastActiveTimestamp DESC (stable: strip index);

// 3. 贪心可见数（budget 含 overflow btn 占位）
visible = mustVisible;
for t in candidates:
    if width(visible ∪ {t}) <= budget at min 32pt each (+ selected bonus):
        visible.add(t);
    else:
        break;

overflow = allTabs - visible;
sort overflow by lastActiveTimestamp ASC;

// 4. 精确宽度
baseW = (budget - bonus - spacing) / visible.count;
for each tab in strip order:
    if tab in visible:
        w = (tab == selected) ? baseW + bonus : baseW;
        item.frame.width = w;
        [item applyAvailableWidth:w];
    else:
        item.hidden = YES;
```

---

## 手测清单

1. **LRU**：开 20 标签，最久未点的在 ▾；刚打开的若在选中则必在条上  
2. **菜单唤醒**：点冷门标签 → 回条上，另一冷门进菜单  
3. **压缩**：1200 pt → 400 pt，Comfortable → Compact → Minimal  
4. **Minimal**：32 pt 仅 favicon；选中 48 pt  
5. **Favicon**：github.com / 未缓存站首字母 → 图标  
6. **Pinned**：永不出 ▾  
7. **回归**：无溢出无 ▾；拖拽/ detach / 跨窗；精简模式 32 pt 条高  

---

## 性能约束

- LRU 排序 O(n log n)，仅在 layout / 选中变更时运行  
- Favicon 异步回调 **不** 调用 `updateTabFrames`，仅更新 icon view  
- 不 `reloadWithTabs:` 于每次 favicon 到达  
- 保持 frame 布局路径，不引入 Auto Layout 于 tab 宽度  

---

## 阶段提交建议（用户要求时）

| 阶段 | 建议 commit 标题 |
|------|------------------|
| TS-LRU-0 | `feat: 标签栏渐进压缩档位常量与 TabDisplayMode` |
| TS-LRU-1 | `feat: 标签项 favicon 槽位与三档 layout` |
| TS-LRU-2 | `feat: 标签栏 LRU 溢出与非均匀宽度分配` |
| TS-LRU-3 | `feat: 标签栏接入 Favicon 服务并增强溢出菜单` |
| TS-LRU-4 | `docs: 标签栏 LRU favicon 验收与文档同步` |
