# AI 附件 — 开发计划

> 基于 [ai-attachment-design.md](ai-attachment-design.md)（**已确认** · 2026-10-29）。  
> 对齐：Bridge / 助手；首发 **DeepSeek**。

---

## 决策回执

见设计文档 §9（D1–D6）。

---

## Phase AT-0 — DeepSeek Adapter 附件能力

- [x] **0.1** `deepseek.js`：`probeAttachments` / `attachFiles` / `attachmentsState` / `waitAttachmentsReady` / `clearAttachments` / `attachAndSendAndWait`
- [x] **0.2** 页内 `File` + `DataTransfer` + `change`；就绪 = 作曲区出现文件名且无上传中迹象
- [x] **0.3** 空文案回退「请查看附件」
- [x] **0.4** Makefile 已拷贝 adapter（沿用现路径）

**验收**：Meo 绑定 DeepSeek 后，经 Bridge 注入小 txt，页内出现附件卡并可回复。

---

## Phase AT-1 — Bridge HTTP + 注入

- [x] **1.1** 解析 `meo_attachments`；读盘；扩展名/大小（20MB）校验
- [x] **1.2** `AIBridgeDOMProvider` 分片注入 base64 → `attachAndSendAndWait`
- [x] **1.3** `AIBridgeJobQueue` 携带 attachments
- [x] **1.4** 允许「有附件且文案为空」；错误类型 `attachments_unsupported` / `attach_failed` / `attach_timeout`
- [x] **1.5** 非 deepseek binding 带附件 → 400

**验收**：`curl` 带 `meo_attachments` 路径可跑通一轮。

---

## Phase AT-2 — 助手 UI

- [x] **2.1** 输入区「附件」+ `NSOpenPanel`（多选）
- [x] **2.2** 待发芯片条（名/大小/移除）
- [x] **2.3** 拖放文件到输入卡（输入框优先接文件，避免当文字插入）；⌘V / 菜单粘贴图片（临时文件）
- [x] **2.4** `BrowserAIAssistantClient` 发送 `meo_attachments`
- [x] **2.5** 非 DeepSeek：📎 禁用、拖放/粘贴图拒绝并提示；切走模型时清空待发附件
- [x] **2.6** 编译通过

**验收**：见设计 §8。

---

## Phase AT-3 / AT-4

见设计 §7（大文件通道打磨、多 Provider）。
