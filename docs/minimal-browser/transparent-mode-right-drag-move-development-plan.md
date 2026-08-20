# 透明模式右键拖拽移窗 — 开发计划

> 基于 [transparent-mode-right-drag-move-design.md](transparent-mode-right-drag-move-design.md)。  
> 前置：透明模式 TM-0～TM-2 已可用。  
> 状态：**RD-0 / RD-1 / RD-2 已完成**  
> Cursor 计划：[.cursor/plans/transparent-mode-right-drag-move.plan.md](../../.cursor/plans/transparent-mode-right-drag-move.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 作用域 | 仅 `transparentModeEnabled` |
| 手势 | 右键拖 ≥ 5pt → 移窗；&lt; 5pt 抬起 → 正常右键菜单 |
| 移窗 | 屏幕坐标 delta 更新 `window.frame` |
| 抑菜单 | 吞 RightMouseUp + `willOpenMenu` 双保险 |
| Ctrl+左键 | V1 不作为拖窗 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase RD-0 | 监视器骨架 | 完成 | install/uninstall；Armed 状态；日志/断点可测 |
| Phase RD-1 | 移窗跟手 | 完成 | 超阈值后平滑移窗 |
| Phase RD-2 | 右键菜单兼容 | 完成 | 单击菜单正常；拖后无菜单；退出透明还原 |

**首版交付：RD-0 + RD-1 + RD-2。**

---

## Phase RD-0：事件监视骨架

**目标**：透明进出时挂/卸本地监视器；能区分 down / drag / up；尚未移窗也可。

### 任务清单

1** 在 `TransparentMode` 增加拖窗监视职责（独立小类或扩 `BrowserTransparentModeController`）
2** `setTransparentModeEnabled:YES` → `install`；`NO` → `uninstall`（`removeMonitor`）
3** 监视 `NSEventMaskRightMouseDown | Dragged | Up`，过滤 `event.window == 本窗`
4** 命中检测：点在当前 `webView`（或 contentContainer）内
5** 状态机 Idle / Armed；记录 down 的屏幕坐标
6** `make browser`；手测进入透明后右键 down/up 仍能出菜单（此阶段可不移窗）

---

## Phase RD-1：跟手移窗

**目标**：超过 5pt 后窗口跟随右键拖动。

### 任务清单

1** 常量 `kTransparentRightDragThreshold = 5.0`
2** Dragged：超阈值 → `Dragging`，按屏幕 delta 更新 `frame.origin`
3** 持续 Dragged 累加；松手回 Idle
4** 全屏 / 无 window 时直接忽略
5** 手测：透明态右键拖可移窗；多显示器简单回归

---

## Phase RD-2：菜单兼容与打磨

**目标**：普通右键不受影响；拖拽不弹菜单。

### 任务清单

1** `Dragging` 期间或拖后本次手势：`RightMouseUp` 返回 `nil`
2** `BrowserWebView willOpenMenu:withEvent:`：若本窗 `suppressContextMenu` → 取消菜单
3** 阈值内纯单击：菜单项（打开链接、搜索等）仍可用
4** 退出透明：卸监视器，标志清零
5** 按 design §8 验收；更新 design/plan 状态与 `docs/README.md`
6** `make browser` 无新增告警

---

## 建议实现顺序（给 Agent）

1. RD-0（监视器 + 状态机，先保证右键单击不坏）  
2. RD-1（超阈值移窗）  
3. RD-2（抑菜单双保险 + 验收文档）  

每阶段结束 `make browser`。提交信息使用简体中文（仅当用户要求 commit 时）。

---

## 非目标（本计划不做）

- 左键空白拖窗  
- 设置里开关/调阈值（可后续加）  
- Ctrl+左键拖窗  
- 覆盖层 hitTest 方案  
