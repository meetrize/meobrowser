# AI 多会话 + Bridge 多绑定 — Cursor 开发计划

> 依据：[ai-multi-session-redesign.md](ai-multi-session-redesign.md)  
> 目标：一次落地 MS-0～MS-3（流式 / 上游分组可留接口，本迭代做可交付子集）

---

## Cursor Plan（执行顺序）

### MS-0 Registry / 路由
1. [x] `AIBridgeBinding` 增加 `bindingId`、`sessionId`、`createdAt`；`modelId = bridge__{provider}__{shortId}`
2. [x] Registry 主键改为 `byBindingId`；`bindingsForProviderId:`；兼容 `bindingForProviderId:`（取最新一条）
3. [x] `bindingForModelId:`：精确匹配长 id；短 id `bridge__provider` 仅当该平台恰好 1 条时命中，多条则视为未命中（上层 409）
4. [x] `bindTab:` 始终新建 binding；同 tab 旧 binding 清除 keep-alive
5. [x] Service `bindCurrentTab` 返回/使用新 modelId；completions 歧义 409
6. [x] `/v1/models` 列出全部 binding

### MS-1 助手多会话 MVP
7. [x] `AIAssistantSession` / `AIAssistantMessage` / `AIAssistantSessionStore`（落盘 Application Support）
8. [x] Sidebar 两态：对话 / 历史 / 新建选平台；顶栏 历史·标题·＋
9. [x] 新建 → 选平台 → WC 开首页标签 → bind → 挂 session
10. [x] 发送用 session.modelId；本地存气泡；去掉「必须先 Bridge 绑定」
11. [x] Bridge 侧栏：活动绑定列表 + 队列状态；文案引导助手主路径

### MS-2 体验
12. [x] 首条用户消息自动标题；标题可编辑；删除（可解绑）
13. [x] 网页已关 → 「重新打开网页」；「显示网页」聚焦 tab
14. [x] 划词 `presentAction`：无会话则新建（用上次平台）
15. [x] 历史搜索（标题 / 摘要）

### MS-3 强化（本迭代子集）
16. [x] 清空全部会话；导出会话到剪贴板
17. [x] Bridge 活动列表显示队列 busy/pending
18. [ ] 完整 SSE / Ollama 分组 UI（后续）

### 收尾
19. [x] Makefile 加入新 `.m`
20. [x] 开发计划勾选
21. [x] `one-click-install` 编译安装

---

## 验收清单

见 redesign §11；外加：删除会话后 binding 可清除；重启后历史仍在。

---

## 文件落点

| 新建 | 路径 |
|------|------|
| Session 模型/Store | `SimpleBrowser/AIAssistant/AIAssistantSession*.{h,m}` |
| 开发计划 | 本文件 |
| 设计（若不存在则补） | `ai-multi-session-redesign.md` |

| 大改 | 路径 |
|------|------|
| Registry / Service / Bridge Sidebar | `SimpleBrowser/AIBridge/*` |
| Assistant Sidebar / ChatPanel / Prefs | `SimpleBrowser/AIAssistant/*` |
| WC 委托开页 | `BrowserWindowController.m` |
