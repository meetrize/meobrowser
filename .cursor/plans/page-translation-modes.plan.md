---
name: 网页翻译多模式
overview: 按 PT-0→PT-2 落地替换/双语对照/即指即译：共享抽取+翻译管道，Bilingual/Hover 用 page-translation.js 呈现；不依赖 Safari 私有网页翻译 entitlement。依据 docs/minimal-browser/page-translation-modes-design.md。
todos:
  - id: pt-0-service
    content: PT-0：抽出 BrowserTextTranslationService；InPageTranslator 改用 Service；make browser
    status: completed
  - id: pt-0-pipeline
    content: PT-0：BrowserTranslationPipeline（抽取→翻译→Replace apply）；Controller 改调 Pipeline；取消/超时保留；make browser
    status: in_progress
  - id: pt-1-js-bilingual
    content: PT-1：page-translation.js（clear/applyBilingual）+ Resources 拷贝 Makefile；Pipeline Bilingual apply；菜单「双语对照」；make browser
    status: pending
  - id: pt-2-hover
    content: PT-2：applyHover 浮层+节流；菜单「即指即译」；UIState/tooltip；模式互斥；make browser
    status: pending
  - id: pt-3-docs-verify
    content: PT-3：勾选 development-plan；更新 design 状态与 docs/README 互链；手测清单；make browser && make verify
    status: pending
isProject: true
---

# 网页翻译多模式 — Cursor 自动开发计划

> **依据**：[page-translation-modes-design.md](docs/minimal-browser/page-translation-modes-design.md) · [page-translation-modes-development-plan.md](docs/minimal-browser/page-translation-modes-development-plan.md)  
> **构建**：每阶段结束执行 `make browser`；最终尽量 `make verify`。  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）。  
> **范围**：**PT-0～PT-2（首版）** + PT-3 文档；不做动态增量译、系统 Translation 主引擎、选区翻译。

## Goal

在现有地址栏翻译上增加 **双语对照** 与 **即指即译**；与 **替换译文** 共用抽取/翻译管道；页面 URL 不变。

## Scope

| 做 | 不做（本计划） |
|----|----------------|
| PT-0 管道重构（Service + Pipeline） | Safari WBS 双语/悬停 |
| PT-1 双语对照（英下中） | 左右分栏 / OCR |
| PT-2 即指即译（预译 + hover） | 边悬停边请求 |
| PT-3 文档与验收 | SPA Mutation 增量（P3 以后） |

## 行为定稿（实现时必须遵守）

1. **三种模式互斥**：Replace / Bilingual / Hover。  
2. **恢复原文 V1**：`reload`。  
3. **Bilingual / Hover**：禁止用 TextManipulation **覆盖**原文；用 JS 打 `data-meo-tid` 并插入/浮层。  
4. **Replace**：继续 `completeTextManipulationForItems:`。  
5. **Safari WBS**：仅可选用于 Replace；Bilingual/Hover 不走 WBS。  
6. **进度 UI**：常驻「正在翻译网页…」；可取消；超时解锁。  
7. **脚本**：`SimpleBrowser/Translation/Resources/page-translation.js` → bundle Resources（对齐 find-in-page）。  
8. **匹配失败的段落**：跳过，不中断整页；必要时 Toast「部分段落未译出」。

## 现有代码锚点

| 模块 | 路径 |
|------|------|
| 菜单/状态 | `Translation/BrowserPageTranslationController.*` |
| 页内替换 | `Translation/BrowserInPageTranslator.*` |
| 窗口接线 | `BrowserWindowController`（translate 按钮） |
| Toast | `BrowserTransientToast`（已有 persistent） |

## 实现顺序（Agent）

### PT-0

1. 新建 `BrowserTextTranslationService`，迁出 HTTP 翻译。  
2. `BrowserInPageTranslator` 依赖 Service。  
3. 新建 `BrowserTranslationPipeline`：收集 items → 译 → Replace apply。  
4. Controller 的「翻译成中文」走 Pipeline；保留取消/超时/常驻 Toast。  
5. `make browser`。

### PT-1

1. 编写 `page-translation.js`：`clear` / `applyBilingual`。  
2. Makefile 拷贝 js。  
3. Pipeline 支持 Bilingual；段落匹配打标 + 插入译文行。  
4. 菜单项「双语对照（英 / 中）」；刷新 button tooltip。  
5. `make browser`；手测双语 + reload。

### PT-2

1. JS `applyHover` + 浮层。  
2. 菜单「即指即译」；UIState。  
3. 模式切换：已 translated 时先 reload 再开新模式（或 clear 后重跑 Pipeline）。  
4. `make browser`；手测悬停。

### PT-3

1. 勾选 development-plan；design 状态改为已实现。  
2. 更新 `docs/README.md` 表项。  
3. `make browser`（及 `make verify` 若存在）。

## 手测

1. Replace → 整页中文 → 显示原始网页  
2. Bilingual → 英下有中 → 显示原始网页  
3. Hover → 仅悬停见译 → 显示原始网页  
4. 翻译中取消 → 可重试  
5. worldcrunch.com 无 Google 屏蔽页  
6. 新标签页按钮禁用  

## 完成定义

- [ ] PT-0～PT-2 代码合并可构建  
- [ ] 上述手测通过  
- [ ] 设计/开发计划/README 已更新  
- [ ] Cursor plan todos 全部 completed  
