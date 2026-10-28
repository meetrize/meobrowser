# AI Bridge（本机网页中转 API）— 设计方案

> 目标：把 MeoBrowser **已登录的 AI 对话网页标签**绑定成本机可调用的 OpenAI 兼容端点；客户端提交提示词后，由浏览器在绑定标签内自动输入、发送、等待回复结束，再把文本返回 API。  
> 状态：**设计已定；BR-0/BR-1 已落地（2026-10-28）**  
> 开发计划：[ai-bridge-development-plan.md](ai-bridge-development-plan.md)  
> **多会话 / 多绑定改造（待实施）**：[ai-multi-session-redesign.md](ai-multi-session-redesign.md) — 1 会话 = 1 绑定；同平台多实例；由 AI 助手自动开页绑定。  
> 关联：[page-scraper-design.md](page-scraper-design.md) · [page-pack-design.md](page-pack-design.md) · [auto-login-design.md](auto-login-design.md) · [captcha-assist-design.md](captcha-assist-design.md)（ModelGateway）· [companion-protocol.md](companion-protocol.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [anti-bot-session-design.md](anti-bot-session-design.md)

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| 本机 HTTP → 控制已开 AI 标签 → 回传回复 | **可行**。复用 `BrowserTab` + `evaluateJavaScript` / PagePack；新建 loopback 服务与 Provider 适配器 |
| OpenAI 兼容 `/v1/chat/completions` | **定稿采用**。便于 Cursor / SDK / curl 零改造接入 |
| WebKit 无 CDP 时抓回复 | **定稿优先 DOM 观察**；进阶再做页内 `fetch`/SSE 钩子 |
| 与真 API / Ollama 关系 | Bridge 是 **ModelGateway 的一种 backend**（`bridge__*`），不是唯一路径 |
| 公网发布 / 账号池 | **不做**。仅 `127.0.0.1` + Bearer token |

**产品名（UI）**：AI Bridge  
**代码目录**：`SimpleBrowser/AIBridge/`，类型前缀 `AIBridge*`  
**产品路径**：BR-0 Spike → BR-1 MVP → BR-2 体验 → BR-3 生态

---

## 1. 需求理解

| # | 原始设想 | 理解 |
|---|---------|------|
| 1 | 利用本浏览器网页能力，把免费 AI 对话页做成中转 API | Tab-as-Backend：绑定真实登录会话，不逆向 token |
| 2 | Web 服务收到提示词 → 自动填入对话框 → 回车 | Provider Adapter 驱动输入框与发送 |
| 3 | 监控回复结束 → 整段返回 API | 完成判定 + 抽取最后一条助手消息 |
| 4 | 本机即可，暂不公网 | loopback + 本地 token |
| 5 | 完善交互与 UI | 侧栏：启停服务、绑定标签、状态与日志 |

以上理解正确。下文在对标开源 Web2API 后定稿架构与体验。

---

## 2. 对标与选型

| 项目 | 做法 | 对本方案 |
|------|------|----------|
| ChatGPT-Web2API / webllm-proxy | Chromium + CDP，拦 SSE | Meo 无 CDP → **不照搬**；API 形态对齐 |
| token-free-gateway | 多厂商 + tools 用 prompt 模拟 | **多 Provider 适配器**；tools 放 BR-3 |
| chatgpt-browser-bridge | 驱动已打开会话 | **绑定现有标签**最接近 |

**选型原则**

1. **真人浏览器会话是反爬解法**，不做 sentinel/PoW 破解。  
2. **OpenAI 表面协议**优先于自研 RPC。  
3. **DOM 适配器可外置热更新**，站点改版少发版。  
4. **串行队列**：同一绑定同一时刻只跑一轮对话。  
5. **合规边界**：本机个人实验；不提供公网中转、多账号调度。

---

## 3. 相对原始设想的优化

| # | 原始点 | 风险 | 更优做法 |
|---|--------|------|----------|
| U1 | 只做「网页中转」 | 站点一改全挂；风控 | 统一 **ModelGateway**：`bridge__*` / `ollama__*` / `openai__*` |
| U2 | 直接公网化思路 | 滥用与 ToS | 默认仅 loopback；无「发布到公网」开关 |
| U3 | 完整多轮 messages 原样重放 | 网页已有上下文，易重复 | 默认只发 **最后一条 user**；可选 `history` 模式 |
| U4 | 轮询 DOM 猜结束 | 误判截断 | `busy` 选择器消失 + 内容稳定窗口；可选网络钩子 |
| U5 | 每站硬编码进 ObjC | 改版成本高 | Adapter = JSON 选择器 + JS 包，可用户覆盖 |
| U6 | 无头自动化 | WebKit/风控更差 | **有头、用户已登录的标签** |

---

## 4. 方案定位

### 4.1 产品一句话

**AI Bridge**：把当前已登录的 AI 对话标签绑成本机模型端点；用标准 OpenAI 客户端发聊天请求，Meo 在该标签里代发并回传完整回复。

### 4.2 与现有能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| `BrowserTab` / `BrowserTabController` | 多标签 + hibernation | 绑定 tab **禁止休眠**（或唤醒后再发） |
| `evaluateJavaScript` / PagePack | 注入与驱动 | Adapter 运行时主通道 |
| LoginRunner / FormMemo | 填框 + input/change 事件 | 复用同一套 setValue 模式 |
| Scraper | DOM 抽取 | 不直接依赖 Recipe；可借鉴等待/超时 |
| Companion Bonjour | 本机 IPC 先例 | HTTP 另起；鉴权思想可对齐 |
| Captcha ModelGateway（CA-3） | 设计中 | **合并叙事**：Gateway 路由到 ollama / openai / bridge |
| Trailing 侧栏 | 通知 / 助手 / 历史 / Pack / 爬虫 | **新增** `BrowserTrailingSidebarKindAIBridge` |
| Chrome Actions | catalog | **新增** `aiBridge`（SF Symbol 建议 `arrow.left.arrow.right.circle`） |
| SBKit | 强制 | 侧栏输入用 `SBTextField` |

### 4.3 做什么 / 不做什么

| 阶段 | 做 | 不做 |
|------|----|------|
| **BR-0** | 探针 JS + mock 页；验证填框/发送/完成检测 | HTTP、侧栏 |
| **BR-1** | loopback HTTP、单 Provider、绑定当前标签、非流式 completions、侧栏 MVP | 流式、多 Provider、tools |
| **BR-2** | SSE（可先假流式）、多 Provider、新对话、超时取消、外置 Adapter | 公网、CDP |
| **BR-3** | tools 模拟、与 ModelGateway 统一、可选 MCP、健康检查 | 账号池、验证码自动过登录 |

### 4.4 设计原则

1. **本机默认安全**：`127.0.0.1` + Bearer；token 可轮换。  
2. **可见可控**：侧栏显示队列与最近请求；可选轻提示。  
3. **脆而不隐**：失败给可读原因（未绑定 / 需登录 / 选择器失效 / 超时）。  
4. **主进程可停**：任务可取消；取消后释放页面观察器。  
5. **遵守站点条款**：产品文案标明个人本机用途。

---

## 5. 用户流程

### 5.1 首次使用

1. 打开 AI 站（如 DeepSeek）并手动登录（含验证码）。  
2. 打开 AI Bridge 侧栏 →「绑定当前标签」。  
3. 系统 `probe()`：检测输入框与登录态；失败则提示。  
4. 「启动服务」→ 展示 `http://127.0.0.1:3921` 与 token →「复制 curl / base URL」。  
5. 外部客户端请求 → 标签内自动对话 → JSON 返回。

### 5.2 日常

- 保持绑定标签打开且会话有效。  
- 侧栏看状态：空闲 / 排队 / 生成中 / 需登录。  
- 站点改版：用「重新探测」或更新用户 Adapter。

### 5.3 失败与人工介入

- 出现验证码 / 风控页：队列暂停，侧栏红字，用户处理后续跑。  
- 超时：返回 504 + 日志；不强制刷新页（避免丢会话）。

---

## 6. 架构

```
Client (OpenAI SDK / curl)
        │  HTTP 127.0.0.1:3921
        ▼
AIBridgeHTTPServer
        │  auth + route
        ▼
AIBridgeGateway  ──┬── ollama__* / openai__*（真 HTTP，BR-3 与 CA-3 合流）
                   └── bridge__* 
                            │
                     AIBridgeJobQueue（每 binding 串行）
                            │
                     AIBridgeProvider（Adapter）
                            │
                     AIBridgeTabBinding → WKWebView
                            │
                     JS: probe / send / waitComplete / readReply
```

### 6.1 模块职责

| 类型 | 职责 |
|------|------|
| `AIBridgeHTTPServer` | GCD / NWListener loopback；`/v1/models`、`/v1/chat/completions`、`/health` |
| `AIBridgePreferences` | 端口、token、是否开机自启服务（默认否）、日志保留条数 |
| `AIBridgeRegistry` | providerId ↔ tabID / window；在线探测结果 |
| `AIBridgeJobQueue` | 串行、超时、取消、429 当队列满 |
| `AIBridgeProvider` | 协议：`probe` / `sendPrompt` / `awaitCompletion` / `readAssistant` / `newChat` |
| `AIBridgeDOMProvider` | 默认实现：加载 Adapter JSON+JS，经 `evaluateJavaScript` 调用 |
| `AIBridgeSidebarController` | 侧栏 UI |
| `AIBridgeSessionLog` | 本地请求摘要（脱敏） |

### 6.2 页内 JS 契约（`window.__MeoAIBridge`）

```js
{
  probe(): { ok, host, loggedIn, hasInput, detail },
  send(text): { ok, error },
  isBusy(): boolean,
  readLastAssistant(): { text, html?, messageId? },
  waitComplete({ timeoutMs, stableMs, baseline? }): Promise<{ ok, text, error }>,
  sendAndWait(text, opts): Promise<{ ok, text, error }>,  // 推荐：先采 baseline 再 send
  newChat(): { ok, error },
  abort(): void
}
```

Native 优先调用 `sendAndWait`（避免短回复竞态）。完成亦可用 `webkit.messageHandlers.aiBridge` 回传（BR-1 可先轮询）。

### 6.3 抓取策略分级

| 级 | 策略 | 阶段 |
|----|------|------|
| L1 | DOM：`busySelector` 消失 + 文本稳定 `stableMs`（默认 800） | BR-0/1 |
| L2 | MutationObserver 推送增量 | BR-2 |
| L3 | document-start 钩 `fetch`/EventSource，匹配 conversation URL | BR-2/3 按站 |

### 6.4 Adapter 配置（外置）

路径建议：

- 内置：`SimpleBrowser/AIBridge/Adapters/<id>/`
- 用户覆盖：`~/Library/Application Support/MeoBrowser/AIBridge/Adapters/<id>/`

```json
{
  "id": "deepseek",
  "displayName": "DeepSeek 网页",
  "modelId": "bridge__deepseek",
  "matchHosts": ["chat.deepseek.com"],
  "inputSelector": "textarea",
  "sendSelector": ".ds-button--primary",
  "assistantSelector": ".ds-markdown.ds-assistant-message-main-content",
  "busySelector": null,
  "newChatSelector": null,
  "completeWhen": "assistantGrowth+stable",
  "stableMs": 1000,
  "defaultTimeoutMs": 120000,
  "notes": "发送控件多为 DIV.ds-button；须 send 前采 baseline；勿用 .ds-markdown-paragraph 单独取文"
}
```

DeepSeek 选择器已于 2026-10-28 登录态实测修订（见 Spike/`adapters/deepseek.js`）。

```json
{
  "id": "iwencai",
  "displayName": "问财 网页",
  "modelId": "bridge__iwencai",
  "matchHosts": ["www.iwencai.com", "iwencai.com"],
  "inputSelector": "#footInput .ql-editor",
  "sendSelector": ".chat-input-bottom-right-button.send-button",
  "assistantSelector": ".chat-response-message-container .rich-text-container.aime-markdown",
  "busySelector": null,
  "completeWhen": "「模型答案生成完成」+ markdown 稳定",
  "stableMs": 1000,
  "defaultTimeoutMs": 180000,
  "notes": "Quill；有字才出 send；完成态「问财 模型答案生成完成」；勿把残留的 .chat-thinking-loading.chat-thinking-summary-icon 当 busy"
}
```

问财选择器已于 2026-10-28 登录态实测；同日修复完成后 loading 图标残留导致 API 一直等待的问题（见 Spike/`adapters/iwencai.js`）。

```json
{
  "id": "doubao",
  "displayName": "豆包 网页",
  "modelId": "bridge__doubao",
  "matchHosts": ["www.doubao.com", "doubao.com"],
  "inputSelector": ".tiptap.ProseMirror / [data-testid=chat_input_input]",
  "sendSelector": "[data-testid=chat_input_send_button] / #flow-end-msg-send",
  "assistantSelector": "[data-testid=receive_message] [data-testid=message_text_content]",
  "busySelector": null,
  "completeWhen": "末条 receive_message 出现 message_action_regenerate + 正文稳定",
  "stableMs": 1000,
  "defaultTimeoutMs": 180000,
  "notes": "TipTap；有字才出 send；生成中 send-btn-wrapper 带 !hidden；新对话 aria-label=新对话"
}
```

豆包选择器已于 2026-10-28 登录态实测（见 Spike/`adapters/doubao.js`）。

```json
{
  "id": "gemini",
  "displayName": "Gemini 网页",
  "modelId": "bridge__gemini",
  "matchHosts": ["gemini.google.com", "bard.google.com"],
  "inputSelector": "rich-textarea .ql-editor",
  "sendSelector": "button[aria-label=发送] / gem-icon-button.send-button",
  "assistantSelector": "model-response .markdown-main-panel",
  "busySelector": "button[aria-label=停止回答]",
  "completeWhen": "停止消失 + regenerate-button + 正文稳定",
  "stableMs": 1000,
  "defaultTimeoutMs": 180000,
  "notes": "Quill；游客/登录均可用；登录态实测 meetrice；正文取 .markdown-main-panel；新对话=发起新对话/reset-button"
}
```

Gemini 选择器已于 2026-10-28 游客 + 登录态实测（见 Spike/`adapters/gemini.js`）。

```json
{
  "id": "chatgpt",
  "displayName": "ChatGPT 网页",
  "modelId": "bridge__chatgpt",
  "matchHosts": ["chatgpt.com", "chat.openai.com"],
  "inputSelector": ".ProseMirror[contenteditable=true]",
  "sendSelector": "button[aria-label=发送]",
  "assistantSelector": "[data-markdown-text-style=assistant-message]",
  "busySelector": "button[aria-label=停止]",
  "completeWhen": "停止消失 + 重新生成回复 + 正文稳定",
  "stableMs": 1000,
  "defaultTimeoutMs": 180000,
  "notes": "2026-10 新 UI：优先 data-markdown-text-style；旧 data-message-author-role 作 fallback"
}
```

ChatGPT 选择器已于 2026-10-28 登录态实测（见 Spike/`adapters/chatgpt.js`）。

---

## 7. API 约定

### 7.1 监听

| 项 | 值 |
|----|-----|
| 默认地址 | `http://127.0.0.1:3921` |
| 绑定 | **仅** IPv4 loopback（禁止 `0.0.0.0`） |
| 鉴权 | `Authorization: Bearer <token>`；启动时生成，可「重新生成」 |

### 7.2 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | `{ "ok": true, "bindings": [...] }` |
| GET | `/v1/models` | 已绑定且 probe 通过的 model 列表 |
| POST | `/v1/chat/completions` | OpenAI Chat Completions 子集 |
| POST | `/v1/bridge/new_chat` | 可选；触发绑定页新对话 |

### 7.3 Completions 语义

| 字段 | 行为 |
|------|------|
| `model` | 必须为已注册 `bridge__*`（或 Gateway 其它前缀） |
| `messages` | 默认取最后一条 `role=user` 的 `content`（字符串；多模态 BR-3） |
| `history` | 缺省 `webpage`；`forward` 时把多轮拼成单段再发送 |
| `stream` | BR-1 忽略或假流式一整块；BR-2 支持 |
| `tools` | BR-1/2 忽略；BR-3 prompt 模拟 |
| 超时 | Adapter `defaultTimeoutMs`，可被请求扩展字段覆盖 |

成功响应（非流式）对齐 OpenAI：

```json
{
  "id": "chatcmpl-meo-…",
  "object": "chat.completion",
  "created": 0,
  "model": "bridge__deepseek",
  "choices": [{
    "index": 0,
    "message": { "role": "assistant", "content": "…" },
    "finish_reason": "stop"
  }],
  "usage": { "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0 }
}
```

`usage` 可填 0（网页无精确 token）。

### 7.4 错误

| HTTP | 场景 |
|------|------|
| 401 | token 无效 |
| 404 | model 未绑定 |
| 409 | 需登录 / 页未就绪 |
| 429 | 队列已满 |
| 504 | 等待回复超时 |
| 503 | 服务未启动或 Adapter 失效 |

---

## 8. UI / UX

### 8.1 入口

- Chrome Action：`aiBridge`，tooltip「AI Bridge」  
- 菜单：工具 → AI Bridge…  
- 与其它 trailing 侧栏互斥

### 8.2 侧栏结构（单面板、单主任务）

1. **服务**：运行状态、base URL、token（显示/复制/轮换）、启停  
2. **绑定**：Provider 选择、当前标签摘要、绑定/解绑、probe 结果  
3. **状态**：空闲 / 排队 N / 生成中 / 错误文案  
4. **最近请求**：时间、model、耗时、状态码（无正文隐私默认）  
5. **快捷**：复制 curl、打开本地说明页（mock/spike 文档）

### 8.3 交互细节

- 绑定成功：轻绿色状态点。  
- 任务进行中：可选 Dock bounce 一次或菜单栏小点（默认关，设置可开）。  
- 解绑或关标签：自动下线对应 model，进行中任务失败并 503。  
- 输入类控件一律 SBKit。

---

## 9. 安全与合规

1. 仅 loopback；文档禁止改公网监听。  
2. Bearer token 存 Preferences / Keychain（定稿：UserDefaults 即可，BR-2 可升 Keychain）。  
3. 日志默认不写完整 prompt/回复；调试开关才落盘全文。  
4. UI 短提示：请遵守各 AI 平台服务条款；仅供本机个人使用。  
5. 不提供「绕过付费墙 / 多账号轮询」能力。

---

## 10. 风险与对策

| 风险 | 对策 |
|------|------|
| DOM 改版 | 外置 Adapter；probe 失败明确提示 |
| React 受控输入不吃 `value=` | 与 LoginRunner 相同：native value setter + InputEvent；必要时逐字或点发送按钮 |
| 标签休眠丢状态 | 绑定 tab `hibernationDisabled` 或等价标志 |
| 并发打爆网页 | 每 binding 队列上限（默认 5） |
| 会话过期 | `/health` + 侧栏「需要重新登录」 |
| ChatGPT 强风控 | Adapter 标实验性；文档可建议外挂 Chromium Web2API，Gateway 路由 |

---

## 11. 首发 Provider

| 优先级 | Provider | 理由 |
|--------|----------|------|
| P0 | **Mock**（本地 HTML） | BR-0 无登录可回归 |
| P0 | **DeepSeek 网页** | 国内常用、结构相对稳 |
| P1 | Kimi / 通义 | 同技术路径 |
| P2 | ChatGPT | 风控高，实验性 |

---

## 12. 验收总览（设计级）

| 项 | 标准 |
|----|------|
| Spike | mock 页上 send→waitComplete 稳定；DeepSeek 人工登录下至少连续 3 轮成功 |
| MVP | curl 打 `/v1/chat/completions` 返回助手正文；侧栏可绑定/启停 |
| 安全 | 非 loopback 无法连接；无 token 401 |
| 失败 | 拔掉绑定后请求 404/503；超时 504 |

---

## 13. 文档与代码落点

| 路径 | 说明 |
|------|------|
| `docs/minimal-browser/ai-bridge-design.md` | 本文 |
| `docs/minimal-browser/ai-bridge-development-plan.md` | 分阶段计划 |
| `SimpleBrowser/AIBridge/` | 实现目录（BR-1+） |
| `SimpleBrowser/AIBridge/Spike/` | BR-0 探针与 mock 页 |
