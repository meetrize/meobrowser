# AI Bridge — 开发计划

> 基于 [ai-bridge-design.md](ai-bridge-design.md) 的分阶段实施计划。  
> 前置：多标签、`evaluateJavaScript`、Trailing 侧栏槽、SBKit、Chrome Actions catalog。  
> **状态：BR-0 / BR-1 完成（2026-10-28）；BR-2～BR-3 未开工。**  
> 关联：[captcha-assist-development-plan.md](captcha-assist-development-plan.md)（CA-3 ModelGateway）· [page-scraper-development-plan.md](page-scraper-development-plan.md) · [professional-features-roadmap.md](professional-features-roadmap.md)

---

## 行为定稿（相对设计稿的默认取值）

| 项 | 定稿 |
|----|------|
| 产品名（UI） | **AI Bridge** |
| 默认端口 | `3921`（冲突时可在侧栏改） |
| 监听 | 仅 `127.0.0.1` |
| 鉴权 | Bearer token；首次启动服务时生成 |
| messages 语义 | 默认只发最后一条 user（`history=webpage`） |
| 流式 | BR-1 非流式；BR-2 再上 |
| 队列 | 每 binding 串行；上限 5，超额 429 |
| 默认超时 | 120s |
| 首发站 | Mock + DeepSeek |
| 服务默认 | **关**（不随 App 自动监听，需侧栏启动） |
| 快捷键 | 暂无；菜单「工具 → AI Bridge…」 |
| 文本输入 | SBKit |

未决项若变更，先改设计稿，再回写本表。

---

## 总览

| 阶段 | 名称 | 对应设计 | 状态 | 产出 |
|------|------|----------|------|------|
| Phase BR-0 | Spike 探针 | §6.2 / §11 | **完成** | mock 页 + 通用 runtime + DeepSeek 探针（已按实测修订） |
| Phase BR-1 | MVP | §6 / §7 / §8 | **完成** | HTTP + DeepSeek/Mock + 绑定 + 侧栏 |
| Phase BR-2 | 体验 | §6.3 L2 / 多站 | 未开始 | SSE、多 Provider、外置 Adapter、取消 |
| Phase BR-3 | 生态 | Gateway / tools | 未开始 | ModelGateway 合流、MCP、健康检查增强 |

建议节奏：先 **人工跑通 BR-0** → MVP = **BR-1**；对外演示以 BR-1 为准。

---

## Phase BR-0：Spike 探针

**目标**：不写 HTTP、不上侧栏；证明在 MeoBrowser 的 WKWebView 里「填提示词 → 发送 → 判定结束 → 读回复」闭环成立。

### 任务清单

#### 0A — 资产

- [x] **0.1** 目录 `SimpleBrowser/AIBridge/Spike/`
- [x] **0.2** `mock-chat.html`：仿 AI 对话页（textarea + 发送 + 流式假回复 + busy 态）
- [x] **0.3** `runtime.js`：实现 `window.__MeoAIBridge` 契约（可被 mock / 真站适配）
- [x] **0.4** `adapters/mock.js`：挂到 mock 页选择器
- [x] **0.5** `adapters/deepseek.js`：DeepSeek 启发式选择器 + 受控输入填充
- [x] **0.6** `SPIKE.md`：在 MeoBrowser 中逐步验证的操作说明

#### 0B — 实测（需人工 / Agent 代操作浏览器）

- [x] **0.7** mock-chat：连续 5 次 `send` + `waitComplete` 成功（2026-10-28，`allOk: true`）
- [x] **0.8** DeepSeek 已登录：`probe().ok == true`（textarea + host ok）
- [x] **0.9** DeepSeek 三轮成功（「智能小助手」/「2」/「OK」）；已回写 `adapters/deepseek.js`
- [x] **0.10** 失败模式记入 SPIKE 附录（发送为 DIV.ds-button、段落误读、send 前 baseline 竞态）

### 完成标准

- Mock：无需网络，稳定闭环。  
- DeepSeek：登录态下至少 3 轮；或文档标明阻塞原因与下一选择器修订。  
- 设计稿 Adapter 初值按实测更新。

### 验证命令（示意）

在 Web Inspector / 注入后控制台：

```js
await __MeoAIBridge.probe()
await __MeoAIBridge.waitComplete({ timeoutMs: 60000 }) // after send
```

或一次性：

```js
await __MeoAIBridge.send('用一句话介绍 WebKit')
  .then(() => __MeoAIBridge.waitComplete({ timeoutMs: 90000 }))
```

---

## Phase BR-1：MVP

**目标**：本机 curl / OpenAI SDK 可打通 **一个** `bridge__*` model（优先 DeepSeek；开发期可用 mock）。

### 任务清单

#### 1A — 服务与队列

- [x] **1.1** `AIBridgePreferences`：port、token、enabled  
- [x] **1.2** `AIBridgeHTTPServer`：loopback、Bearer、路由  
- [x] **1.3** `GET /health`、`GET /v1/models`、`POST /v1/chat/completions`（非流式）  
- [x] **1.4** `AIBridgeJobQueue`：串行、超时、上限 5  

#### 1B — 绑定与 Provider

- [x] **1.5** `AIBridgeRegistry` + 绑定（`bridgeKeepsAlive` 禁 hibernate）  
- [x] **1.6** `AIBridgeDOMProvider`：注入 Spike runtime + adapter  
- [x] **1.7** WK `evaluateJavaScript` 直接 await `sendAndWait` Promise（未单独建 message handler）  
- [x] **1.8** 内置 mock + deepseek Adapter 资源拷入 App bundle（Makefile）  

#### 1C — UI

- [x] **1.9** `BrowserTrailingSidebarKindAIBridge` + slot 接线  
- [x] **1.10** Chrome Action `aiBridge`  
- [x] **1.11** `AIBridgeSidebarController`：启停、token、绑定、状态、最近请求  
- [x] **1.12** 菜单「工具 → AI Bridge…」  
- [x] **1.13** SBKit 输入控件（token 展示用 `SBTextField`）  

#### 1D — 工程

- [x] **1.14** Makefile 源文件与 Resources  
- [x] **1.15** `make browser` 通过；设计/本计划勾选 BR-1  


### 完成标准

- 绑定 DeepSeek（或 mock 页标签）后：

```bash
curl -s http://127.0.0.1:3921/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek","messages":[{"role":"user","content":"ping"}]}'
```

返回助手正文。  
- 无 token → 401；未绑定 → 404；超时 → 504。  
- 仅 loopback 可连。

---

## Phase BR-2：体验

**目标**：可日常给脚本用；多站；失败可恢复。

### 任务清单

- [ ] **2.1** `stream: true` SSE（可先整段假流式，再 L2 增量）  
- [ ] **2.2** Provider：Kimi / 通义（至少一个）  
- [ ] **2.3** `POST /v1/bridge/new_chat`  
- [ ] **2.4** 任务取消（HTTP 断开或侧栏按钮 → `abort`）  
- [ ] **2.5** 用户覆盖 Adapter 目录 + 「重新探测」  
- [ ] **2.6** 请求历史脱敏与导出  
- [ ] **2.7** 绑定页需登录时 409 + 侧栏红字  

### 完成标准

- 两 Provider 可切换；取消中断页面观察；用户改 JSON 选择器无需重编译即可生效（重启注入即可）。

---

## Phase BR-3：生态

**目标**：与验证码助手 ModelGateway 叙事统一；可选 Agent 生态。

### 任务清单

- [ ] **3.1** `AIBridgeGateway`：`bridge__` / `ollama__` / `openai__` 路由  
- [ ] **3.2** tools / function calling prompt 模拟（学 token-free-gateway）  
- [ ] **3.3** 可选 MCP server（本机 stdio 或同端口扩展）  
- [ ] **3.4** 周期 health：登录态 / probe  
- [ ] **3.5** 与 CA-3 `CaptchaModelGateway` 合并或共享客户端代码  

### 完成标准

- OpenAI SDK 只改 `base_url` 即可在本地模型与 Bridge 间切换（靠 model id 前缀）。  
- 文档说明 ChatGPT 实验性与外挂 Chromium 方案。

---

## 目录规划（落地时）

```
SimpleBrowser/AIBridge/
  Spike/                 # BR-0（已有）
    SPIKE.md
    mock-chat.html
    runtime.js
    adapters/mock.js
    adapters/deepseek.js
  AIBridgePreferences.{h,m}
  AIBridgeHTTPServer.{h,m}
  AIBridgeRegistry.{h,m}
  AIBridgeJobQueue.{h,m}
  AIBridgeDOMProvider.{h,m}
  AIBridgeSidebarController.{h,m}
  Adapters/              # bundle 内置
```

---

## 依赖与风险门禁

| 门禁 | 说明 |
|------|------|
| BR-0 → BR-1 | Mock 必过；DeepSeek 建议过（若阻塞可先 MVP 只接 mock + 文档） |
| BR-1 → BR-2 | curl MVP 稳定；侧栏绑定无崩溃 |
| 风控 | 不自动过登录验证码；暂停队列 |
| WebKit | 不引入 CDP；不改 web-inspector「不做 Remote Debugging 服务」结论 |
