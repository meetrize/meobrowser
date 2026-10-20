# DOM 探针（DOM Inspector）— 设计方案

> 目标：为 MeoBrowser 增加一个**按需开启**的 DOM 属性查看器。开启后鼠标悬停即高亮元素并浮层展示其**全部**属性/特性/几何/样式；点击则**钉住**该元素，展开为可分段的属性清单（`row[price]` → 拆成 `row` + `[price]`），任意属性名、完整值、或值内分段均可**单击复制 / 右键菜单复制**。
> 状态：**设计定稿，待实现**
> 开发计划：[dom-inspector-development-plan.md](dom-inspector-development-plan.md)
> 关联：[page-scraper-design.md](page-scraper-design.md)（复用元素拾取脚本）· [tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md)（工具栏动作）· [web-inspector-design.md](web-inspector-design.md)（元素检查的定位分工）· [heavy-page-ui-responsiveness-design.md](heavy-page-ui-responsiveness-design.md)（注入开销约束）

---

## 1. 方案定位

### 1.1 产品一句话

**给"看 DOM 到底是啥样"这件事一个零学习成本的口袋工具**：一个按钮进入"探照灯"模式，鼠标即指针，所见即所查；点一下就把这个元素的全部家底钉在侧边面板里，可以像拆快递一样一层层拆值、随手复制任意一块。

### 1.2 与既有能力的分工

| 能力 | 定位 |
|------|------|
| 系统 Web Inspector（⌘⌥I） | 完整 DevTools：样式调改、断点、性能。**重、需退出日常态** |
| 页面爬虫 `BrowserScraperElementPicker` | 目标是**产出抓取配置**（选择器/行路径），面向自动化 |
| **DOM 探针（本方案）** | 目标是**只读地把元素属性摊开给你看并复制**，轻量、无副作用、可随手进出 |

一句话：本方案不是替代 Inspector，而是补上 Inspector 与"爬虫配置"之间那块高频刚需——**快速查看 + 快速复制一个元素的自定义/数据属性**。

### 1.3 做什么 / 不做什么

| 做（V1） | 不做（明确边界） |
|----------|------------------|
| 工具栏动作「DOM 探针」（toggle） | 不做样式编辑、节点树 DOM 树 |
| 悬停高亮 + 跟随式浮动气泡 | 不做 console / network |
| 点击钉住 → 侧栏分段属性清单 | 不做 XPath 断言回写页面 |
| 属性名 / 完整值 / 值内分段 三级复制 | 不做自动爬取调度 |
| 事件监听 / 几何 / 计算样式摘要 | 不做 iframe 穿透选择（同源 iframe V2 再议） |
| Esc 退出、一次性（拾取一次即退出）模式 | 不做常驻注入（关闭时页面零脚本） |

---

## 2. 交互设计

### 2.1 三种模式状态机

```
关闭 ──(点击工具栏按钮 / ⌥⌘D)──▶ 悬停态 HOVER
                                   │ 鼠标移动
                                   ▼
                              高亮元素 + 气泡
                                   │ 移动鼠标 = 气泡跟随，无状态堆积
                                   │ 点击元素
                                   ▼
                                钉住态 PINNED ──(点面板空白/关闭/再次点按钮/Esc)──▶ 关闭
                                   │ 点面板里的下一个元素
                                   ▼
                              钉住态（顺延到下一个元素）
```

**关键规则**

1. **悬停态是"瞬态"的**：气泡只显示最近一次悬停元素，鼠标移动即替换，绝不排队。气泡本身 `pointer-events: none`，不挡鼠标。
2. **点击即钉住**：点击页面任意元素 → 进入钉住态，气泡升级为侧栏面板，同时该元素保持高亮描边（`.meo-dom-inspector__pinned`，虚线，带 z-index 徽标）。
3. **钉住态下面板可"继续选下一个"**：面板顶部有一个"下一个/上一个"按钮，或直接在页面上再点一个元素即可替换钉住目标。这样可以连续看同一列表里的多个 `<tr>`。
4. **一次性模式（推荐默认）**：设置项"拾取后自动退出"，开启时钉住一个元素后探针自动关闭回到日常浏览——最大程度贴合"看一眼就走"的诉求。
5. **退出必须干净**：`window.__meoDomInspectorStop()` 移除所有 capture 阶段监听、还原所有高亮、删除注入样式节点。无任何残留。

### 2.2 悬停气泡（Hover HUD）

```
┌────────────────────────────────────────────┐
│  div.card.item-row              ⌗ 复制选择器 │  ← 标题行：tagName#id.class
│  1280×720  @ (412, 188)   可见 24.0×18.0     │  ← 副标题：几何
│  ─────────────────────────────────────────  │
│  data-id="sku-88213"                        │
│  data-row='{"price":39.9,"qty":2}'          │  ← hover 段
│  class="card item-row is-active"            │
│  onclick="submitOrder(…)"                   │
│  … 另有 7 个属性                            │  ← 折叠提示
└────────────────────────────────────────────┘
```

- **标题行右侧**：`⌗ 复制选择器`（一键复制唯一 CSS 选择器），这是最高频诉求，务必有。
- **气泡位置**：元素包围盒下方 8px；贴近视口边缘时自动翻转到上方 / 左右收边；永不超出窗口。
- **气泡内属性**：默认最多 8 条，超出折叠；`⇧` 展开全部。
- **不进气泡的字段**：`on*` 事件属性与超长样式串可折叠在「事件」「样式」小节内。

### 2.3 侧栏面板（Pinned Inspector）

点住后从右侧滑入一个窄面板（建议 320pt，可拖拽调宽；也可复用 `BrowserTrailingSidebarSlot` 的槽位机制，和爬虫/登录助手侧栏互斥）。

```
┌─ DOM 探针 ─────────────────────── ✕ ─┐
│ ⌗ CSS选择器      ⋯⋯                  │  ← 动作条：复制选择器 / 复制HTML / 复制XPath / 全部复制
│ div.card.item-row#row-3.is-active     │  ← 标题（可编辑查询？V2）
├───────────────────────────────────────┤
│ ▸ 身份                    3 项  折叠 ▸ │  ← 分组，可折叠，默认展开
│   tagName          div                 │
│   id               row-3               │
│   className        card item-row is-active │
│ ▸ 自定义属性                12 项      ▸ │
│   data-id          sku-88213      ⧉ ⧉ │  ← 值区鼠标悬停出现两个小按钮
│   data-row         {                │  ← 大值：可展开分段树
│     ├ 键  price             ⧉ ⧉      │
│     ├ 值  39.9              ⧉ ⧉      │
│     └ 键  qty               ⧉ ⧉      │
│   data-config      {"theme":"dark","on":{"a":1,"b":[2,3]}}  │
├───────────────────────────────────────┤
│ ▸ 几何  ▸ 计算样式  ▸ 事件  ▸ 无障碍  ▸  │  ← 其余分组折叠
└───────────────────────────────────────┘
```

**分组（Groups）**：身份 / 自定义属性（`data-*`, `aria-*`, 自定义 `x-`）/ 标准属性 / 几何（bounding rect、scroll、偏移、层级 z-index）/ 计算样式摘要 / 事件监听 / 文本摘要（自身 text、首 200 字符）。

### 2.4 分段（Segment）规则 — 核心

值按下述优先级拆成**分段数组**，UI 渲染成可折叠树，每一段独立可复制：

| # | 规则 | 例子 | 渲染 |
|---|------|------|------|
| R1 | 值是合法 JSON | `{"a":1,"b":2}` | 对象/数组树，叶子复制单个标量 |
| R2 | 值形如 `row[price]`（标识符 + 一个或多个 `[]`） | `row[price]`, `a.b[0][1]` | 行内分段按钮：`row` · `[price]` |
| R3 | 值含分隔符（`,` `;` `\|` `/` `\n`）且分段数 ≥2 | `a,b,c` | 逐段 chip，空格可往返 |
| R4 | R2 命中后再对段内递归应用 R1/R3（最多 2 层） | `cfg[theme][colors]` → `cfg` `[theme]` `[colors]` | 树形嵌套 |
| R5 | 值超长（>120 字符） | 任意 | 截断显示 `…`，`⤢` 展开完整；完整值仍可整段复制 |
| R6 | 括号键值 `key=value` | `id=a&b` | 分段 + 键名/值两级 |

**复制语义（关键 UX）**：鼠标悬停某一段，该段右侧浮出**两个 8pt 小按钮**：

- `⧉`（单击）：**复制该段原文**（如 `price` 或 `[price]` 或 `39.9`）
- `⧉⧉`（单击）：**复制完整路径**（如 `data-row → price`，便于回溯定位）

同时该段本身**可点击复制**（单击 = 复制该段；与按钮一致，避免"点按钮才有效"的隐蔽交互）。右键任意段 → 系统菜单：**复制该段 / 复制完整路径 / 复制所在行的完整值 / 复制全部属性（JSON）/ 在 Finder 中显示…（无）/ 用 MeoBrowser 搜索该值（可选）**。

> 建议明确"单击段=复制"的直觉：光标变成 `arrow.copy` 或 `I-beam` + 段背景高亮，1ms 后该段短暂闪绿表示已复制。

### 2.5 快捷键与右键菜单

| 操作 | 快捷键 |
|------|--------|
| 切换 DOM 探针 | `⌥⌘D` |
| 钉住态下复制选择器 | `⌘C`（焦点在面板时） |
| 钉住态下"全部复制为 JSON" | `⌘⇧C` |
| 关闭面板 / 退出 | `Esc` |

工具栏按钮右击 → 与其它 Chrome Action 一致：已固定到工具栏 / 固定 / 隐藏。

---

## 3. 技术方案

### 3.1 架构（复用既有基建）

```
BrowserWindowController
  └─ chromeActionsView  (新增 BrowserChromeActionDOMInspectorID)
       └─ 动作派发 performChromeActionForItemID:
            └─ BrowserDOMInspectorController (新)  ── 负责启停、生命周期、菜单
                 ├─ BrowserDOMInspectorBridge (新) ── 注入脚本 / postMessage 收发
                 ├─ BrowserDOMInspectorPanel (新)   ── 侧栏 NSScrollView + 属性行视图
                 ├─ BrowserDOMInspectorRowView(新)  ── 单个"名: 值(分段)"行
                 └─ BrowserDOMValueSegmenter (新)  ── 纯数据分段器（可单测）
```

复用：
- **注入通道**：`BrowserScraperElementPicker` 的模式 —— `WKUserContentController` + `LoginAssistScriptMessageProxy` + `window.webkit.messageHandlers.meoDomInspector`，但用**独立 handler 名**，互不干扰。
- **动作注册**：`BrowserChromeActionItem` 增加一项，`BrowserChromeActionLayoutStore` 自动纳入可固定/排序体系，零成本获得"更多"菜单与自定义面板支持。
- **侧栏**：`BrowserTrailingSidebarSlot`（与爬虫侧栏、登录助手侧栏互斥）。
- **高亮**：`BrowserScraperCandidateOverlay` 的高亮绘制思路可参考，但本方案改用**页面内 CSS outline**（比 AppKit overlay 更精确，且能穿透滚动）。

### 3.2 页面脚本（注入内容）

只在开启时 `evaluateJavaScript` 注入一次性脚本，注册 `window.__meoDomInspector = { stop(), pick() }`。

```js
(function(){
  if (window.__meoDomInspectorStop) window.__meoDomInspectorStop();
  const post = (o) => { try { window.webkit.messageHandlers.meoDomInspector.postMessage(o); } catch(e){} };
  const STYLE_ID = '__meo_dom_inspector_style';

  // 1) 样式：只在页面注入一段 shadow-less CSS
  ensureStyle(`
    .meo-di-hover { outline: 2px solid #2F7BFF !important; outline-offset: -2px !important; cursor: crosshair !important; }
    .meo-di-pinned { outline: 2px dashed #FF7A1A !important; outline-offset: -2px !important; }
    .meo-di-badge { position:absolute; z-index:2147483647; ... }
  `);

  // 2) 悬停：mouseover 捕获阶段 + mouseout 去抖 + scroll/resize 时重算
  function onOver(e) {
    const el = e.target;
    if (!el || el.nodeType !== 1) return;
    highlight(el, 'meo-di-hover');
    const prev = cur; cur = el;
    post({ type: 'hover', payload: snapshot(el, { full: false }) });
  }

  // 3) 点击：capture + preventDefault + stopPropagation，钉住
  function onDown(e) {
    e.preventDefault(); e.stopPropagation();
    const el = e.target; if (!el || el.nodeType !== 1) return;
    pin(el);
    post({ type: 'pinned', payload: snapshot(el, { full: true }) });
  }

  // 4) 快照：所有自有属性 + 全部 attribute + 几何 + 摘要样式 + 监听器
  function snapshot(el, { full }) { ... }   // 见 3.3

  window.__meoDomInspectorStop = function(){
    cleanup();  // removeEventListener(true) + 清高亮 + 删 style
  };
})();
```

**性能纪律（对齐 heavy-page 设计）**

1. `mouseover` 用 **capture 阶段 + 100ms trailing 去抖**，且只在 `el !== lastElement` 时才 post 消息。
2. `mouseover` 期间调用 `e.target.matches` 之类不做；快照构造在 rAF 里做。
3. hover 模式只发**摘要**（≤12 字段 + 截断值），完整快照仅在点击时发一次。
4. 事件监听全部用 `{capture:true, passive:true}`（除需要 `preventDefault` 的 click）。
5. **零常驻**：关闭时脚本完全移除；不开探针的页面不注入任何字节。
6. `scroll`/`resize` 期间不重算快照，只移动高亮（CSS outline 天然跟随，无需重算）。

### 3.3 快照数据结构（postMessage payload）

```jsonc
{
  "type": "hover|pinned",
  "payload": {
    "tagName": "div",
    "selector": "div.card.item-row#row-3",   // 唯一 CSS 选择器（已用 nth-of-type 去重）
    "xpath": "/html[1]/body[1]/div[2]/div[5]",
    "id": "row-3",
    "className": "card item-row is-active",
    "attributes": [ { "name": "data-id", "value": "sku-88213", "kind": "data" }, ... ],
    "properties": [ { "name": "onclick", "value": "submitOrder(…)", "kind": "handler" } ],
    "geometry": { "x":412,"y":188,"w":1280,"h":720,"scrollH":720,"visible":true,
                  "scrollTop":0,"scrollLeft":0,"zIndex":"auto" },
    "text": { "own": "¥39.9", "clipped": "…" },
    "styleSummary": { "display":"block","position":"relative","color":"rgb(20,20,20)", ... },
    "a11y": { "role":"", "alt":"", "label":"", "hidden":false },
    "listeners": ["click","mouseover"],       // getEventListeners 不可用时留空
    "counts": { "attributes": 18, "truncated": 7 }
  }
}
```

> `getEventListeners` 仅 DevTools 可用 → V1 显示为空并在分组标题标注「仅 DevTools 可用」，不误导。

### 3.4 分段器（Swift 侧，纯函数）

```swift
enum DomValueSegment {
    case literal(String)                      // 原文片段（可含空格原样保留）
    case bracketKey(String)                   // [price] 中的 price
    case identifier(String)                   // row
    case jsonPath(path: [DomJsonPathStep], raw: String) // JSON 内的定位路径
}

enum DomJsonPathStep {
    case key(String)
    case index(Int)
}

enum DomValueSegmenter {
    static func segments(for value: String, depth: Int = 0) -> [DomValueSegment]
}
```

算法顺序：**R6 → R1（JSON 解析成功则走 JSON 树）→ R2（`^[A-Za-z_$][\w$-]*(\[[^\[\]]+\])+$`）→ R3（分隔符切分）→ R5（长度截断）**。
每段附带 `fullPath`（如 `data-row → row → price`）用于「复制完整路径」。

JSON 解析失败时降级为 R2/R3，绝不抛错、绝不空返回（空值也要能显示"（空）"）。

### 3.5 侧栏 UI 实现要点

- `NSScrollView` + `NSStackView`（复用 `BrowserScraperSidebarController` 的滚动栈写法）。
- 每个 `BrowserDOMInspectorRowView`：`名称标签`（等宽字体，可选中/可点复制）+ `值区`（`NSTextField` 不可编辑、不可选中，改为**自定义绘制/分段按钮**，以满足"点段复制"）。
- 分段按钮用 `NSButton` 的 `.bordered` 极简样式或自绘 `NSView`，hover 时显示复制角标。
- 复制统一走 `NSPasteboard generalPasteboard` + `BrowserTransientToast` 提示「已复制 data-row → price」。
- 右键菜单：`menuForEvent:` 中按 `event` 所在分段组装 `NSMenu`。
- 面板宽度可拖拽，状态存 `BrowserDOMInspectorPreferences`（UserDefaults）。

### 3.6 状态与生命周期

| 事件 | 行为 |
|------|------|
| 切换标签页 | 探针保持开启状态，对新 WebView 重新注入；旧 WebView 移除监听 |
| 标签休眠（无 WebView） | 按钮置灰，提示「标签已休眠」 |
| 页面导航（didCommit） | 自动重新注入（若处于开启态） |
| 窗口关闭 | 清理脚本，释放面板 |
| 应用退出 | 同上（脚本随 WebView 销毁自然消失） |
| 多窗口 | 每个窗口独立一份，静态状态用 `__weak` WebView 引用（参照 `BrowserScraperElementPicker` 的单例风格，但**按窗口实例**持有） |

### 3.7 与爬虫拾取的互斥

两者都用"捕获点击"。**同一个 WebView 同时只允许一个拾取器**：

- 在 `BrowserScraperElementPicker` 的 `startPickingInWebView:` 与新的 `BrowserDOMInspectorBridge` 启动时互相调用对方的 `cancelActivePick`，或抽一个共享的 `BrowserWebViewPickCoordinator` 做单例仲裁。
- UI 上：爬虫侧栏打开时 DOM 探针按钮自动置灰并给出 tooltip「请先关闭页面爬虫拾取」。

> V1 建议实现共享仲裁（新增 `BrowserWebViewPickCoordinator`），避免两处各写一遍互斥逻辑。

---

## 4. 与系统 Inspector 的边界（务必写清）

- 本方案**只读**，不写页面 DOM 属性（高亮 class 与角标除外，且退出时全部清除）。
- 本方案**不与 `WKWebView.inspectable` 联动**；两者可共存但互不感知。
- 如果用户只是要"改样式/看请求"，仍应引导到 ⌘⌘I 系统 Inspector（已在 [web-inspector-design.md](web-inspector-design.md) 实现）。

---

## 5. 安全与隐私

- 只读取 DOM，不上报、不写磁盘、不做网络请求。**完全本地**。
- 面板"全部复制为 JSON" 生成的内容仅在剪贴板，不落盘。
- 探针开启状态不持久化到磁盘（仅记忆"是否默认显示在工具栏"）。

---

## 6. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 大页面高频 `mouseover` 卡顿 | 滚动/移动掉帧 | capture + 去抖 + hover 只发摘要 + rAF 构造快照 + 关闭即移除 |
| 页面自身监听器抢先触发 | 点不到元素 | 用 capture + `stopImmediatePropagation`，并在注入前 `cloneNode` 备份原始监听不可行 → 接受并记录；必要时对已知电商站提供"温和模式"设置 |
| 页面 CSP 阻止注入脚本 | 功能不可用 | `WKUserScript` 在 documentStart 注入（不受页面 CSP 影响）→ **采用此方案**，而非临时 `evaluateJavaScript` |
| 属性值含超长 JSON/base64 | 面板爆炸 | R5 截断 + 折叠 + 上限 200KB |
| iframe 内容 | 选不到 | V1 在主 frame 生效，UI 标注；同源 iframe 注入 V2 |
| 高亮 class 名与页面冲突 | 视觉异常 | 统一前缀 `meo-di-*` + `!important` + 退出时按前缀批量清理 |

> **关键技术选型修正**：脚本应通过 `WKUserScript`（`injectionTime: .atDocumentStart`）注册到 `WKUserContentController`，而不是每次 `evaluateJavaScript`。这样既绕过页面 CSP，又能在导航后自动重注入，生命周期更干净。关闭时调用 `__meoDomInspectorStop()` 即可。

---

## 7. 里程碑

| 阶段 | 交付 | 验收 |
|------|------|------|
| M1 | 工具栏动作 + 注入骨架 + 悬停高亮 + 摘要气泡 | 按钮可开关，hover 出气泡，Esc 干净退出 |
| M2 | 点击钉住 + 侧栏面板 + 属性全量分组展示 | 面板可打开/关闭/切换标签正确 |
| M3 | 分段器 + 三级复制（含右键菜单） | `row[price]`、JSON、逗号串均正确拆段并复制 |
| M4 | 拾取仲裁 + 快捷键 + 偏好设置 + 边界加固 | 与爬虫互斥；休眠标签置灰；无残留 |
| M5（可选） | CSS 选择器高亮反查 / 录制多元素对比 / 导出 JSON 快照文件 | — |

---

## 8. 未来增强（V2+，不承诺）

1. **多元素对照**：勾选多个元素，侧栏并排对比属性差异（类似 Chrome "Computed" diff）。
2. **选择器生成器**：在面板里点选子节点，逐步收敛出一条稳定 CSS 选择器，一键复制。
3. **监听器回放**：显示 `getEventListeners` 近似（通过重新注入 hook `addEventListener` 采集，代价高，默认关）。
4. **数据路径提取**：从 `data-row` 这类 JSON 自动生成"表结构"，导出 CSV（与页面爬虫联动）。
5. **快捷键免手**：按住 `⌥` 临时进入探针模式，松开即退出（Chrome 的 Inspect 模式同款）。
6. **跨窗口/手机端**：Android 端复用同一 JS 协议。
