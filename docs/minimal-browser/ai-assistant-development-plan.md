# AI 助手侧栏 — 开发计划

> 基于 [ai-assistant-design.md](ai-assistant-design.md)。依赖 [AI Bridge](ai-bridge-design.md)。  
> 页面上下文（整页摘要 / 可引用 Bundle）：[ai-page-context-design.md](ai-page-context-design.md) · [ai-page-context-development-plan.md](ai-page-context-development-plan.md)（**已确认**）

---

## Phase A — MVP（本迭代）

- [x] **A1** `BrowserAIAssistant*` 模块 + Prefs 宽度 / lastModelId  
- [x] **A2** Trailing slot kind + WC 接线 + 拖拽改宽  
- [x] **A3** Chrome `aiAssistant` + 工具菜单  
- [x] **A4** 模型下拉全平台 + ●/○；未绑定不可用  
- [x] **A5** Bridge HTTP 客户端 + 对话 UI + 取消  
- [x] **A6** 划词右键 AI 子菜单（问问 / 解释 / 总结 / 翻译）  
- [x] **A7** 设计 + 本计划 + roadmap 条目  
- [x] **A8** Makefile + 安装验收  

---

## Phase B — 增强

| ID | 项 | 状态 |
|----|-----|------|
| B1 | 整页摘要（正文 Citation + Recipe `summarize-page`） | **PC-0 已实现**，见 [ai-page-context-development-plan.md](ai-page-context-development-plan.md) |
| B2 | 问答本页（可勾选 Bundle 层） | **PC-1 已实现** |
| B3 | 多轮会话 + 新对话 | **已完成（多会话）**，见 [ai-multi-session-redesign.md](ai-multi-session-redesign.md) · [ai-multi-session-development-plan.md](ai-multi-session-development-plan.md) |
| B4 | `stream:true` 假 SSE 边显 | 计划中 |
| B5 | 划词：润色 / 更简洁 / 列表化 | 计划中 |
| B6 | 未绑定「去绑定」预选 Provider | 计划中 |
| B7 | Ollama / OpenAI 上游分组 | 计划中 |

---

## Phase C — 深度

| ID | 项 |
|----|-----|
| C1 | 阅读模式提纲 / 名词解释 |
| C2 | 标签整理建议 |
| C3 | 表单 / 许可协议要点 |
| C4 | 图片右键识图（需多模态） |
| C5 | 隐私：可选持久会话、设置说明 |

---

## Phase D — 生态

- `meobrowser://ai?action=summarize`（Page Context PC-3）
- Page Pack 固定 prompt / 用户 Recipe 共享
- 爬虫结果 AI 清洗；Bundle → Scraper 字段草稿（PC-3）

---

## 验收（A）

1. 工具栏开关侧栏，拖拽宽度重启保持  
2. 模型下拉 ●/○；未绑定不可发送  
3. 已绑定可对话并显示回复  
4. 划词 AI 动作开侧栏并提交（已绑定时）  
