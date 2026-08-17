# 网页翻译多模式（替换 / 双语对照 / 即指即译）— 设计方案

> 目标：在地址栏翻译入口上，提供三种呈现模式——**替换译文**、**双语对照**、**即指即译**；共用「抽取 → 翻译」管道，不改页面 URL、不走 Google 网页代理。  
> 状态：**已实现**  
> 开发计划：[page-translation-modes-development-plan.md](page-translation-modes-development-plan.md)  
> Cursor 计划：[.cursor/plans/page-translation-modes.plan.md](../../.cursor/plans/page-translation-modes.plan.md)  
> 关联：现有 `SimpleBrowser/Translation/`（`BrowserPageTranslationController` · `BrowserInPageTranslator`）

---

## 1. 方案定位

### 1.1 产品一句话

**同一套译句结果，三种阅读方式**：整页换成中文、英上中下对照、或保持英文悬停见译。

### 1.2 要解决的痛点

| 用户场景 | 痛点 | 本方案价值 |
|----------|------|------------|
| 快速扫原文站 | 只想看中文 | 替换模式（已有，保留） |
| 学语言 / 核对术语 | 替换后找不到原文 | 双语对照：段落下挂中文 |
| 沉浸读英文 | 不想整页变中文，但偶遇生词 | 即指即译：悬停出译文 |
| 反爬站点 | Google 网页代理被屏蔽 | 页内抽取 + 文本 API（已落地） |

### 1.3 做什么 / 不做什么

| 做（V1） | 不做（明确边界） |
|----------|------------------|
| 三种互斥模式 + 菜单入口 | 调用 Safari App 内置「网页翻译」完整引擎（需 private entitlement） |
| TextManipulation 抽取 + 文本翻译后端 | 依赖 `com.apple.private.translation` |
| 双语：原文下插入译文行 | 左右分栏、PDF/图片 OCR 翻译 |
| 即指即译：全文译完后 hover 浮层 | 未预译时边悬停边请求（V1） |
| 显示原始网页 / 取消翻译 | 整站自动翻译偏好、跨标签同步译文缓存 |
| 常驻进度 + 可取消（已有交互） | 自研完整机器翻译模型 |

### 1.4 与 Safari 内置翻译的关系

| 问题 | 结论 |
|------|------|
| Safari 能否直接提供双语 / 即指即译？ | **不能**。Safari 仅做 DOM 文本替换，无对照与悬停产品形态 |
| 能否复用什么？ | **TextManipulation 抽取**（与 Safari 同源 SPI）；翻译服务第三方 App 常不可用 |
| V1 策略 | 抽取用 WebKit SPI；翻译用现有文本 API，抽象为可替换的 `BrowserTextTranslationService` |

### 1.5 设计原则

1. **管道共享**：抽取与翻译只做一次；模式只决定呈现。  
2. **原站优先**：不改变 URL / 主文档 origin。  
3. **可恢复**：任一模式均可「显示原始网页」（reload 或卸注入）。  
4. **失败可解释**：部分段落失败不阻塞整页；Toast 提示。  
5. **轻量**：注入脚本按需；离开模式或导航后清理。

---

## 2. 现状基线（代码）

| 项 | 现状 |
|----|------|
| 入口 | 地址栏内翻译按钮（星标右侧）+ 弹出菜单 |
| 菜单 | 翻译成中文 / 首选语言 / 显示原始网页；翻译中可取消 |
| 引擎 | `BrowserInPageTranslator`：TextManipulation + Google 文本 API（Lingva 回退） |
| Safari 路径 | 软链 `WBSTranslationContext`；地区/entitlement 不可用时跳过 |
| 交互 | 常驻「正在翻译网页…」、按钮 tint、60s 超时 |
| 模式 | **仅替换译文** |

---

## 3. 三种模式

### 3.1 替换译文（Replace）— 已有

- 行为：`completeTextManipulation` 将 token 内容换成译文。  
- 视觉：页面显示中文。  
- 恢复：reload。

### 3.2 双语对照（Bilingual）

- 行为：保留原文节点；在每个可译块**下方**插入译文行。  
- 视觉：英（原样式）→ 中（次要色、略小字号）。  
- 实现要点：  
  - **不要**用 TextManipulation 覆盖原文。  
  - 应用前给节点打 `data-meo-tid`；JS 插入 `<div class="meo-tr-bilingual" data-meo-tid="…">译文</div>`。  
  - 样式隔离：class 前缀 `meo-tr-`；尽量不破坏原站 flex/grid。  
- 恢复：移除所有 `.meo-tr-bilingual` 与 `data-meo-tid`（或 reload）。

### 3.3 即指即译（Hover）

- 行为：页面**仍显示英文**；后台完成全文翻译后，注入 `{ tid → 中文 }`；鼠标悬停带 `data-meo-tid` 的块时显示浮层。  
- 视觉：原文不变；浮层固定/跟随（`position: fixed`），次要背景、可读字号。  
- 实现要点：  
  - 同样不覆盖原文。  
  - `mouseover` / `mousemove` 节流（≈50ms）；移出延迟 150–200ms 隐藏。  
  - 滚动时更新位置或暂时隐藏。  
- 恢复：移除标记、映射与浮层脚本（或 reload）。

### 3.4 模式互斥

同一 WebView 同时只激活一种模式。切换模式前：先清理上一模式注入，再重新「抽取→翻译→应用」。

**V1 定稿**：切换模式或「显示原始网页」优先 `reload`（最稳）；同页 `clear()` 作可选优化。

---

## 4. 架构

```
BrowserPageTranslationController   菜单 / UI 状态 / 模式选择
        │
        ▼
BrowserTranslationPipeline         抽取 → 译句 → 按模式 apply
        │
        ├── BrowserTextTranslationService   HTTP 文本翻译（可替换）
        ├── BrowserInPageTranslator         Replace 模式（现有，可收入 Pipeline）
        └── page-translation.js             Bilingual / Hover 注入与清理
```

### 4.1 核心数据

```objc
typedef NS_ENUM(NSInteger, BrowserTranslationPresentationMode) {
    BrowserTranslationPresentationModeReplace = 0,
    BrowserTranslationPresentationModeBilingual,
    BrowserTranslationPresentationModeHover,
};

// BrowserTranslationUnit：unitID / sourceText / translatedText
```

每 WebView 记录：`presentationMode`、是否 translating / translated。

### 4.2 应用策略

| 模式 | 应用 |
|------|------|
| Replace | `completeTextManipulationForItems:`（现状） |
| Bilingual | JS `MeoTranslation.applyBilingual(units)` |
| Hover | JS `MeoTranslation.applyHover(units)` |

### 4.3 脚本职责（`page-translation.js`）

- 打标 / 应用双语 / 应用悬停 / `clear()`  
- 仅用户启用翻译后注入（对齐 Find-in-Page：不常驻所有页）

---

## 5. UI / 菜单

```
翻译成中文              → Replace
双语对照（英 / 中）      → Bilingual
即指即译                → Hover
────────
首选语言 ▸
────────
显示原始网页
取消翻译                （translating 时）
```

| 状态 | tint | tooltip |
|------|------|---------|
| 空闲 | secondary | 翻译网页 |
| 翻译中 | accent | 正在翻译…（打开菜单可取消） |
| Replace 完成 | blue | 已显示译文 |
| Bilingual 完成 | blue | 双语对照 |
| Hover 完成 | blue | 即指即译（悬停显示译文） |

---

## 6. 生命周期

1. 选模式 → 常驻进度 → Pipeline 抽取 → 批量翻译。  
2. 成功 → apply → 标记 translated + mode → Toast「翻译完成」。  
3. 取消 / 超时 → 清理 + Toast。  
4. `didCommitNavigation` → 取消任务 + 清除模式态。  
5. 「显示原始网页」→ 取消 + reload（V1）。

---

## 7. 风险与对策

| 风险 | 对策 |
|------|------|
| 站点 CSS 挤爆布局 | 译文块保守样式；单块失败跳过 |
| TextManipulation id 不稳定 | 以自研 `data-meo-tid` 为准 |
| 动态加载内容 | V1 不增量；P3 MutationObserver |
| 翻译 API 失败/墙 | Lingva 回退；失败块不绑定 |
| 与页内查找冲突 | P2 手测；必要时互斥提示 |
| 私有 SPI 变更 | Bilingual/Hover 主要依赖 JS |

---

## 8. 验收标准（产品）

1. worldcrunch.com 等：三种模式均不改 URL，不被代理页拦截。  
2. 双语：可见英+中；「显示原始网页」后恢复。  
3. 即指即译：默认只见英文；悬停出中文浮层。  
4. 翻译中可取消；完成后可再开另一模式。  
5. `make browser` 通过；新标签页入口禁用。

---

## 9. 实现索引（落地后更新）

| 模块 | 路径 |
|------|------|
| 控制器 | `Translation/BrowserPageTranslationController.*` |
| Pipeline | `Translation/BrowserTranslationPipeline.*` |
| 文本翻译 | `Translation/BrowserTextTranslationService.*` |
| Replace 薄封装 | `Translation/BrowserInPageTranslator.*`（转发 Pipeline Replace） |
| 页面脚本 | `Translation/Resources/page-translation.js` |
| 菜单/按钮 | `BrowserWindowController` |
