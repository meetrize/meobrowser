# AI 助手侧栏 — 设计

> 面向浏览场景的对话 UI；后端为本机 [AI Bridge](ai-bridge-design.md) OpenAI 兼容 API。  
> 与 **AI Bridge 管理侧栏**职责分离。  
> **多会话改造（待实施）**：[ai-multi-session-redesign.md](ai-multi-session-redesign.md) — 会话驱动自动开页绑定；Bridge 不再作为手动绑定主路径。

---

## 1. 定位

| 侧栏 | 职责 |
|------|------|
| **AI Bridge** | 启停 loopback、绑定/解绑网页 Provider、探测、快速测试 |
| **AI 助手** | 选模型、发提示、看回复；划词右键入口 |

助手**只**调用 `http://127.0.0.1:<port>/v1/chat/completions`（Bearer），不直接操作网页 DOM。

---

## 2. UI

- Trailing 侧栏，与通知 / 历史 / Bridge 等互斥（`BrowserTrailingSidebarKindAIAssistant`）
- 可拖拽改宽：默认 360，范围 280～560，持久化
- Chrome 按钮 `aiAssistant`（sparkles）+ 工具菜单「AI 助手…」
- 顶部：模型下拉（全平台 + ●/○ 绑定态）+ 状态条
- 中部：对话记录（用户 / 助手分段）
- 底部：`SBTextView` 输入 + 发送 / 取消；「打开 AI Bridge」便于去绑定

### 模型列表

固定平台（与 Bridge 一致，不含 mock）：

| 显示名 | modelId |
|--------|---------|
| DeepSeek 网页 | `bridge__deepseek` |
| Kimi 网页 | `bridge__kimi` |
| 问财 网页 | `bridge__iwencai` |
| 豆包 网页 | `bridge__doubao` |
| Gemini 网页 | `bridge__gemini` |
| ChatGPT 网页 | `bridge__chatgpt` |

- ● = Registry 已绑定且 tab 存活；○ = 未绑定  
- 选中未绑定：禁用发送，提示去 Bridge 侧栏绑定  
- 数据源：静态表 + `AIBridgeRegistry`，**不以** `/v1/models` 为唯一来源（该接口仅返回已绑定）

---

## 3. 划词右键

有选区时插入 **AI** 子菜单：

- 直接问问 AI
- 解释
- 总结
- 翻译成中文

行为：打开 AI 助手侧栏 → 套 prompt 模板 → 当前模型已绑定则自动发送，否则只填入并提示。

---

## 4. 错误与状态

| 情况 | 表现 |
|------|------|
| 未绑定 | 橙/红提示，发送禁用 |
| 服务未启动 | 发送前尝试 `startServer:` |
| 409 host / 登录 | 展示 Bridge 返回的 `error.message` |
| 进行中 | 禁用发送；取消走 `/v1/bridge/cancel` |

---

## 5. 隐私

- MVP：会话仅内存，不落盘  
- 选区与正文经本机 Bridge，不默认上传第三方（除非用户绑的是云网页 Provider）  
- 后续：可选「记住会话」、设置页说明

---

## 6. 后续能力（见开发计划 Phase B～D）

- **页面上下文（已定稿）**：整页正文摘要、可勾选 Bundle（HTML/资源）、Prompt Recipe — [ai-page-context-design.md](ai-page-context-design.md) · [ai-page-context-development-plan.md](ai-page-context-development-plan.md)
- 多轮（已完成）、流式、改写、上游模型分组、阅读模式 AI、标签整理等。
