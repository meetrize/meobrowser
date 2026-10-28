# AI Bridge — 开发计划（全量）

> 基于 [ai-bridge-design.md](ai-bridge-design.md)。  
> **状态（2026-10-28）**：BR-0 / BR-1 **完成且实测通**；BR-2 / BR-3 **本迭代落地**；BR-4 后续增强。  
> 关联：CA-3 ModelGateway · professional-features-roadmap

---

## 当前结论

| 项 | 状态 |
|----|------|
| 本机 OpenAI 兼容 API | ✅ `127.0.0.1:3921` |
| DeepSeek 网页绑定 | ✅ 填框 / 发送 / 读回复 |
| JS 桥接 | ✅ 同步启动 + 轮询 |
| SSE 假流式 | ✅ `stream:true` |
| new_chat / cancel | ✅ HTTP + 侧栏 |
| 409 登录态 | ✅ probe 失败 |
| ollama__ / openai__ | ✅ Upstream 转发 |
| Kimi 适配器 | ✅ 已实测（等「思考已完成」后取 `.markdown-container` 正文） |

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 产品名 | AI Bridge |
| 端口 | `3921`，仅 loopback |
| 鉴权 | Bearer |
| messages | 默认最后一条 user |
| stream | 假流式（整段后再切 SSE）；真增量 → BR-4 |
| 上游 | `ollama__*` / `openai__*` 真 HTTP |
| MCP / tools | BR-4 |

---

## 总览

| 阶段 | 名称 | 状态 |
|------|------|------|
| BR-0 | Spike | **完成** |
| BR-1 | MVP | **完成** |
| BR-2 | 体验加固 | **完成（本迭代）** |
| BR-3 | 统一网关 | **完成（本迭代）** |
| BR-4 | 增强 | 计划中 |

---

## Phase BR-2：体验加固

- [x] **2.1** `stream:true` SSE 假流式  
- [x] **2.2** `adapters/kimi.js` + 侧栏 Provider  
- [x] **2.3** `POST /v1/bridge/new_chat`  
- [x] **2.4** `POST /v1/bridge/cancel` + 侧栏取消  
- [x] **2.5** 请求前 probe → **409**  
- [x] **2.6** 侧栏：新对话、取消、复制 Base URL  
- [x] **2.7** Makefile 拷贝 kimi  

---

## Phase BR-3：统一网关

- [x] **3.1** `AIBridgeUpstreamClient`  
- [x] **3.2** `bridge__` / `ollama__` / `openai__` 路由  
- [x] **3.3** `/v1/models` 含前缀说明条目  
- [x] **3.4** `/health` 增强（queue / upstream / model 约定）  
- [x] **3.5** Prefs：`ollamaBaseURL` / `openaiBaseURL` / `openaiApiKey`  

---

## Phase BR-4：后续（不阻塞）

| ID | 项 |
|----|-----|
| 4.1 | 真增量 SSE（轮询差分） |
| 4.2 | 用户 Adapter 目录热覆盖 |
| 4.3 | tools 模拟 |
| 4.4 | MCP server |
| 4.5 | ChatGPT 实验适配器 |
| 4.6 | 与 CA-3 共享客户端 |

---

## 验收速查

```bash
TOKEN=...   # 侧栏复制

# 健康
curl -s http://127.0.0.1:3921/health

# 非流式（已验证 DeepSeek）
curl -s http://127.0.0.1:3921/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek","messages":[{"role":"user","content":"ping"}]}'

# 假流式
curl -N http://127.0.0.1:3921/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek","stream":true,"messages":[{"role":"user","content":"hi"}]}'

# 取消 / 新对话
curl -s -X POST http://127.0.0.1:3921/v1/bridge/cancel -H "Authorization: Bearer $TOKEN"
curl -s -X POST http://127.0.0.1:3921/v1/bridge/new_chat \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model":"bridge__deepseek"}'

# Ollama（本机需安装）
curl -s http://127.0.0.1:3921/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model":"ollama__llama3.2","messages":[{"role":"user","content":"hi"}]}'
```

---

## 风险

| 风险 | 对策 |
|------|------|
| 站点改版 | 修订 Adapter；probe 409 |
| Ollama 未装 | 502，不影响 bridge__ |
| 假流式 | 延迟≈整段生成；客户端仍可解析 SSE |
| Kimi 选择器 | 启发式；登录后 probe 修订 |
