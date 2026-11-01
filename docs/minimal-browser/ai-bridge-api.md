# AI Bridge — 外部接入 API 手册

> 面向：**本机外部客户端**（curl / OpenAI SDK / Cursor / 自研脚本）通过 HTTP 调用 MeoBrowser AI Bridge。  
> 依据实现：`SimpleBrowser/AIBridge/`（以 `AIBridgeService` 路由为准）。  
> 设计背景见 [ai-bridge-design.md](ai-bridge-design.md)；本文只描述**可调用的协议与用法**。

---

## 1. 一句话

把浏览器里**已登录的 AI 对话标签**绑成 OpenAI 兼容端点：外部发 `/v1/chat/completions`，Meo 在绑定标签内代填、发送、等回复结束，再把助手正文返回。

可选：同一端口还可把请求转发到本机 Ollama 或任意 OpenAI 兼容上游（`ollama__*` / `openai__*`）。

---

## 2. 启用服务（浏览器侧）

1. 打开目标 AI 站点并登录（如 DeepSeek）。
2. 打开 **AI Bridge** 侧栏（Chrome 动作区或工具菜单）。
3. 选择 Provider → **绑定当前标签**（或由 AI 助手自动开页绑定）。
4. **启动服务**；侧栏会显示 Base URL 与 Bearer Token（可复制 / 轮换）。
5. 可选：勾选「随浏览器启动」自动 `startServer`。

未启动服务时，外部连接会失败。Token 存在 UserDefaults（`AIBridge.bearerToken`），首次启动会自动生成。

---

## 3. 地址与传输

| 项 | 值 |
|----|-----|
| 默认 Base URL | `http://127.0.0.1:3921` |
| 监听地址 | **仅** `127.0.0.1`（loopback；不监听 `0.0.0.0`） |
| 默认端口 | `3921`（侧栏可改，`AIBridge.port`） |
| 协议 | HTTP/1.x（本机，无 TLS） |
| 编码 | 请求/响应 JSON 默认 `application/json; charset=utf-8` |
| 流式响应 | `text/event-stream; charset=utf-8`（见 §7.4） |

实际端口以侧栏 / `GET /health` 的 `port` 字段为准：

```text
Base URL = http://127.0.0.1:<port>
```

**不要**把服务改成公网监听；本产品定位为本机个人实验。

---

## 4. 鉴权

除下列例外外，所有端点都需要：

```http
Authorization: Bearer <token>
```

| 路径 | 是否需要 Bearer |
|------|-----------------|
| `GET /health` | **否** |
| `OPTIONS *` | **否**（返回 204） |
| 其余 `/v1/...` | **是** |

Token 可在 AI Bridge 侧栏查看、复制、重新生成。无效或缺失 → **401**：

```json
{ "error": { "message": "unauthorized", "type": "auth" } }
```

---

## 5. Model ID 约定

请求体里的 `model` 决定走哪条后端：

| 前缀 | 含义 | 示例 |
|------|------|------|
| `bridge__` | 网页标签中转（需先绑定） | `bridge__deepseek`、`bridge__deepseek__a1b2c3` |
| `ollama__` | 转发到本机 Ollama OpenAI 兼容接口 | `ollama__llama3.2` |
| `openai__` | 转发到侧栏配置的上游 Base URL | `openai__gpt-4o-mini` |

### 5.1 网页绑定（`bridge__*`）

绑定成功后，完整 modelId 形如：

```text
bridge__<provider>__<shortId>
```

例如：`bridge__deepseek__a1b2c3`。

短名规则：

- `bridge__deepseek`：当且仅当该 Provider **恰好 1 个绑定**时可用。
- 同平台多个绑定（多会话）时，短名会 **409 ambiguous_model**，必须用完整 `bridge__deepseek__xxxxxx`（侧栏或 `GET /v1/models` / `/health` 可查）。

内置 Provider（`providerId`）：

| providerId | 站点（期望 host） | 首页 |
|------------|-------------------|------|
| `deepseek` | chat.deepseek.com | https://chat.deepseek.com/ |
| `kimi` | kimi.moonshot.cn / kimi.com 等 | https://www.kimi.com/ |
| `iwencai` | iwencai.com | https://www.iwencai.com/ |
| `doubao` | doubao.com | https://www.doubao.com/chat/ |
| `gemini` | gemini.google.com | https://gemini.google.com/app |
| `chatgpt` | chatgpt.com / chat.openai.com | https://chatgpt.com/ |
| `mock` | 任意（内置 mock-chat.html） | 包内 HTML |

### 5.2 Ollama（`ollama__*`）

- 默认上游：`http://127.0.0.1:11434/v1`（`AIBridge.ollamaBaseURL` 可改）。
- 请求会把 `model` 改写成去掉前缀后的 tag，再 POST 到上游 `/v1/chat/completions`。
- `stream` 由上游原样透传。

### 5.3 OpenAI 兼容上游（`openai__*`）

- 须在侧栏配置 `openaiBaseURL`（含 `/v1`）与可选 `openaiApiKey`。
- 未配置 Base → **400** `openaiBaseURL not configured`。
- 行为同 Ollama：去前缀后转发。

---

## 6. 端点一览

| 方法 | 路径 | 鉴权 | 说明 |
|------|------|------|------|
| GET | `/health` | 否 | 服务状态、绑定列表、队列、上游配置摘要 |
| GET | `/v1/models` | 是 | OpenAI 风格模型列表（已绑定 + 前缀提示） |
| POST | `/v1/chat/completions` | 是 | 主聊天接口（OpenAI Chat Completions 子集） |
| POST | `/v1/bridge/new_chat` | 是 | 在绑定页触发「新对话」 |
| POST | `/v1/bridge/cancel` | 是 | 取消当前任务并清空排队 |
| GET/POST | `/v1/bridge/inspect` | 是 | 调试：检查绑定页助手 DOM |
| OPTIONS | 任意 | 否 | 204 |

未知路径 → **404** `{ "error": { "message": "not found", ... } }`。

---

## 7. 端点详情

### 7.1 `GET /health`

无需 Token。示例：

```bash
curl -s http://127.0.0.1:3921/health | jq .
```

响应字段（摘要）：

```json
{
  "ok": true,
  "listening": true,
  "port": 3921,
  "bindings": [
    {
      "id": "<bindingId>",
      "model": "bridge__deepseek__a1b2c3",
      "provider": "deepseek",
      "session_id": "",
      "url": "https://chat.deepseek.com/...",
      "hasTab": true
    }
  ],
  "queue": { "busy": false, "pending": 0, "maxPending": 5 },
  "upstream": {
    "ollamaBaseURL": "http://127.0.0.1:11434/v1",
    "openaiBaseURL": "",
    "openaiConfigured": false
  },
  "models": {
    "bridge": "bridge__<provider>",
    "ollama": "ollama__<tag>",
    "openai": "openai__<model>"
  },
  "status": "空闲"
}
```

### 7.2 `GET /v1/models`

```bash
curl -s http://127.0.0.1:3921/v1/models \
  -H "Authorization: Bearer YOUR_TOKEN" | jq .
```

```json
{
  "object": "list",
  "data": [
    {
      "id": "bridge__deepseek__a1b2c3",
      "object": "model",
      "owned_by": "meo-bridge",
      "provider": "deepseek",
      "binding_id": "...",
      "session_id": ""
    },
    { "id": "ollama__*", "object": "model", "owned_by": "ollama-prefix" }
  ]
}
```

仅列出**仍有 tab** 的绑定；另附 `ollama__*` /（若已配置）`openai__*` 提示项。

### 7.3 `POST /v1/chat/completions`（核心）

#### 请求头

```http
Authorization: Bearer <token>
Content-Type: application/json
```

#### 请求体（网页中转最小集）

```json
{
  "model": "bridge__deepseek",
  "messages": [
    { "role": "user", "content": "用一句话介绍你自己" }
  ],
  "stream": false
}
```

| 字段 | 必填 | 行为 |
|------|------|------|
| `model` | 是 | 见 §5 |
| `messages` | 是（网页路径） | **只取最后一条 `role=user` 的 content** 写入网页；前面的历史默认由网页会话自身保持 |
| `stream` | 否 | `true` 时：网页路径为**假流式**（整段生成完再切成 SSE）；上游路径透传 |
| `meo_attachments` | 否 | 本机附件，见 §8；目前仅 DeepSeek |

`content` 支持：

- 字符串：直接作为提示词  
- 数组（多模态形态）：拼接其中 `type=text` 的 `text` 字段（忽略图片等其它 part）

网页路径**不会**把完整 `messages` 多轮原样重放到网页（避免与页内上下文重复）。

#### 成功响应（非流式）

```json
{
  "id": "chatcmpl-meo-…",
  "object": "chat.completion",
  "created": 1730000000,
  "model": "bridge__deepseek",
  "choices": [
    {
      "index": 0,
      "message": { "role": "assistant", "content": "…" },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

`usage` 固定为 0（网页无精确 token）。超时默认约 **180s**（队列任务）。

#### curl 示例

```bash
export MEO_BRIDGE=http://127.0.0.1:3921
export MEO_TOKEN='粘贴侧栏 Token'

curl -s "$MEO_BRIDGE/v1/chat/completions" \
  -H "Authorization: Bearer $MEO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bridge__deepseek",
    "messages": [{"role":"user","content":"ping"}]
  }'
```

侧栏「复制 curl」生成的命令与此等价。

### 7.4 流式（`stream: true`）

**网页 `bridge__*`**：页面生成完整结束后，服务端把正文按约 24 字符切成 OpenAI SSE chunk（假流式），以 `text/event-stream` 返回，末尾 `data: [DONE]`。

**`ollama__*` / `openai__*`**：上游响应原样透传（含真 SSE）。

客户端按标准 OpenAI streaming 解析即可。

### 7.5 `POST /v1/bridge/new_chat`

在绑定标签内触发「新对话」。

```json
{ "model": "bridge__deepseek" }
```

或：

```json
{ "provider": "deepseek" }
```

成功：`{ "ok": true }`；失败多为 **503**。

说明：实现按 `bridge__` 后整段当 `providerId` 解析。同平台多绑定时，请优先传短名 `bridge__deepseek`（取该平台「最新」一条）或 `provider` 字段；完整长 modelId（含 `__shortId`）不适合本端点。

### 7.6 `POST /v1/bridge/cancel`

取消当前生成并拒绝排队任务。

```bash
curl -s -X POST "$MEO_BRIDGE/v1/bridge/cancel" \
  -H "Authorization: Bearer $MEO_TOKEN"
```

```json
{ "ok": true, "cancelled": true }
```

被取消的任务对客户端返回 **499** 类失败（经 job 完成回调）。

### 7.7 `GET|POST /v1/bridge/inspect`

调试用：对绑定页助手 DOM 做检查。Body 可选：

```json
{ "model": "bridge__deepseek" }
```

未绑定 → 404。

---

## 8. 附件（`meo_attachments`）

扩展字段（非 OpenAI 标准），仅网页路径读取。**当前仅 `deepseek` 支持**；其它 Provider 带附件 → **400** `attachments_unsupported`。

```json
{
  "model": "bridge__deepseek",
  "messages": [{ "role": "user", "content": "请总结这个文件" }],
  "meo_attachments": [
    {
      "path": "/Users/you/Documents/report.pdf",
      "name": "report.pdf",
      "mime": "application/pdf"
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `path` | 是 | **本机绝对路径**（须以 `/` 开头） |
| `name` | 否 | 展示名；默认取路径最后一段 |
| `mime` | 否 | 缺省按扩展名猜测 |

约束：

- 单文件 ≤ **20MB**（Bridge 侧上限）
- 文件须存在且非目录；服务端读入后 base64 注入网页，走 DeepSeek 原生上传
- 允许「仅附件、空字符串 content」；两者皆空 → 400

更多产品设计见 [ai-attachment-design.md](ai-attachment-design.md)。

---

## 9. 错误码

统一形状：

```json
{ "error": { "message": "…", "type": "…" } }
```

| HTTP | 典型场景 | `type` 示例 |
|------|----------|-------------|
| 400 | JSON 无效、缺 model、缺 user content、附件非法、非支持前缀 | `invalid_request` / `attachments_unsupported` |
| 401 | Token 错误或缺失 | `auth` |
| 404 | model 未绑定 / 路径不存在 | `invalid_request` |
| 409 | 多绑定歧义、需登录/输入框未就绪、域名不匹配 | `ambiguous_model` / `login_required` / `host_mismatch` |
| 429 | 队列已满（默认 `maxPending=5`） | （job 层） |
| 499 | 客户端取消 / cancelAll | — |
| 502 | 上游转发失败 | `upstream_error` |
| 503 | 服务/WebView/Adapter 注入失败、页面 about:blank | `bridge_error` |
| 504 | 等待网页回复超时 | — |

域名不匹配时，错误对象可能额外带 `host` / `url` / `provider`；登录失败时可能带 `probe` 诊断对象。

---

## 10. 外部接入方式

### 10.1 前置检查清单

1. MeoBrowser 在运行，AI Bridge **已启动**。  
2. `curl http://127.0.0.1:3921/health` 看到 `"listening": true` 与期望 `bindings`。  
3. 绑定标签仍打开、已登录、未跳到无关域名。  
4. 复制侧栏 Token；调用时带 `Authorization: Bearer …`。  
5. `model` 与 `/v1/models` 中的 `id` 一致（多绑定时用完整 id）。

### 10.2 OpenAI Python SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:3921/v1",
    api_key="YOUR_TOKEN",  # 即侧栏 Bearer Token
)

resp = client.chat.completions.create(
    model="bridge__deepseek",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

附件需走原始 HTTP（SDK 无 `meo_attachments` 字段时自行 `requests.post`）。

### 10.3 Node（官方 openai 包）

```js
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "http://127.0.0.1:3921/v1",
  apiKey: process.env.MEO_TOKEN,
});

const r = await client.chat.completions.create({
  model: "bridge__deepseek",
  messages: [{ role: "user", content: "你好" }],
});
console.log(r.choices[0].message.content);
```

### 10.4 Cursor / 其它「自定义 OpenAI 兼容」客户端

| 配置项 | 填法 |
|--------|------|
| API Base / Endpoint | `http://127.0.0.1:3921/v1` |
| API Key | 侧栏 Bearer Token |
| Model | `bridge__deepseek` 或 `/v1/models` 列出的完整 id |

注意：

- 仅本机可用；远程机器连不上（loopback）。  
- 网页路径延迟高（真实页面生成），适合低频；并发会被队列串行化。  
- 默认只发**最后一条 user**；依赖网页里已有的多轮上下文。需要干净会话时先调 `/v1/bridge/new_chat`。

### 10.5 纯 curl + jq

```bash
MEO_BRIDGE=http://127.0.0.1:3921
MEO_TOKEN=YOUR_TOKEN

# 健康检查
curl -s "$MEO_BRIDGE/health" | jq .

# 列模型
curl -s "$MEO_BRIDGE/v1/models" -H "Authorization: Bearer $MEO_TOKEN" | jq '.data[].id'

# 聊天
curl -s "$MEO_BRIDGE/v1/chat/completions" \
  -H "Authorization: Bearer $MEO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek","messages":[{"role":"user","content":"1+1=?"}]}' \
  | jq -r '.choices[0].message.content'

# Ollama 转发示例
curl -s "$MEO_BRIDGE/v1/chat/completions" \
  -H "Authorization: Bearer $MEO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"ollama__llama3.2","messages":[{"role":"user","content":"hi"}]}'
```

### 10.6 队列与并发

- 同一 JobQueue：**串行**执行；默认最多排队 **5** 条，超出 **429**。  
- 长时间任务占用绑定标签；请勿同时在该标签手动打字干扰。  
- 可用 `/v1/bridge/cancel` 或侧栏取消。

---

## 11. 与网页会话的语义差异（必读）

| OpenAI 云 API | AI Bridge 网页路径 |
|---------------|-------------------|
| 无状态；每次带全量 messages | **有状态**：页内会话即上下文 |
| `messages` 全部生效 | 默认只注入**最后一条 user** |
| 高并发多连接 | 本机单队列，贴近真人节奏 |
| 稳定 SLA | 依赖站点 DOM；改版可能导致 probe/发送失败 |

失败时优先：刷新绑定页 → 侧栏「重新探测」→ 确认登录 → 看 `/health` 的 `url`/`hasTab`。

---

## 12. 安全边界

1. 只监听 `127.0.0.1`；持有本机 Token 即可调用。  
2. Token 可随时在侧栏轮换；轮换后旧客户端立刻 401。  
3. 附件路径由本机进程读盘——**仅信任本机调用方**。  
4. 遵守各 AI 平台服务条款；不做公网中转、账号池或多账号调度。  
5. 侧栏请求日志默认只保留摘要（最近约 30 条），不含完整 prompt/回复正文。

---

## 13. 相关代码与文档

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/AIBridge/AIBridgeService.m` | HTTP 路由与协议实现 |
| `SimpleBrowser/AIBridge/AIBridgeHTTPServer.m` | loopback 监听 |
| `SimpleBrowser/AIBridge/AIBridgePreferences.m` | 端口 / Token / 上游 |
| `SimpleBrowser/AIBridge/AIBridgeRegistry.m` | 绑定与 modelId |
| `docs/minimal-browser/ai-bridge-design.md` | 产品与架构设计 |
| `docs/minimal-browser/ai-bridge-development-plan.md` | 分阶段计划 |
| `docs/minimal-browser/ai-attachment-design.md` | 附件协议设计 |

---

## 14. 快速验收

```bash
# 1) 服务起来
curl -s http://127.0.0.1:3921/health | jq '.ok,.listening,.bindings'

# 2) 无 Token 应 401
curl -s -o /dev/null -w "%{http_code}\n" \
  http://127.0.0.1:3921/v1/models

# 3) 有绑定 + Token 应返回助手正文
curl -s http://127.0.0.1:3921/v1/chat/completions \
  -H "Authorization: Bearer $MEO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek","messages":[{"role":"user","content":"只回复：ok"}]}' \
  | jq -r '.choices[0].message.content'
```
