# 轻量开发者工具（Web Inspector）— 设计方案

> 目标：在**不显著增加常驻内存、不拖慢日常浏览**的前提下，为 MeoBrowser 提供 Elements / Console / Network 等基础调试能力；并附带「查看源代码」「硬刷新」等原生轻量能力。  
> 状态：**DI-0 / DI-1 已实现**（DI-2 待开发）  
> 开发计划：[web-inspector-development-plan.md](web-inspector-development-plan.md)  
> 关联：[professional-features-roadmap.md](professional-features-roadmap.md) §3.2 · [design.md](design.md) · [insecure-https-design.md](insecure-https-design.md) · [anti-bot-session-design.md](anti-bot-session-design.md) · [multi-tab-design.md](multi-tab-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**按需复用系统 WebKit Inspector**：日常浏览零开销；需要调试时，用系统 Web Inspector（检查元素、控制台、网络、存储等）+ 少量原生菜单能力，**不**自建 Chromium 式 DevTools 前端。

### 1.2 要解决的痛点

| 用户场景 | 痛点 | 本方案价值 |
|----------|------|------------|
| 前端 / 全栈本地调 UI | MeoBrowser 打不开检查器，只能切 Safari/Chrome | ⌘⌥I 或 Safari「开发」菜单即可调试 |
| 查 Network / Console | 轻量浏览器通常整块缺失 | 系统 Inspector 自带基础面板 |
| 看 SSR / 文档结构 | 无「查看源代码」 | 原生轻量实现，不依赖 Inspector |
| 前端硬刷缓存 | ⌘R 走普通 reload | ⌘⇧R → `reloadFromOrigin` |
| 担心内存变「Chrome」 | 怕内嵌 DevTools 拖垮轻量定位 | 默认关；仅调试会话占内存 |

### 1.3 做什么 / 不做什么

| 做（V1） | 不做（明确边界） |
|----------|------------------|
| `WKWebView.inspectable` 开关（偏好 + 通知） | 内嵌完整 DevTools HTML/前端 |
| 菜单「打开 Web Inspector」⌘⌥I | 自研 Console / Network 面板 |
| Safari「开发」菜单附加调试（inspectable 开启后） | 常驻注入 console/network 钩子脚本 |
| 「查看网页源代码」菜单 + 右键 | Remote Debugging Protocol 自建服务端 |
| 「强制刷新」⌘⇧R | 断点调试服务端、源映射编辑器增强 |
| 设置「允许网页检查」默认关（可改为开） | Android 端 Inspector（Mac 为工作台） |
| macOS 13.3+ 公开 API 优先 | 依赖私有 API 作为**唯一**路径 |

### 1.4 设计原则

1. **按需付费**：关闭开关时与今日行为一致；打开 Inspector 窗口后才有额外进程/内存。  
2. **原生优先**：复用系统 Web Inspector，对齐路线图「不自造轮子」。  
3. **公开 API 优先**：`inspectable`（macOS 13.3+）必做；程序化弹出 Inspector 优先公开路径，私有 `_WKInspector` 仅作可选增强且可降级。  
4. **不常驻脚本**：不为「假 Console」往每个页面注入监听脚本（避免性能与反风控副作用，见 [anti-bot-session-design.md](anti-bot-session-design.md)）。  
5. **与标签休眠兼容**：休眠标签无 live WebView 时，相关菜单禁用；唤醒后再检查。  
6. **安全默认**：生产默认不强制开启 inspectable；用户显式打开「允许网页检查」。

---

## 2. 现状基线（代码）

| 项 | 现状 |
|----|------|
| 引擎 | 系统 `WKWebView`（`BrowserWebView`） |
| `inspectable` | **未设置** |
| Web Inspector 菜单 | **无** |
| 查看源代码 | **无** |
| 硬刷新 | `BrowserWebView.reloadFromOrigin` **已实现**；菜单 ⌘R 走 `reloadPage:` → `reload`；**未**接 ⌘⇧R |
| 右键菜单 | `BrowserWebView.willOpenMenu:withEvent:` 已扩展下载 / 新窗口等 |
| 设置窗 | `BrowserSettingsWindowController`（UserDefaults 各 Preferences 模式） |
| 标签休眠 | 全局/窗口 live WebView 上限；休眠后无 WebView |
| 路线图 | §3.2 P0；验收清单「Web Inspector + 查看源代码」未勾 |

---

## 3. 候选方案对比

| 方案 | 做法 | 常驻内存 | 调试能力 | 结论 |
|------|------|----------|----------|------|
| **A. inspectable + Safari 附加** | 设 `inspectable=YES`；用户从 Safari → 开发 → MeoBrowser | ≈0（未连接时） | 完整系统面板 | **V1 必选底座** |
| **B. 菜单直接弹出 Inspector** | ⌘⌥I 调 show；失败则引导 A | 仅打开时 | 同 A，体验更好 | **V1 主路径（可降级）** |
| C. 自研精简 Console/Network | 注入 + 原生面板 | 持续有 | 残缺、难维护 | **不做** |
| D. 嵌 Chromium DevTools | 独立前端 + 协议桥 | 高 | 完整但与 WebKit 不对齐 | **不做** |
| E. 仅 Debug 编译打开 inspectable | `#if DEBUG` | Debug 构建有 | 发布包无 | 可作工程默认；**产品仍要设置开关** |

**定稿：A + B + 原生轻量项（源代码 / 硬刷新）**，合称 **DI（Developer Inspector）**。

```
日常浏览（inspectable 关）
  → 与今日一致，无 Inspector 相关开销

开启「允许网页检查」
  → 现有 / 新建 WKWebView.inspectable = YES
  → 仍不打开 Inspector UI，直到用户主动操作

用户 ⌘⌥I / 菜单「打开 Web Inspector」
  → 尝试程序化 show
  → 成功：系统 Inspector 窗口（Elements / Console / Network / …）
  → 失败：提示用 Safari「开发」菜单附加（能力等价）

用户「查看源代码」/ ⌘⌥U
  → evaluateJavaScript 取 outerHTML → 新标签只读展示（不启 Inspector）

用户 ⌘⇧R
  → reloadFromOrigin（绕过缓存）
```

---

## 4. 功能规格

### 4.1 允许网页检查（偏好）

| 项 | 规格 |
|----|------|
| 存储 | `NSUserDefaults`，key 建议 `MeoBrowserAllowWebInspection` |
| 默认 | **`NO`**（日常零开销、偏安全） |
| UI | 设置窗口新增「开发者」分区：复选框「允许网页检查」+ 说明文案 |
| 文案建议 | 「开启后可用系统 Web Inspector（检查元素、控制台、网络等）。仅在调试时建议开启；关闭时不影响日常浏览。」 |
| 生效范围 | 所有窗口、所有标签的 live `WKWebView`；变更后立即应用到已有 WebView，并通知新建路径 |
| 通知 | `BrowserDeveloperPreferencesDidChangeNotification`（命名与现有 `*PreferencesDidChangeNotification` 一致） |
| 低于 macOS 13.3 | 复选框禁用 + 说明「需要 macOS 13.3 或更高版本」 |

**工程可选**：Debug 构建在 `registerDefaults` 中默认 `YES`，方便开发；Release 仍默认 `NO`。以设置 UI 为准，用户可随时改。

### 4.2 应用 `inspectable`

| 时机 | 行为 |
|------|------|
| `BrowserTab.ensureWebView` 创建 WebView 后 | 按偏好设置 `inspectable`（`@available(macOS 13.3, *)`） |
| 偏好变更 | 遍历所有窗口 → 所有 live tab → 同步 `inspectable`；休眠标签等唤醒时再设 |
| 弹出窗口 / `createWebViewWithConfiguration:` | 新 WebView 同样应用 |

辅助类建议：`BrowserDeveloperPreferences`（读写 + 通知）+ 薄封装 `BrowserWebInspector`（apply / show / 能力探测）。

### 4.3 打开 Web Inspector（⌘⌥I）

| 项 | 规格 |
|----|------|
| 菜单位置 | **查看**菜单：「打开 Web Inspector」，快捷键 ⌘⌥I（`i` + Command + Option） |
| 前置条件 | 当前标签有 live `WKWebView`；非纯 Launchpad 无页（`isNewTabPage` 且无文档）时禁用 |
| 偏好未开 | 首次触发可：① 自动打开偏好并提示用户开启，或 ② Alert「需先在设置中开启允许网页检查」+「打开设置」按钮。**推荐 ②**，避免静默改安全默认 |
| 程序化 show | 优先公开 API；若无，则 **可选** `dlsym` / 运行时调用 `_inspector` → `show`（与现有 process-swap 私有调用风格一致），包在独立文件，失败即降级 |
| 降级文案 | 「无法直接打开检查器。请确认已开启「允许网页检查」，然后在 Safari → 开发 → MeoBrowser 中选择对应页面。」 |
| 与 ⌘⇧I（通知侧栏） | 现有「手机通知」为 ⌘⇧I；本项为 **⌘⌥I**，互不冲突 |

`validateMenuItem:`：无 WebView / Launchpad / 休眠未唤醒 → 禁用「打开 Web Inspector」。

### 4.4 Safari「开发」菜单路径（文档 + UI 提示）

设置区在复选框下方增加次要说明：

> 也可在 Safari 菜单栏启用「开发」菜单后，通过「开发 → [你的 Mac] → MeoBrowser」附加调试。需先勾选上方开关。

不在 App 内伪造 Safari 菜单；仅说明。

### 4.5 查看网页源代码

| 项 | 规格 |
|----|------|
| 入口 | 查看菜单「查看网页源代码」⌘⌥U；页面右键增加同名项（空白处 / 通用） |
| 实现 | `evaluateJavaScript:@"document.documentElement.outerHTML"`（或等价）；失败则尝试 `document.documentElement.innerHTML` 降级提示 |
| 展示 | **新标签页**加载只读内容：`text/plain` 或简易 `text/html` 转义后的 `<pre>`；标题如「源代码 — {原标题}」 |
| URL | 可用 `meo-source:` 伪协议或 `data:text/plain;charset=utf-8,...`；优先 **data URL 或临时内存 HTML**，避免污染浏览历史（与 `BrowsingPreferences.isPersistableURL` 协调：源代码页**不**写入会话恢复） |
| 编码 | UTF-8；超大页面（如 > 5 MB 字符串）可截断并提示「已截断」 |
| 限制 | 仅为**当前文档**序列化后的 DOM 快照，不是未解析的原始 HTTP body；跨域 iframe 不展开。文案可在空状态注明「显示为当前 DOM，可能与原始响应有差异」 |
| Launchpad / 无文档 | 菜单禁用 |

输入展示若用原生文本视图：**必须** `SBTextView`（仓库文本输入规范）；若用 WebView 展示 `<pre>`，则无需 SBKit 文本控件。

**推荐 V1**：新标签 + `BrowserWebView` 加载包装后的 HTML（`<pre>` + 等宽 CSS），实现快、可搜索（⌘F 复用查找）；不引入新编辑器窗。

### 4.6 强制刷新（硬刷新）

| 项 | 规格 |
|----|------|
| 菜单 | 查看菜单「强制刷新」，快捷键 ⌘⇧R |
| 行为 | 调用当前 `BrowserWebView.reloadFromOrigin`（已处理 hash / 缓存策略） |
| 与 ⌘R | ⌘R 保持 `reloadPage:`（普通刷新 / 错误页重试逻辑不变） |
| 休眠标签 | 与普通刷新一致：可先走现有 hibernate 刷新路径，或禁用强制刷新直至唤醒（与 `reloadPage:` 对齐即可） |
| Launchpad | 禁用 |

### 4.7 系统 Inspector 已含能力（无需自建）

开启并连接 Inspector 后，用户即可使用系统面板，**本方案不单独实现**：

- Elements（检查元素 / DOM）
- Console
- Network
- Storage / 相关资源面板（随系统 WebKit 版本提供）
- 响应式 / 时间线等（若系统版本提供）

产品文案中可写「基础开发者工具（检查元素、控制台、网络等）由系统 Web Inspector 提供」。

---

## 5. 架构与模块

### 5.1 模块划分

```
SimpleBrowser/
├── Developer/                          # 新建
│   ├── BrowserDeveloperPreferences.h/.m   # UserDefaults + 通知
│   └── BrowserWebInspector.h/.m           # applyInspectable / showInspector / 能力探测
├── Tabs/BrowserTab.m                      # ensureWebView 后 apply
├── BrowserWindowController.m              # 菜单 action、validate、偏好变更刷新
├── BrowserMenus.m                         # 查看菜单项
├── BrowserSettingsWindowController.m      # 「开发者」分区 UI
└── Tabs/BrowserWebView.m                  # 右键「查看网页源代码」
```

### 5.2 调用关系

```
BrowserDeveloperPreferences
        │ 通知
        ▼
BrowserWindowController ──► 所有 tab.webView
        │
        ├── openWebInspector: ──► BrowserWebInspector.showForWebView:
        ├── viewPageSource:   ──► JS outerHTML ──► 新标签展示
        └── hardReloadPage:   ──► reloadFromOrigin

BrowserTab.ensureWebView ──► BrowserWebInspector.applyInspectableToWebView:
```

### 5.3 程序化 Show 的技术策略

| 优先级 | 路径 | 说明 |
|--------|------|------|
| 1 | 公开 API（若 SDK 已提供 show/inspect 类方法） | 编译期 `@available` 调用 |
| 2 | 运行时可选私有：`_inspector` / `show` | 独立 `.m`，`respondsToSelector` / `dlsym`，**不得**链进必选符号 |
| 3 | 降级引导 Safari 附加 | Alert + 设置说明；功能不丢 |

App Store / 公证场景：私有 API 有拒审风险。若目标含 Mac App Store，**V1 可仅做 A（inspectable）+ 降级文案**，把 B 的私有 show 标为「Direct / 非 MAS 构建可选」。Makefile 可用编译宏 `MEO_ENABLE_PRIVATE_INSPECTOR_SHOW=1` 控制。

**默认建议**：开源 / 本机 Direct 构建启用可选 show；文档标明 MAS 构建关闭私有路径。

### 5.4 与休眠 / 多窗口

| 场景 | 行为 |
|------|------|
| 多窗口 | 偏好全局；每个窗口各自打开自己的 Inspector（系统行为） |
| 休眠 | 无 WebView → 菜单禁用；唤醒 `ensureWebView` 时再 apply inspectable |
| 标签上限 | 不改变 live WebView 预算；Inspector 是附加调试进程，不计入「8/12」业务上限，但用户应知晓调试时内存会升 |

### 5.5 内存与性能预算

| 状态 | 预期 |
|------|------|
| 偏好关 | 与现状一致（无额外进程、无注入） |
| 偏好开、Inspector 未连 | 接近现状；`inspectable` 标记本身可忽略 |
| Inspector 已打开 | **额外** Web Inspector / WebKit 相关进程内存（数十～百余 MB 量级，随页面与面板而变）；关闭 Inspector 窗口后应回落 |
| 查看源代码 | 短暂 JS 执行 + 一个只读标签的字符串内存；关标签即释放 |
| 硬刷新 | 与一次绕过缓存的导航相当 |

**验收**：偏好关时，空窗 / 单标签 RSS 相对改前无明显回归（目测或对照 [acceptance.md](acceptance.md) 基线量级即可，不强制精确字节）。

---

## 6. 交互与文案

### 6.1 菜单结构（查看）

在现有「刷新」附近扩展：

```
查看
├── 刷新                          ⌘R
├── 强制刷新                      ⌘⇧R
├── ────────
├── 放大 / 缩小 / 实际大小
├── ────────
├── 在页面中查找 …
├── ────────
├── 打开 Web Inspector            ⌘⌥I
├── 查看网页源代码                ⌘⌥U
├── ────────
└── 手机通知                      ⌘⇧I
```

### 6.2 右键

在 `willOpenMenu:withEvent:` 末尾（或合适分隔符后）插入：

- 「查看网页源代码」→ 转发给窗口 `viewPageSource:`

无文档时不插入或 disabled。

### 6.3 设置分区

```
── 开发者 ──
☑ 允许网页检查
  开启后可使用系统 Web Inspector（检查元素、控制台、网络等）。
  也可通过 Safari → 开发 → MeoBrowser 附加调试。
```

---

## 7. 与相关模块的关系

| 模块 | 关系 |
|------|------|
| [insecure-https-design.md](insecure-https-design.md) | 互补：证书例外方便本地 HTTPS；本方案管调试 UI。不合并为同一开关 |
| [anti-bot-session-design.md](anti-bot-session-design.md) | 本方案**禁止**为 DevTools 常驻注入；风险域策略不变 |
| User-Agent 设置（路线图） | 另项；本方案设置分区可预留下方空位，但不实现 UA 编辑 |
| 命令面板（路线图） | V1.1 可注册命令：打开 Inspector / 查看源代码 / 强制刷新 |
| Android | 明确不做；Mac 为开发者工作台 |

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 私有 API 拒审 / 脆化 | show 可选；inspectable 公开 API 为底线 |
| 用户误以为「开关 = 已打开面板」 | 文案区分「允许检查」与「打开 Inspector」 |
| 源代码 ≠ 原始响应 | UI/文档注明 DOM 快照 |
| 超大页卡顿 | 截断 + 提示；JS 在主帧执行注意超时 |
| Inspector 内存升高被误报为「浏览器变重」 | 文档与设置说明「仅调试时」；默认关 |
| 快捷键冲突 | ⌘⌥I / ⌘⌥U / ⌘⇧R 避开现有 ⌘⇧I、⌘R、⌘⇧T 等 |

---

## 9. 分阶段交付（摘要）

| 阶段 | 内容 | 价值 |
|------|------|------|
| **DI-0** | Preferences + `inspectable` + 设置 UI + Safari 附加说明 | 立刻可调，零 UI 进程 |
| **DI-1** | 菜单 ⌘⌥I show（含降级）、⌘⇧R、validate | 主路径体验 |
| **DI-2** | 查看源代码（菜单 + 右键 + 新标签展示） | 不依赖 Inspector 的日常查源 |
| **DI-3**（可选） | 命令面板入口、Debug 默认开、MAS 宏拆分、原始响应 body（需另设计） | 增强 |

首版交付目标：**DI-0 + DI-1 + DI-2**。

详细任务见 [web-inspector-development-plan.md](web-inspector-development-plan.md)。

---

## 10. 验收标准（设计级）

- [ ] 默认关闭「允许网页检查」时，无法被 Safari 开发菜单列出（或列出不可检），日常无 Inspector 进程
- [ ] 开启后，Safari → 开发 → MeoBrowser 可附加当前页，Elements / Console / Network 可用
- [ ] ⌘⌥I：能 show 则弹出；否则明确降级指引；未开偏好时引导设置
- [ ] ⌘⇧R 走 `reloadFromOrigin`；⌘R 行为不变
- [ ] 「查看网页源代码」新标签只读展示；不进入会话恢复；Launchpad 下菜单禁用
- [ ] 休眠标签菜单项正确禁用；唤醒后 inspectable 仍跟偏好
- [ ] 无新增常驻 UserScript；`make browser` 通过
- [ ] 文本输入若用原生多行控件，遵守 SBKit

---

## 11. 开放决策（已拍板）

| 问题 | 决定 |
|------|------|
| 默认是否开启 inspectable？ | **否**（Release）；Debug 可选 registerDefaults 为 YES |
| 未开偏好时 ⌘⌥I？ | Alert +「打开设置」，不静默打开 |
| 源代码展示形态？ | 新标签 + HTML `<pre>`（可再 ⌘F） |
| 私有 show？ | Direct 构建可选；失败降级；不作为唯一路径 |
| 是否做精简自研面板？ | **否** |
