# AI 页面上下文（Page Context）— 开发计划

> 基于 [ai-page-context-design.md](ai-page-context-design.md)（**已确认** · 2026-10-29）。  
> 对齐助手计划：[ai-assistant-development-plan.md](ai-assistant-development-plan.md) B1 / B2 / Phase D。

---

## 决策回执（D1–D6）

| ID | 定稿 |
|----|------|
| D1 | 默认 **Article**；质量低降级 |
| D2 | 「全部引用」允许 + 二次确认 + 预算裁剪 |
| D3 | Bundle **不**默认落盘 |
| D4 | PC-2：**L3 按需**；L4 观望 |
| D5 | Recipe 列表管理，非重编辑器 |
| D6 | **不**新建 trailing kind；嵌助手资源盘 |

---

## Phase PC-0 — 正文摘要（= 助手 B1）

**目标**：右键 / 侧栏「总结该网页」真正基于正文，经 Citation 注入，不刷全文气泡。

- [x] **0.1** 页内 JS：`window.__MeoPageContext.capture` 最小集（`meta` + `article` + 质量 flag）
- [x] **0.2** `AIPageContextCapturer` + 按 `tabId` 内存 Store（stale：同 tab 导航）
- [x] **0.3** Citation 扩展：`pageMeta` / `pageArticle` + `promptBlock` / `chipLabel`
- [x] **0.4** 内置 Recipe `summarize-page`（ObjC 常量表；PC-2 再加用户 JSON）
- [x] **0.5** `PromptBuilder`：systemHint + 引用块 + userPrompt；article 24k 截断
- [x] **0.6** 侧栏：快捷「总结该网页」；发送气泡「📎 N 条引用 · …」
- [x] **0.7** 右键：「总结该网页」（始终采正文；无选区「总结」亦走同一路径）
- [x] **0.8** Article 失败降级 + 状态条文案
- [x] **0.9** Makefile / 接线 `BrowserWebView` 取当前 webView；编译通过

**验收**

1. 打开长文页 → 「总结该网页」→ 回复依据正文而非仅标题 URL  
2. 未绑定模型：填入提示 + 挂引用，不发送  
3. 用户气泡无全文 HTML/正文倾泻  

---

## Phase PC-1 — 可勾选 Bundle（含 B2 问答本页）

- [x] **1.1** 层：`outline` / `html`（截断）/ `markdown`（可选）
- [x] **1.2** 助手底部「本页上下文」折叠条 + 资源盘勾选 ↔ 芯片
- [x] **1.3** 「重新采集」；导航 stale 橙提示
- [x] **1.4** Recipe `ask-page`；侧栏 + 右键「问答本页…」（默认不 autoSend）
- [x] **1.5** 「全部引用」二次确认 + 总预算裁剪提示
- [x] **1.6** 芯片 popover 预览（字数 / 截断说明 / 前若干行）

**验收**

1. 可只勾正文问答；可加 HTML 后重发  
2. 导航后提示过期，重采后 chip 内容更新  

---

## Phase PC-2 — 资源索引 + 用户 Recipe

- [x] **2.1** L1 资源索引（script / css / json / img）+ 内联全文  
- [x] **2.2** L3：用户点「加载」再拉同源文本；单资源 Citation kinds  
- [x] **2.3** `/` 斜杠选 Recipe；`@` 提及层/资源  
- [x] **2.4** 用户 Recipe CRUD（Application Support）；「更多 ▾ → 管理配方」  
- [x] **2.5** 内置：`regex-extract`、`outline-page`、`extract-facts`  
- [x] **2.6** 隐私档位偏好（严格 / 标准 / 开发）最小实现  

**验收**

1. 勾选页内 JSON-LD 可单独引用并提问  
2. 自定义「总结该网页」文案保存后快捷按钮可用  

---

## Phase PC-3 — Skill 雏形 + 生态

- [x] **3.1** Recipe + 可选 preprocess 挂钩（设计预留）  
- [x] **3.2** 导出 Bundle；「应用到页面爬虫」草稿字段  
- [x] **3.3** `meobrowser://ai?action=summarize`  
- [x] **3.4** 点选 DOM 区域 → subtree Citation（复用 Scraper picker 轮廓）  
- [x] **3.5**（可选）Regex Lab 本地预览  

---

## 代码落点（实现时）

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/AIAssistant/PageContext/` | Capturer / Store / PromptBuilder / 页内 JS |
| `SimpleBrowser/AIAssistant/Recipes/` | 内置 `summarize-page` 等 |
| `SimpleBrowser/AIAssistant/AIAssistantCitation.*` | 新 kinds |
| `SimpleBrowser/AIAssistant/BrowserAIAssistantPrompts.*` | 改读 Recipe |
| `SimpleBrowser/AIAssistant/BrowserAIAssistantSidebarController.*` | 资源盘 + 快捷按钮 |
| `SimpleBrowser/Tabs/BrowserWebView.m`（或 WC） | 右键菜单项 |

---

## 建议开工顺序

先做 **PC-0**（闭环可演示）→ PC-1（资源盘，产品成型）→ PC-2 → PC-3。
