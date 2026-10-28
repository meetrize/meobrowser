# AI 助手多会话 + Bridge 自动绑定 — 改造方案

> 状态：**MS-0～MS-3 子集已落地（2026-10-28）** · 开发计划：[ai-multi-session-development-plan.md](ai-multi-session-development-plan.md)  
> 关联：[ai-assistant-design.md](ai-assistant-design.md) · [ai-bridge-design.md](ai-bridge-design.md)

## 结论

| 维度 | 目标 |
|------|------|
| 绑定 | **1 会话 = 1 binding = 1 标签**；同平台可多开 |
| 驱动 | 助手新建会话时自动开页绑定；Bridge 为基础设施 |
| UI | 窄侧栏：对话 ↔ 历史叠层；顶栏 历史 / 标题 / ＋新建 |
| modelId | `bridge__{provider}__{shortId}`；短名仅单绑定时兼容 |

详细交互、数据模型、分阶段与风险决策见同目录开发计划；完整叙事以本文件历史版本与开发计划为准。
