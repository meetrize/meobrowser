# 跨窗口拖放标签 — 开发计划

> 基于 [tab-cross-window-drop-design.md](tab-cross-window-drop-design.md)。  
> **状态：已实现（2026-07-15）。**  
> **Cursor Plan**：[.cursor/plans/tab-cross-window-drop.plan.md](../../.cursor/plans/tab-cross-window-drop.plan.md)  
> 前置：多窗口真迁移、标签拖拽影子（DG）。

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 命中优先级 | 外窗 strip > 本窗 strip > 桌面（新窗） |
| 占位 | 目标条空心槽，用目标条 tab 宽度 |
| 松手迁移 | extract + adopt:atIndex:，WebView 不重建 |
| 提交动画 | 先迁移再短 fade 影子（正确性优先） |

---

## 总览

| 阶段 | 名称 | 预估 |
|------|------|------|
| XD-0 | 命中 + 占位 UI | 0.5～1 天 |
| XD-1 | 松手真迁移 | 0.5～1 天 |
| XD-2 | 样式打磨与验收 | 0.5 天 |

任务明细见 Cursor Plan todos。
