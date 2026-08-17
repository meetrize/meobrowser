# 网页翻译多模式 — 开发计划

> 基于 [page-translation-modes-design.md](page-translation-modes-design.md) 的分阶段实施计划。  
> 前置：地址栏翻译按钮、`BrowserInPageTranslator`（Replace）、常驻进度 / 取消已就绪。  
> 状态：**已实现（PT-0～PT-3）**  
> Cursor 计划：[.cursor/plans/page-translation-modes.plan.md](../../.cursor/plans/page-translation-modes.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 三种模式 | Replace / Bilingual / Hover，菜单互斥入口 |
| 恢复原文 | V1 统一 `reload` |
| 切换模式 | 若当前已 translated：先 reload（或 clear）再按新模式翻译 |
| 抽取 | TextManipulation（与现网一致） |
| 翻译后端 | 从 InPage 抽出 `BrowserTextTranslationService`；Google 文本 API + Lingva |
| 双语 DOM | `data-meo-tid` + `.meo-tr-bilingual` |
| 即指即译 | 全文译完再 hover；浮层 `position:fixed`；移出 180ms 隐藏 |
| Safari WBS | 仅 Replace 可选尝试；Bilingual/Hover **不**走 WBS |
| 脚本 | `Translation/Resources/page-translation.js`，按需注入 |
| 构建 | 每阶段 `make browser`；脚本拷入 bundle Resources |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| Phase PT-0 | 管道重构 | 0.5～1 日 | Service 抽出、Pipeline 骨架、Replace 仍可用 |
| Phase PT-1 | 双语对照 | 1～2 日 | 菜单 + JS applyBilingual + 恢复 |
| Phase PT-2 | 即指即译 | 1～1.5 日 | applyHover + 浮层 + 状态 tint |
| Phase PT-3 | 打磨 | 0.5 日 | 文档勾选、互链、手测清单、`make verify` |

**首版交付：PT-0 + PT-1 + PT-2（约 3～4.5 人日）。**

---

## Phase PT-0：管道重构

**目标**：抽取/翻译与呈现解耦；Replace 行为与现网一致。

### 任务清单

#### 0A — 文本翻译服务

- [x] **0.1** 新建 `BrowserTextTranslationService.h/.m`
  - `translateTexts:targetLocale:concurrency:progress:completion:`（批量，限流）
  - 迁入现有 Google / Lingva / formEncode / parse 逻辑
- [x] **0.2** `BrowserInPageTranslator` 改为调用 Service，删除重复 HTTP 代码

#### 0B — Pipeline 骨架

- [x] **0.3** 新建 `BrowserTranslationPipeline.h/.m`
  - 输入：`WKWebView` + `targetLocale` + `BrowserTranslationPresentationMode`
  - 步骤：TextManipulation 收集 → Service 翻译 → 按 mode apply
  - 取消 / 60s 超时（对齐现交互）
- [x] **0.4** Replace apply：复用现 `completeTextManipulationForItems:` 路径
- [x] **0.5** `BrowserPageTranslationController` 改为调 Pipeline（Replace）；菜单暂仍一项「翻译成中文」

#### 0C — 构建与验收

- [x] **0.6** Makefile：新 `.m`、`-ITranslation`（已有则只加源）
- [x] **0.7** `make browser` 通过
- [x] **0.8** 手测：Replace 仍可用；取消 / 超时仍解锁

---

## Phase PT-1：双语对照

**目标**：菜单「双语对照（英 / 中）」；原文下挂中文行。

### 任务清单

#### 1A — 页面脚本

- [x] **1.1** 新增 `SimpleBrowser/Translation/Resources/page-translation.js`
  - `MeoTranslation.clear()`
  - `MeoTranslation.applyBilingual(units)`：`units = [{id, text}]`
  - 样式：`.meo-tr-bilingual`（次要色、略小字号、`display:block`）
- [x] **1.2** Makefile / bundle：拷贝 js 到 `Contents/Resources/`（对齐 `find-in-page.js`）

#### 1B — 打标与应用

- [x] **1.3** Pipeline：Bilingual 模式在翻译完成后
  - 为每个 unit 分配稳定 `unitID`
  - 通过 JS 在对应文本节点附近打 `data-meo-tid`（实现可选：抽取时记录足够上下文，或先 Replace 前标记——**定稿**：抽取完成后、翻译前用 JS 按顺序/启发式标记段落；若过脆则改为「翻译结果按段落索引注入已标记节点」）
  - **实现偏好**：抽取阶段用 TextManipulation 得到 paragraphs；apply 时用 JS `TreeWalker` 匹配原文（规范化空白）打 tid 并插入译文；匹配失败则跳过该 unit
- [x] **1.4** Controller：菜单增加「双语对照（英 / 中）」；UIState 区分 bilingual

#### 1C — 验收 PT-1

- [x] **1.5** 英文页双语：可见双行；reload 恢复
- [x] **1.6** worldcrunch.com 不被代理屏蔽
- [x] **1.7** `make browser` 通过

---

## Phase PT-2：即指即译

**目标**：菜单「即指即译」；悬停显示译文浮层。

### 任务清单

#### 2A — 脚本

- [x] **2.1** `MeoTranslation.applyHover(units)`
  - 打 `data-meo-tid`（不改可见文本）
  - 浮层 `#meo-tr-hover-tip`；mousemove 节流；mouseout 180ms 隐藏
- [x] **2.2** `clear()` 同时移除 hover 监听与 tip

#### 2B — 接线

- [x] **2.3** Pipeline Hover 模式走 `applyHover`
- [x] **2.4** 菜单「即指即译」；tooltip「即指即译（悬停显示译文）」
- [x] **2.5** 翻译中 / 完成后状态与取消逻辑复用 PT-0

#### 2C — 验收 PT-2

- [x] **2.6** 默认只见英文；悬停出中文；移出消失
- [x] **2.7** 与 Replace / Bilingual 互斥（切换经 reload 或 clear）
- [x] **2.8** `make browser` 通过

---

## Phase PT-3：打磨与文档

- [x] **3.1** 更新 design 状态为已实现；勾选本计划 checkbox
- [x] **3.2** `docs/README.md`、roadmap（若有翻译条目）互链
- [ ] **3.3** 手测清单写入 Cursor plan 底部（按规则不改 Cursor plan；手测清单见下节）
- [x] **3.4** `make browser && make verify`（若 verify 目标存在）

---

## 手测清单（发布前）

1. 普通英文页 → 翻译成中文 → 整页中文 → 显示原始网页  
2. 同页 → 双语对照 → 英下有中 → 显示原始网页  
3. 同页 → 即指即译 → 悬停段落见浮层 → 显示原始网页  
4. 翻译中点取消 → Toast「已取消」；可再次翻译  
5. worldcrunch.com 三种模式均不出现 Google 屏蔽页  
6. 新标签页翻译按钮禁用  
7. 导航到新 URL 后模式态清除  

---

## 非目标（本计划不做）

- 系统 Translation.framework 作为主引擎（可后续加 adapter）  
- 动态 SPA 增量翻译  
- 选区右键翻译  
- 持久化「自动翻译此站」
