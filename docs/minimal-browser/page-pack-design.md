# 页面插件（Page Pack）— 设计方案

> 目标：在 MeoBrowser 内提供 **Stylish（User CSS）+ Tampermonkey（User JS）合一** 的「页面插件」能力：按 URL 匹配注入样式与脚本，支持远程安装与本地完全开放式编辑，保存后即时生效。  
> 状态：**已确认（按推荐定稿）** · 2026-08-21  
> 开发计划：[page-pack-development-plan.md](page-pack-development-plan.md) · Cursor：[.cursor/plans/page-pack.plan.md](../../.cursor/plans/page-pack.plan.md)  
> 关联：[professional-features-roadmap.md](professional-features-roadmap.md)（§3.9「每站点 User CSS/JS」）· [assist-sidebar-design.md](assist-sidebar-design.md) · [companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md) · [web-inspector-design.md](web-inspector-design.md)

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| 按 URL 注入 CSS（类 Stylish） | **可行**。CSS 经 JS 插入 `<style>`，或 `evaluateJavaScript` 热更新 |
| 按 URL 注入 JS（类 Tampermonkey） | **可行**。主路径用导航时机注入 + 可选 `WKUserScript`；V1 不做完整 GM API |
| 同一插件多文件（CSS+JS）同时注入 | **可行**。以「Pack」为单元，含 `manifest` + 多文件 |
| 右侧侧栏管理 + 内联编辑 | **可行**。复用 trailing 侧栏槽；与通知 / 助手 / 历史 **互斥** |
| 远程推荐安装 | **可行（分阶段）**。先静态 Catalog JSON；不爬 GreasyFork |
| 保存立刻生效 | **可行**。当前页热注入 + 后续导航按匹配重注 |

**产品名建议**：**页面插件**（对外）；代码 / 目录名 **PagePack**。  
**产品路径**：先做 **本地 Pack CRUD + 匹配注入 + 侧栏编辑（PP-MVP）** → 再做 **远程发现安装（PP-1）** → 再做 **导入兼容 / 高级运行时（PP-2）**。

---

## 1. 需求理解（你的原始设想）

| # | 你的需求 | 理解 |
|---|---------|------|
| 1 | 类 Stylish：关联当前网址的 CSS 注入页面 | 按 match 规则把样式写进文档 |
| 2 | 类 Tampermonkey：关联当前网址的 JS 注入页面 | 按 match + run-at 执行脚本 |
| 3 | 一个插件可同时含 CSS/JS，多文件一起注入 | 插件 = 包（Pack），不是单文件 |
| 4 | 可安装远程已发布插件 | Catalog / 直链安装 |
| 5 | 已安装与自建插件可完全自定义 | 侧栏内改文件、增删文件、开关启用 |
| 6 | 侧栏上/中/下：推荐 / 本地 / 编辑器 | 管理与编辑同屏；保存立即生效 |

以上理解正确。下文在此基础上做 **体验与架构定稿**，解决窄侧栏三叠板拥挤、注入时机、安全与和现有 chrome 冲突等问题。

---

## 2. 相对原始设想的优化原则

| # | 原始点 | 风险 | 更优做法 |
|---|--------|------|----------|
| U1 | 固定「上中下」三面板永远同时展开 | 360px 侧栏里推荐列表 + 本地列表 + 代码编辑器互相挤压，编辑体验差 | **双模式**：浏览态（发现 / 本页 / 全部）与 **编辑态（选中 Pack 后全高编辑器）**；编辑态顶栏返回，不必永久三等分 |
| U2 | 「推荐」与「本地」并列置顶 | 日常改自己的插件时，推荐区占高度 | 默认落在 **「本页」**（当前 URL 匹配的已启用 Pack）；「发现」为独立分段 |
| U3 | 点击本地才显示编辑器 | 正确，但应强化「当前页生效」反馈 | 顶栏徽标：**本页 N 个生效**；列表行显示匹配状态 / 启用开关 |
| U4 | 保存立刻生效 | 仅 reload 体验差；仅热注入可能漏 SPA | **热注入当前文档 + 标记需对后续导航重匹配**；提供「刷新页面」次要按钮 |
| U5 | 远程插件无限开放 | 任意远程 JS = 完整页面权限 | 安装确认页展示 match 范围与权限摘要；默认禁止 `@match *://*/*` 无确认安装 |
| U6 | 对标完整 Tampermonkey | GM_*、跨域、@require、沙箱成本高 | V1：**纯页面世界注入**（`WKContentWorld.pageWorld`）；无 GM_xmlhttpRequest；`@require` 仅本地文件或安装时内联 |
| U7 | 新建工具栏图标 | 与现有 ActionGroup / 侧栏槽竞争 | **建议有独立入口**（页面插件与「助手」语义不同）；接入 `BrowserTrailingSidebarSlot` 新 kind |

---

## 3. 方案定位

### 3.1 产品一句话

**页面插件**：把「改样式」和「跑脚本」收成一个可安装、可开关、可多文件编辑的 Pack——打开侧栏就能管当前站，改完保存立刻看见效果。

### 3.2 与现有能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| 路线图「每站点 User CSS/JS」P3 | 未做 | **正式落地并升级为 Pack 模型** |
| `WKUserScript` / `evaluateJavaScript` | 登录助手、验证码、查找、透明模式等已用 | Pack 注入复用同一套 WebKit 能力；**独立模块**，不塞进 LoginAssist |
| Trailing 侧栏槽 | 通知 / 助手 / 历史互斥 | **新增** `BrowserTrailingSidebarKindPagePack` |
| SBKit 文本控件 | 强制 | 编辑器外的元数据输入走 `SBTextField`；代码区可用 `SBTextView` 或自绘等宽编辑器（见 §6.4） |
| Web Inspector | 已有 | 调试用户脚本时仍可用系统检查器；Pack 侧栏不替代 Inspector |

### 3.3 做什么 / 不做什么

| 阶段 | 做 | 不做 |
|------|----|------|
| **PP-MVP** | Pack 模型 + 本地存储；match/exclude；多文件 CSS/JS；启用开关；侧栏「本页 / 全部」+ 编辑态；保存热生效；新建 / 删除 Pack | 远程 Catalog；GreasyFork 一键；GM API；云同步 |
| **PP-1** | 远程 Catalog（JSON）；安装预览与确认；更新检查（可选） | 爬取第三方站点 HTML；付费商店 |
| **PP-2** | 导入 `.user.js` / UserCSS 元数据；`@require` 安装时打包；isolated world 选项；导出 zip | 完整 Chrome Extension；后台 Service Worker；任意跨域特权 |

### 3.4 设计原则

1. **当前页优先**：打开侧栏默认看「本页会跑哪些 Pack」。  
2. **Pack 是唯一单元**：样式与脚本同包管理，避免 Stylish / TM 两套 UI。  
3. **编辑态给足高度**：写代码时列表收起，而不是硬塞三栏。  
4. **人在回路**：远程安装必确认；危险 match 必二次确认；删除需确认。  
5. **即时可感**：保存 → 当前页立刻应用；开关 → 立刻注入或撤销（CSS 可卸；JS 撤销可能需刷新，见 §7）。  
6. **单槽侧栏**：与通知 / 助手 / 历史互斥。  
7. **安全默认**：新建 Pack 默认 match = **当前页 origin + path 前缀**，而非 `*://*/*`。

---

## 4. 用户体验（定稿）

### 4.1 入口

| 入口 | 行为 |
|------|------|
| 工具栏 / Chrome 动作区「页面插件」图标 | Toggle 侧栏（SF Symbol 建议 `puzzlepiece.extension` 或 `curlybraces`） |
| 查看菜单 →「页面插件」 | 同上；建议快捷键 **⌘⇧P**（若冲突再改，如 ⌘⌥P） |
| 地址栏工具菜单 / 更多菜单（若已迁入） | 「页面插件…」打开侧栏 |
| （可选）当前页有启用匹配时图标点亮 / 小角标显示数量 | 增强可发现性，非 MVP 必须 |

**不**劫持助手钥匙或通知铃铛。

### 4.2 侧栏整体：两种模式，而非永久三等分

宽度：对齐现有侧栏 **320～560**，默认 **400**（代码编辑略宽于通知栏），记忆键如 `MeoPagePackSidebarWidth`。

#### 模式 A — 浏览态

```text
┌─ 页面插件 ──────────── ✕ ─┐
│ 本页生效 · 2                │  ← 上下文徽标（跟当前 tab URL）
│ [ 本页 ] [ 全部 ] [ 发现 ]  │  ← 分段（默认「本页」）
│ 🔍 搜索名称…                │
├─────────────────────────────┤
│ ▼ 已启用（2）               │
│  ● 文档站去广告      [开]   │  ← 开关；单击行 → 进入编辑态
│     style.css · tweak.js    │
│  ● 宽屏阅读          [开]   │
│ ▼ 已禁用 / 未匹配（…）      │  ← 「全部」时出现；「本页」可折叠显示未匹配
│  ○ 某全局脚本        [关]   │
├─────────────────────────────┤
│ [ + 新建插件 ]              │
└─────────────────────────────┘
```

- **本页**：仅列出 match 当前 URL 的 Pack（含已禁用，便于一键开启）。  
- **全部**：本地库；可按启用 / 名称排序。  
- **发现**（PP-1）：远程推荐列表；安装按钮 → 确认页 → 写入本地。  
- MVP 可先做「本页 | 全部」，「发现」放占位空态：「即将支持从目录安装」。

#### 模式 B — 编辑态（点击本地 Pack 后）

```text
┌─ ← 文档站去广告 ───── ✕ ─┐
│ [开]  匹配: example.com/*   │  ← 启用 + 摘要；点「匹配」展开编辑
│ [style.css] [tweak.js] [+]  │  ← 文件 Tab；+ 新建文件
├─────────────────────────────┤
│                             │
│  （等宽代码编辑器）          │  ← 主区域占满剩余高度
│                             │
├─────────────────────────────┤
│ 未保存的更改 · [丢弃] [保存] │  ← 保存后立刻对当前页生效
│              [在页面中刷新]  │
└─────────────────────────────┘
```

- **返回** ← ：回浏览态并保持选中高亮。  
- 元数据（名称、match、exclude、run-at、仅主 frame）用折叠面板或「设置」小页，避免挤占代码区。  
- **新建文件**：选类型 `.css` / `.js`，文件名校验，加入 Pack 并打开 Tab。  
- **删除文件**：确认后移除；至少保留一个文件或允许空 Pack（空 Pack 启用等于空操作）。

这样仍覆盖你要的三块能力（推荐 / 本地 / 编辑），但 **交互上是「分段浏览 + 钻入编辑」**，比永久上中下更适合窄栏写代码。

### 4.3 关键与常见流

| 场景 | 流程 |
|------|------|
| 为当前站快速改样式 | 打开侧栏 → 新建插件（预填当前 origin 的 match）→ 默认 `style.css` → 写 CSS → 保存 → 立刻看见 |
| 开关已有插件 | 浏览态行内开关；关：尝试移除已注入 CSS，JS 提示「刷新后完全卸载」 |
| 安装远程（PP-1） | 发现 → 详情（描述、权限、文件列表）→ 安装 → 进入编辑态或留在列表 |
| 多文件协作 | 同一 Pack 内 CSS 先注入、JS 按 `runAt` 排序注入（见 §7） |
| 切标签 | 侧栏若开着，徽标与「本页」列表随选中 tab URL 刷新；编辑态不强制打断（可选提示「当前编辑的 Pack 与本页不匹配」） |

### 4.4 空态与引导

| 状态 | 文案要点 |
|------|----------|
| 本页无 Pack | 「当前页没有页面插件。新建一个，默认只作用于本站。」+ 按钮 |
| 全部为空 | 同上 +（PP-1）「从发现安装」 |
| 发现未配置 Catalog | 「尚未配置插件目录。」（开发期可用内置示例 JSON） |
| 保存失败 | 具体错误（磁盘、文件名非法）；不静默 |

### 4.5 键盘与可达性

| 操作 | 建议 |
|------|------|
| Toggle 侧栏 | ⌘⇧P（待定） |
| 保存 | ⌘S（编辑态且焦点在侧栏时） |
| Esc | 编辑态有未保存 → 确认；否则关侧栏或退回浏览态（与助手侧栏策略对齐） |
| 文件 Tab | ⌘⌥← / → 切换（可选） |

输入控件遵守 SBKit；代码区需保证 ⌘C/V/X/A/Z 可用（`SBApplicationMenus` 已装则走响应链）。

---

## 5. 数据模型

### 5.1 Pack（插件包）

```text
PagePack
├── id              UUID 字符串
├── name            显示名
├── version         可选 semver 字符串
├── enabled         BOOL
├── matches[]       Chrome 风格 match 模式（V1 主推）
├── excludes[]      同左
├── description     可选
├── author          可选
├── sourceURL       可选（远程安装来源，便于更新）
├── createdAt / updatedAt
└── files[]         PagePackFile
```

### 5.2 File

```text
PagePackFile
├── name            如 style.css / main.js（包内唯一）
├── kind            css | js
├── runAt           document-start | document-end | document-idle（仅 js；css 固定越早越好）
├── mainFrameOnly   BOOL（默认 YES）
└── （内容）        独立文件落盘，不塞进 JSON
```

### 5.3 磁盘布局

```text
~/Library/Application Support/MeoBrowser/PagePacks/
├── index.json                 # 所有 Pack 元数据索引（无大段源码）
└── {packId}/
    ├── manifest.json          # 与 index 条目一致的权威副本
    ├── style.css
    └── tweak.js
```

- 写盘原子性：写临时文件再 replace。  
- `index.json` 便于列表快速加载；打开编辑时再读文件内容。

### 5.4 Match 规则（V1）

对齐 Chrome Extension / Tampermonkey `@match` 子集：

| 模式示例 | 含义 |
|----------|------|
| `https://example.com/*` | 该 host 下所有 path |
| `https://*.example.com/*` | 子域 |
| `*://example.com/docs/*` | http/https |
| `http://localhost:3000/*` | 本地开发 |

V1 **不做** 完整 `@include` 正则（可 PP-2）；UI 提供「用当前页生成」一键填 match。

### 5.5 远程 Catalog（PP-1）

```json
{
  "schemaVersion": 1,
  "packs": [
    {
      "id": "catalog.wide-reading",
      "name": "宽屏阅读",
      "description": "…",
      "version": "1.0.0",
      "matches": ["https://*.example.com/*"],
      "downloadURL": "https://cdn.example.com/packs/wide-reading.zip",
      "sha256": "…"
    }
  ]
}
```

- Catalog 根 URL 可配置（设置项或编译期默认）。  
- 安装包：zip 内含 `manifest.json` + 文件；校验 sha256（若有）。

---

## 6. UI 架构（原生）

### 6.1 模块建议

```text
SimpleBrowser/PagePack/
├── PagePackModels.h/.m          # Pack / File 模型
├── PagePackStore.h/.m           # 读写 Application Support
├── PagePackMatcher.h/.m         # URL × matches/excludes
├── PagePackInjector.h/.m        # 对 WKWebView 注入 / 撤销
├── PagePackCatalogClient.h/.m   # PP-1 远程目录
├── PagePackSidebarController.*  # 侧栏 UI
└── PagePackEditorController.*   # 编辑态（可内嵌于 Sidebar）
```

### 6.2 侧栏接入

- `BrowserTrailingSidebarSlot` 增加 `PagePack` kind。  
- `BrowserWindowController`：开页面插件侧栏时关其他 trailing 侧栏。  
- 宽度、Esc、窄窗自动收起：对齐通知 / 助手侧栏。

### 6.3 列表行

- 名称、启用开关、次要信息（文件数 / match 摘要）。  
- 「本页」行可显示小圆点「正在生效」。  
- 右键菜单：编辑、复制 match、导出、删除（MVP 可先工具按钮）。

### 6.4 代码编辑器选型（定稿建议）

| 方案 | 优点 | 缺点 | 建议 |
|------|------|------|------|
| `SBTextView` 等宽字体 | 符合仓库规范、快捷键现成 | 无语法高亮 | **MVP 采用** |
| 第三方高亮（如 Highlightr） | 体验好 | 依赖与体积 | PP-1 可选 |
| 嵌入 Monaco/CodeMirror WKWebView | 最强 | 重、焦点与快捷键复杂 | 不建议 V1 |

MVP：**`SBTextView` + menlo/SF Mono + 关闭富文本**；足够完成「开放式自定义」。

元数据字段：`SBTextField`；多行描述可用 `SBTextView`。

---

## 7. 注入架构（核心）

### 7.1 为何不把所有 Pack 静态塞进 `WKUserContentController`

- Pack 会增删改、按 URL 变化。  
- `removeAllUserScripts` 会误伤登录助手 / 查找等系统脚本。  
- 多标签共享 configuration 策略因实现而异，静态全量脚本难维护。

### 7.2 V1 推荐策略：**引导脚本 + 按导航动态注入**

1. **系统级**（可选）：在 configuration 上安装极薄 bootstrap（仅 message handler 名称预留），**不**承载用户代码。  
2. **每次主 frame 导航**（`didCommit` / `didFinish` 按 `runAt` 分流）：  
   - 取当前 URL → `PagePackMatcher` → 所有 `enabled` 且匹配的 Pack。  
   - **CSS**：按文件名稳定排序，包装为插入 `<style data-meo-pagepack="id:file">` 的 JS，优先 `document-start` 时机（`didCommit` 后尽早 `evaluateJavaScript`）。  
   - **JS**：按 `runAt`：  
     - `document-start` → commit 后尽快  
     - `document-end` → `didFinish` 或 DOMContentLoaded 探测  
     - `document-idle` → didFinish + short delay / `requestIdleCallback` polyfill  
3. **保存热更新（当前页）**：  
   - CSS：替换同 `data-meo-pagepack` 节点或更新 `textContent`。  
   - JS：**重新执行**（无法可靠「撤销」已跑逻辑）→ UI 文案：「脚本已重新执行；若异常请刷新页面」。  
4. **禁用 Pack**：移除其 CSS 节点；JS 提示刷新。

### 7.3 注入顺序（同 Pack 内）

1. 全部 CSS（文件名排序）  
2. 全部 JS，按 `runAt` 组内文件名排序  

多 Pack 之间：按 `updatedAt` 或用户可调 `priority`（V1 用名称 / 安装序稳定排序即可；**priority 字段预留**）。

### 7.4 iframe

V1 默认 **`mainFrameOnly = YES`**。需要 iframe 时在文件级关闭该开关（进阶，可藏在元数据里）。

### 7.5 Content World

| 世界 | V1 |
|------|-----|
| `pageWorld` | **默认**：可改页面 DOM/全局，与 Stylish/TM 直觉一致 |
| `defaultClient` isolated | PP-2 选项：更安全但无法改页面全局变量 |

### 7.6 SPA / History API

- `didCommit` 仅在完整导航触发；纯 `pushState` 可能不重注。  
- V1：**监听** `popstate` / 可选 hook（bootstrap 内）通知原生「URL 可能变了」→ 重新匹配 CSS（JS 是否重跑默认 **否**，避免重复绑定；提供「URL 变化时重跑脚本」Pack 级开关，默认关）。

### 7.7 与系统 UserScript 共存

- Pack **禁止** `removeAllUserScripts`。  
- 注入只用 `evaluateJavaScript`（及可选独立命名的少量 bootstrap `WKUserScript`）。  
- CSS 节点带 `data-meo-pagepack` 前缀，避免误删站点自身 style。

---

## 8. 安全与信任

| 风险 | 缓解 |
|------|------|
| 恶意远程 JS | 安装确认 + sha256；显示 match 范围；来源 URL 可见 |
| 过宽 match | UI 警告；`*://*/*` 需勾选「允许所有网站」 |
| 读写本地文件 / 钥匙串 | V1 **不提供** 扩展 API |
| XSS 式自我保存 | 用户自写代码自负；不静默执行未启用 Pack |
| 供应链 | Catalog 仅 HTTPS；可选钉扎证书（远期） |

设置中增加总开关：**启用页面插件**（默认开）；关闭则停止一切注入。

---

## 9. 与「上中下三面板」的映射（验收对照）

| 你的面板 | 本方案落点 |
|----------|------------|
| 上：推荐插件 | 浏览态分段 **「发现」**（PP-1）；MVP 可占位 |
| 中：本地插件启停 | 浏览态 **「本页 / 全部」** 列表 + 行内开关 |
| 下：文件与代码编辑 | **编辑态**全高编辑器 + 文件 Tab + 保存即时生效 |

能力全集覆盖；布局改为更适合写代码的 **drill-in**，而不是三等分挤压。

---

## 10. 里程碑建议

| 里程碑 | 范围 | 价值 |
|--------|------|------|
| **PP-0** | 模型 + Store + Matcher + 单测式匹配用例 | 数据面正确 |
| **PP-MVP** | Injector + 侧栏浏览/编辑 + 新建/保存热更新 + 工具栏入口 + 侧栏槽互斥 | 可日常自用 |
| **PP-1** | Catalog 安装 + 确认页 + 基础更新 | 可分发推荐插件 |
| **PP-2** | `.user.js` / UserCSS 导入、isolated 选项、URL 变化策略、语法高亮 | 生态与高级用户 |

---

## 11. 决策定稿（2026-08-21 已确认）

| # | 问题 | 定稿 |
|---|------|------|
| D1 | 侧栏布局 | **浏览态 + 编辑态钻入**（非永久上中下） |
| D2 | MVP 远程「发现」 | **否**；分段占位，实体能力放 PP-1 |
| D3 | 工具栏独立图标 | **是**（`puzzlepiece.extension` 或等价） |
| D4 | 快捷键 | **⌘⇧P**；若冲突改为 ⌘⌥P |
| D5 | JS API | V1 **无 GM_***，`pageWorld` 纯页面脚本 |
| D6 | 编辑器 | MVP **`SBTextView` + 等宽字体** |
| D7 | 新建默认 match | **当前页 origin + `/*`** |
| D8 | 产品名 | **页面插件**（代码模块 `PagePack`） |

---

## 12. 参考（业界与 WebKit）

- Userscript 元数据：`@match` / `@exclude` / `@run-at`（Greasemonkey / Tampermonkey）  
- UserCSS：`/* ==UserStyle== */`（Stylus）；本方案 V1 用统一 Pack manifest，导入兼容放 PP-2  
- WebKit：`WKUserScript`、`evaluateJavaScript:`、`WKContentWorld`  
- 本仓库已有注入先例：`LoginFormDetector`、`CaptchaDetector`、`BrowserFindEngine`、透明模式 page style  

---

## 13. 文档状态

- 本文件：方案 **已确认**（§11 定稿）。  
- 开发计划：[page-pack-development-plan.md](page-pack-development-plan.md)  
- Cursor 计划：[.cursor/plans/page-pack.plan.md](../../.cursor/plans/page-pack.plan.md)
