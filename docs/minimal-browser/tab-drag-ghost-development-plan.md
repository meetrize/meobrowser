# 标签拖拽跟随阴影 — 开发计划

> 基于 [tab-drag-ghost-design.md](tab-drag-ghost-design.md)。  
> **状态：已实现（2026-07-15）。**  
> **Cursor Plan**：[.cursor/plans/tab-drag-ghost.plan.md](../../.cursor/plans/tab-drag-ghost.plan.md)

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| D1 | 离开标签条有效区（外扩 8pt）→ 松手成新窗口 |
| D2 | 拖出时条内合拢 |
| D3 | Detach 显示「新窗口」角标 |
| D4 / D5 | Esc 取消、跨窗拖入 — 首版不做 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| DG-0 | 影子骨架 Ghost-led | 0.5～1 天 | GhostController + 跟手 + 条内排序 |
| DG-1 | 双模式 + 吸附 | 0.5～1 天 | 条内/拖出样式、松手判定、条内吸附 |
| DG-2 | 新窗落点 + 文档 | 0.5 天 | 飞向新窗、Reduce Motion、验收 |

---

## 任务清单

见 Cursor Plan todos（`dg-0-*` … `dg-2-*`），实施时以该文件为准并更新 status。

---

## 验收

对照设计文档第 8 节。核心：影子跟手、双模式、WebView 不重载、无回归。
