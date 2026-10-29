# AI 附件（Attachment）— 设计方案

> 目标：在 **AI 助手**输入区支持本地附件；经 **AI Bridge** 注入到已绑定的 **DeepSeek 网页**对话，成为该站原生附件并随消息发送。  
> 状态：**已确认（按推荐定稿）** · 2026-10-29  
> 开发计划：[ai-attachment-development-plan.md](ai-attachment-development-plan.md)  
> 首发 Provider：**仅 DeepSeek**；其它站后续按同一 Adapter 契约扩展。  
> 关联：[ai-bridge-design.md](ai-bridge-design.md) · [ai-assistant-design.md](ai-assistant-design.md) · [ai-assistant-development-plan.md](ai-assistant-development-plan.md) · Spike `adapters/deepseek.js`

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| DeepSeek 网页是否支持附件 | **支持**。作曲区回形针 + 隐藏 `input[type=file][multiple]` |
| 不弹系统文件框、用 JS 注入本地文件 | **可行（已实测）**。`DataTransfer` + `input.files = dt.files` + `change` → 出现附件卡，并调用官方上传 API |
| 经 AI Bridge 转发到网页 | **可行**。Native 读盘 → 页内构造 `File` → 复用现有 Adapter 通道 → 再 `sendAndWait` |
| 助手 UI 加上传 | **可行**。输入框下方/旁侧加回形针与芯片条，不改对话气泡主结构 |
| 首版范围 | **只做 DeepSeek**；协议预留多 Provider |

**产品名（UI）**：附件 / 「添加附件」  
**代码建议**：Bridge 侧 `AIBridgeAttachment*` + `deepseek.js` 扩展；助手侧 Citation/Composer 扩展  
**产品路径**：AT-0 Spike 页内上传 → AT-1 Bridge API + DeepSeek Adapter → AT-2 助手 UI → AT-3 多文件/拖放/大文件 → AT-4 其它 Provider

---

## 1. 需求理解

| # | 原始设想 | 理解与定稿 |
|---|---------|------------|
| 1 | 先做 DeepSeek | 首发只保证 `bridge__deepseek`；其它模型选中时禁用附件或灰显说明 |
| 2 | AI 助手聊天框下加上传 | 作曲区（输入框）内/下：回形针、拖放、芯片预览；发送时一并交给 Bridge |
| 3 | 经 Bridge 转到 DeepSeek 网页并成为其对话附件 | **不**自己解析文件塞进 prompt；**是**驱动网页完成与真人一致的上传，再发文字 |

以上理解正确。关键纠偏见 §3。

---

## 2. 探测报告（2026-10-29 · chat.deepseek.com 登录态）

### 2.1 UI

- 作曲根：`.aaff8b8f`
- 输入：`textarea`（placeholder「给 DeepSeek 发送消息」）
- 回形针：`.ds-button.ds-button--iconLabelPrimary`（纸夹 SVG，发送按钮左侧）
- 发送：`.ds-button--primary` 圆形上箭头
- 附件卡出现后：文件名节点 `.e70accd6`，元信息 `._7103a25`（如 `TXT 73B`），卡容器 `div._25c7358.dafb6286`，条带 `div.b40079d7`

### 2.2 隐藏 file input

```text
input[type="file"][multiple]
accept: 约 985 个扩展名（pdf / 常见图片 / doc(x) / ppt(x) / xls(x) / md / csv / 大量代码后缀 …）
父级：div.bf38813a ⊂ 作曲区
```

公开资料口径（供产品文案，非硬编码上限）：网页侧约 **单文件 ≤100MB、会话最多约 50 个**；以实际上传失败提示为准。

### 2.3 注入实测（关键）

在页内执行：

1. `new File([blob], 'meo-bridge-probe.txt', { type: 'text/plain' })`
2. `DataTransfer.items.add(file)` → `input.files = dt.files`
3. `dispatchEvent(change)`

结果：

- 作曲区出现附件卡：`meo-bridge-probe.txt` / `TXT 73B`
- 网络出现：
  - `POST https://chat.deepseek.com/api/v0/file/upload_file`
  - `GET https://chat.deepseek.com/api/v0/file/fetch_files?file_ids=file-…`
- **无需点击回形针、无需系统文件选择器**

结论：WKWebView / Chromium 系均可走「页内构造 File → 赋给隐藏 input」路径；**不必**依赖 CDP `setFileInput`（Meo 也没有 CDP）。

### 2.4 与现有 Adapter 的关系

现有 `deepseek.js` 已覆盖：`probe` / `setInput` / `clickSend` / `sendAndWait` / `readLastAssistant`。  
缺口：**`attachFiles` + `waitAttachmentsReady`**，以及发送前「附件未就绪则等待/失败」。

### 2.5 风险与注意

| 风险 | 说明 | 缓解 |
|------|------|------|
| 哈希 class 改版 | `.e70accd6` 等不稳定 | 就绪判定用「文件名文本出现 + meta 非上传中 + 无 spinner」；选择器集中 Adapter |
| `evaluateJavaScript` 大 payload | 大文件 base64 会卡顿/失败 | AT-1 小文件直传；AT-3 loopback 暂存 URL + 页内 `fetch` |
| WebKit `input.files` 赋值 | Chromium 上合成 `change` 可用；WKWebView 常不触发 React | **定稿**：赋值后调 `__reactProps$.onChange` + composer `drop`；不可直调 `upload_file`（需 PoW 头） |
| 深度思考 / 模式限制 | 历史上 Expert 模式曾禁附件 | 发送前 `probeAttachments()`；不可用则明确错误 |
| 多模态 ≠ 附件 | DeepSeek 网页附件多为服务端抽文本 | 产品文案写清「随网页上传」，不承诺像素级识图 |
| 合规 | 复用用户已登录会话 | 保持 Bridge「本机个人」边界；不代登、不公网中转文件 |

---

## 3. 相对原始设想的优化（建议采纳）

| # | 原始点 | 风险 | 更优做法 |
|---|--------|------|----------|
| U1 | 只在助手 UI 选文件，Bridge 再「想办法」 | 协议不清、难测 | 先定 **Bridge 契约**（`attach` → ready → send），助手只是客户端 |
| U2 | 把文件内容读进 prompt | 爆上下文、丢格式、与网页能力重复 | **优先网页原生上传**；文本小文件可另提供「粘贴为代码块」降级 |
| U3 | 一上来做全 Provider | 每站上传 DOM 不同 | DeepSeek 打穿后再抽象 `ProviderCapabilities.attachments` |
| U4 | 大文件一次 base64 进 JS | 内存与脚本桥极限 | **≤ N MB 内存注入；更大走 loopback staging** |
| U5 | 发送与上传并行 | 未传完就点发送 | 强制 **waitAttachmentsReady**；芯片显示上传中/失败 |
| U6 | 附件与 Page Context 混一谈 | 概念打架 | 附件 = 本地文件上网页；Page Context = 当前页引用；可并存，芯片样式区分 |

---

## 4. 架构

```
AI 助手侧栏                          AI Bridge                         DeepSeek 标签
┌─────────────────────┐            ┌──────────────────────┐          ┌─────────────────┐
│ 选本地文件 / 拖放    │  HTTP     │ /v1/chat/completions │  evaluate │ File + DataTransfer
│ 芯片条（名/大小/态） │ ────────► │ + meo_attachments     │ ────────► │ → upload_file API
│ 发送文案             │           │ JobQueue 串行         │          │ → 附件卡 ready
└─────────────────────┘            │ Adapter.attach+send  │          │ → sendAndWait
                                   └──────────────────────┘          └─────────────────┘
```

原则（与 Bridge 一致）：

1. 助手**不**直接操作 DOM；只打本机 OpenAI 兼容 API。  
2. 文件字节尽量**不经**多余拷贝：Native 读盘 → 页内一次构造 `File`。  
3. 同一 binding **串行**：先 attach 全部就绪，再填字发送。

### 4.1 页内 JS 契约扩展（`window.__MeoAIBridge`）

```js
{
  // 现有
  probe(), send(text), sendAndWait(text, opts), …

  // 新增
  probeAttachments(): {
    ok, supported, hasFileInput, accept, maxFilesHint?, detail
  },

  // files: [{ name, mime, base64 }] 或 [{ name, mime, stagingUrl }]
  attachFiles(files): { ok, error?, accepted: number },

  attachmentsState(): {
    items: [{ name, metaText, ready, error? }],
    allReady: boolean,
    uploading: boolean
  },

  waitAttachmentsReady({ timeoutMs }): Promise<{ ok, error?, items }>,

  clearAttachments(): { ok },

  // 推荐封装
  attachAndSendAndWait(text, files, opts): Promise<{ ok, text, error? }>
}
```

DeepSeek 实现要点：

- `findFileInput()` → `input[type=file]`（优先作曲区内）  
- `attachFiles`：逐个或批量 `DataTransfer` 赋值 + `change`（若站点一次吃掉 input，则循环）  
- `attachmentsState`：扫描附件条带文本；`ready` ≈ 有文件名且 meta 匹配大小/类型、无 loading  
- 类名哈希失效时：回退到「作曲区内是否出现已知文件名」

### 4.2 Native / HTTP 契约

**推荐（Bridge 扩展字段，助手易用）**：

```json
POST /v1/chat/completions
{
  "model": "bridge__deepseek",
  "messages": [
    { "role": "user", "content": "请总结附件要点" }
  ],
  "meo_attachments": [
    {
      "name": "report.pdf",
      "path": "/Users/me/Documents/report.pdf",
      "mime": "application/pdf"
    }
  ]
}
```

约束：

- `path` **仅本机绝对路径**；服务只读用户显式选中的文件。  
- 校验：存在、可读、扩展名 ∈ probe.accept（或白名单）、大小上限。  
- 非 DeepSeek / `probeAttachments.supported=false` → `400` 明确错误。

**可选兼容（OpenAI 风格 content parts）**：

```json
"content": [
  { "type": "text", "text": "…" },
  { "type": "input_file", "input_file": { "path": "…" } }
]
```

首版以 `meo_attachments` 为主；parts 可后解析进同一管道。

**大文件 staging（AT-3）**：

```text
POST /v1/bridge/files          → { file_id, url, expires_at }
GET  /v1/bridge/files/{id}     → 原始字节（仅 127.0.0.1 + Bearer）
页内：fetch(url) → Blob → File → attachFiles
```

### 4.3 模块职责

| 模块 | 职责 |
|------|------|
| `AIBridgeDOMProvider` | 调用 `attachAndSendAndWait` / 轮询 job |
| `adapters/deepseek.js` | 上传 DOM + 就绪检测 |
| `AIBridgeService` | 解析 `meo_attachments`、读盘、大小校验、注入参数 |
| `BrowserAIAssistantSidebarController` | 回形针、`NSOpenPanel`、拖放、芯片、发送打包 |
| Prefs（可选） | 默认附件目录、单文件大小上限、是否允许附件 |

---

## 5. AI 助手 UI / 交互

### 5.1 MVP（AT-2）

输入卡片（现有 `inputBox`）改造：

```
┌──────────────────────────────────────┐
│ [📄 report.pdf  1.2MB  ×] [🖼 a.png ×] │  ← 芯片条（可横滑）
│                                      │
│  请总结附件里的结论…                   │  ← SBTextView
│                                      │
│  📎          发送    停止             │  ← 回形针在发送左侧
└──────────────────────────────────────┘
```

行为：

| 操作 | 行为 |
|------|------|
| 点 📎 | `NSOpenPanel`；`allowsMultipleSelection=YES`；类型按 DeepSeek accept 子集过滤 |
| 拖文件到输入卡 | 接受 Promise 文件 URL；非法类型 toast |
| 芯片 × | 从待发列表移除（未发送前） |
| 发送 | 有附件：`meo_attachments` + 文案；仅附件无文案：允许（默认文案可空或「请查看附件」） |
| 模型非 DeepSeek | 📎 禁用 + tooltip「当前仅 DeepSeek 网页支持附件」 |
| 上传中 | 发送禁用；状态条「正在上传附件…」；可停止则走现有 cancel |

### 5.2 对话气泡

用户消息下展示只读芯片（文件名 + 大小），不内嵌全文。  
助手回复仍为现有 markdown 气泡。

### 5.3 与 Page Context / Citation

| 类型 | 来源 | 是否上传到 DeepSeek |
|------|------|---------------------|
| 附件 | 本地文件 | **是**（网页 upload） |
| Citation / Page Context | 当前页采集 | **否**（拼进 prompt 文本） |

两者可同时存在：先上传附件，再把 Citation 文本并入 `content`（现有逻辑）。

---

## 6. 更好的功能 / 交互 / UI 建议

按性价比排序，**建议首版就带 ★**：

| # | 建议 | 理由 |
|---|------|------|
| ★1 | **拖放上传**到输入卡 | 比只点回形针更符合桌面习惯；实现成本低 |
| ★2 | **芯片态**：排队 / 上传中 / 就绪 / 失败 | 避免「点了发送却没带上文件」的黑盒 |
| ★3 | **发送前校验** accept + 大小 | 失败在 Meo 侧即时提示，少浪费网页往返 |
| ★4 | **粘贴图片**（⌘V）→ 自动变附件 | 截图问 AI 高频；DeepSeek accept 含常见图片 |
| 5 | 右键文件「用 AI 打开」/ Finder 服务 | 进阶入口；可放 AT-4 |
| 6 | 「仅提取文本进 prompt」降级开关 | 网页上传挂了时的逃生舱；小 txt/md 有用 |
| 7 | 附件与「新对话」策略 | 默认：有附件时可选「新开网页会话再传」，避免污染旧上下文 |
| 8 | Bridge 侧栏「快速测试」也支持选文件 | 方便不打开助手就验 Adapter |
| 9 | 统一 `ProviderCapabilities` 徽章 | 模型下拉旁显示「支持附件」图标 |
| 10 | 多图缩略图预览 | 体验好但非 MVP；先文件名芯片即可 |

**不建议首版做**：

- 直连逆向 `upload_file` 绕过 DOM（易碎、要维护 PoW/Header）  
- 云同步附件库  
- 把任意网页资源 URL 当附件自动下载（安全面大）

---

## 7. 分阶段落地

### AT-0 — Spike（Meo 内复验）

1. 绑定 DeepSeek 标签，注入 runtime + 扩展版 `deepseek.js`。  
2. Native/`evaluateJavaScript` 注入 ≤100KB 的 txt，确认附件卡 + `upload_file`。  
3. `attachAndSendAndWait('用一句话描述附件内容', [file])` 跑通。  
4. **勾选标准**：Meo WKWebView 下 DataTransfer 路径成功；否则改 staging/fetch 方案再进 AT-1。

### AT-1 — Bridge

- 解析 `meo_attachments`  
- 读盘、校验、调用 Adapter  
- 错误码：`attachments_unsupported` / `attach_failed` / `attach_timeout`  
- Bridge 侧栏测试框可附带一个可选文件路径（或稍后 AT-2 再做 UI）

### AT-2 — 助手 UI（含拖放 / 粘贴图）

- 📎 + OpenPanel + 芯片 + 发送打包  
- **拖放**到输入卡、**⌘V 粘贴图片**（与 📎 同进本阶段）  
- 非 DeepSeek 禁用  
- 用户气泡展示附件摘要

### AT-3 — 体验

- 多文件队列体验打磨  
- staging URL（若 chunk 注入不够）  
- 更稳的就绪检测（可选 hook `upload_file` 响应）

### AT-4 — 扩展

- Kimi / 豆包 / ChatGPT 等按站适配  
- `ProviderCapabilities.attachments`  
- 可选「文本降级」与 Finder 服务

---

## 8. 验收清单（DeepSeek MVP）

1. 助手选 1 个 pdf/txt → 芯片显示 → 发送 → DeepSeek 页出现同名附件卡 → 模型回复与文件相关。  
2. 仅文字发送行为与现网一致（无附件回归）。  
3. 上传未完成点发送：本地拦截或 Bridge 等待，不出现「无附件的空问」。  
4. 取消任务：不留下 Bridge 死锁；页内尽量 `clearAttachments` 或提示用户手动叉掉。  
5. 换到非 DeepSeek 模型：无法添加附件。  
6. 超限/拒收扩展名：Meo 侧明确错误文案。

---

## 9. 决策回执（已确认）

| ID | 定稿 |
|----|------|
| D1 | 协议用顶层 **`meo_attachments`**（`name` + `path` + 可选 `mime`） |
| D2 | **允许**无文案只发附件；网页侧若拒空文案则 Adapter 回退为「请查看附件」 |
| D3 | 直接开工 AT-0→AT-2（含 Meo WKWebView 复验） |
| D4 | MVP **单文件 ≤20MB**；超限 Meo 侧拦截 |
| D5 | **拖放 + 粘贴图片**与 📎 同进 AT-2 |
| D6 | 大文件经 **页内分片 base64 注入**（避免 chat.deepseek.com → localhost CORS）；AT-3 再评估其它通道 |

---

## 附录 A — 探测时关键选择器（易变）

| 用途 | 选择器 / 线索 |
|------|----------------|
| file input | `input[type=file]` |
| 回形针 | `.aaff8b8f .ds-button.ds-button--iconLabelPrimary` |
| 文件名 | `.e70accd6` |
| 大小/类型 | `._7103a25` |
| 附件卡 | `div._25c7358.dafb6286` |
| 上传 API | `POST /api/v0/file/upload_file` |
| 元数据 | `GET /api/v0/file/fetch_files?file_ids=` |

选择器以 Adapter 内封装为准；产品逻辑依赖「文件名可见 + 上传网络完成」双信号更稳。

## 附录 B — 对标

开源 Uni-CLI DeepSeek adapter 亦采用：点附件控件 + `setFileInput`。  
Meo 无 CDP，故采用 **页内 File + DataTransfer**（本探测已验证等价效果）。
