# 轻量开发者工具（Web Inspector）— 开发计划

> 基于 [web-inspector-design.md](web-inspector-design.md) 的分阶段实施计划。  
> 前置条件：多标签、`BrowserMenus` 查看菜单、`BrowserSettingsWindowController`、`BrowserWebView.reloadFromOrigin`、标签休眠已就绪。  
> 状态：**DI-0 / DI-1 / DI-2 已完成**；DI-3 可选。  
> 关联：[professional-features-roadmap.md](professional-features-roadmap.md) §3.2

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 偏好默认 | Release：`允许网页检查 = NO`；Debug 可 `registerDefaults` 为 YES |
| ⌘⌥I 未开偏好 | Alert 说明 +「打开设置」按钮；**不**静默改偏好 |
| ⌘⌥I 已开偏好 | 尝试 `BrowserWebInspector` show；失败 → Alert 指引 Safari「开发」菜单 |
| ⌘⇧R | `reloadFromOrigin`；错误页 pending URL 时与普通刷新一样先清错误再硬刷目标 URL（实现时与 `reloadPage:` 对齐） |
| ⌘⌥U / 查看源代码 | 新标签展示 DOM `outerHTML` 包装页；**不**写入会话恢复 |
| 右键 | `willOpenMenu:` 增加「查看网页源代码」 |
| 私有 API show | 编译宏 `MEO_ENABLE_PRIVATE_INSPECTOR_SHOW`（Makefile Direct 默认可开）；MAS/关宏时仅降级 |
| 常驻注入 | **禁止** |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| Phase DI-0 | 可检查底座 | 0.5～1 日 | Preferences + inspectable + 设置 UI + Safari 路径可用 |
| Phase DI-1 | 菜单主路径 | 0.5～1 日 | ⌘⌥I（show/降级）、⌘⇧R、validate |
| Phase DI-2 | 查看源代码 | 0.5～1 日 | 菜单 + 右键 + 新标签只读源码 |
| Phase DI-3 | 体验（可选） | 按需 | 命令面板、宏拆分文档化、截断/空状态打磨 |

**首版交付目标：DI-0 + DI-1 + DI-2（约 1.5～3 人日）。**

建议节奏：半天 DI-0，半天 DI-1，半天 DI-2 + 手测。

---

## Phase DI-0：可检查底座

**目标**：用户打开设置开关后，可用 Safari「开发」菜单附加 MeoBrowser 页面；关闭时与现状一致。

### 任务清单

#### 0A — Preferences 与 Inspector 工具类

- [x] **0.1** 新建 `SimpleBrowser/Developer/BrowserDeveloperPreferences.h/.m`
  - `+sharedPreferences` 或类方法读写即可（对齐 `BrowserLocationPreferences` 风格）
  - `allowWebInspection`（BOOL，UserDefaults `MeoBrowserAllowWebInspection`）
  - 变更时发 `BrowserDeveloperPreferencesDidChangeNotification`
- [x] **0.2** 新建 `SimpleBrowser/Developer/BrowserWebInspector.h/.m`
  - `+applyInspectableToWebView:`（`@available(macOS 13.3, *)`，按偏好设 `inspectable`）
  - `+isInspectionSupported`（系统版本）
  - 本阶段 **不必**实现 show
- [x] **0.3** Makefile：加入 `Developer/*.m`，`-IDeveloper`（或统一 `-ISimpleBrowser` 已有则只加源文件）

#### 0B — 应用到 WebView

- [x] **0.4** `BrowserTab.ensureWebView`：创建 `BrowserWebView` 后调用 `applyInspectableToWebView:`
- [x] **0.5** `BrowserWindowController`（或 AppDelegate）监听偏好通知：遍历本窗 / 所有窗 live WebView 并 apply
- [x] **0.6** 确认 `createWebViewWithConfiguration:` 弹出的 WebView 也走 `ensureWebView` 或显式 apply

#### 0C — 设置 UI

- [x] **0.7** `BrowserSettingsWindowController` 增加「开发者」分区
  - 复选框绑定 `allowWebInspection`
  - 次要说明：Safari「开发」菜单附加方式
  - `< 13.3`：禁用复选框 + 版本提示
- [x] **0.8**（可选）Debug：`AppDelegate` `registerDefaults` 将 key 设为 YES

#### 0D — 验收 DI-0

- [ ] **0.9** 开关关：Safari 开发菜单中不应可检（或不可用）
- [ ] **0.10** 开关开：附加成功，Elements / Console / Network 可用
- [ ] **0.11** 关→开→已有标签无需重启即可附加
- [x] **0.12** `make browser` 通过

**DI-0 代码已落地（2026-08-14）**；0.9～0.11 需本机 Safari「开发」菜单手测。
---

## Phase DI-1：菜单主路径

**目标**：查看菜单可打开 Inspector（或降级指引），并支持强制刷新。

### 任务清单

#### 1A — 菜单项

- [x] **1.1** `BrowserMenus`「查看」：在「刷新」下增加「强制刷新」⌘⇧R（`keyEquivalent:@"r"` + Command+Shift）
- [x] **1.2** 增加「打开 Web Inspector」⌘⌥I（`@"i"` + Command+Option）
- [x] **1.3** 分隔符与现有查找 / 通知项排布符合设计 §6.1

#### 1B — WindowController 行为

- [x] **1.4** `hardReloadPage:`
  - 对齐 `reloadPage:` 的休眠 / pending 错误 URL 处理
  - 有文档时调用 `reloadFromOrigin`
- [x] **1.5** `openWebInspector:`
  - 无 WebView / Launchpad → return
  - 未开偏好 → Alert + 打开设置（`showBrowserSettings:`）
  - 已开 → `[BrowserWebInspector showInspectorForWebView:]`
- [x] **1.6** `validateMenuItem:` 覆盖新 action（与 `reloadPage:` 类似条件）

#### 1C — 程序化 Show + 降级

- [x] **1.7** `BrowserWebInspector+show`
  - 公开 API（若有）
  - `#if MEO_ENABLE_PRIVATE_INSPECTOR_SHOW` 可选私有路径（`respondsToSelector` / 无硬链符号）
  - 返回 BOOL 或 NSError；失败由 VC 弹降级 Alert
- [x] **1.8** Makefile：Direct 目标定义 `MEO_ENABLE_PRIVATE_INSPECTOR_SHOW=1`（或默认开、文档说明如何关）
- [x] **1.9** 降级 Alert 文案按设计 §4.3

#### 1D — 验收 DI-1

- [ ] **1.10** ⌘⇧R 绕过缓存（可用 Cache-Control 测试页或本地 server 验证）
- [ ] **1.11** ⌘R 行为不变
- [ ] **1.12** ⌘⌥I：开偏好下 show 或降级指引正确；未开偏好进设置
- [ ] **1.13** 与 ⌘⇧I 通知侧栏无冲突
- [ ] **1.14** Launchpad / 休眠：菜单项禁用

**DI-1 代码已落地（2026-08-14）**；1.10～1.14 需本机手测。`make browser MEO_ENABLE_PRIVATE_INSPECTOR_SHOW=0` 可关闭私有 show。
---

## Phase DI-2：查看网页源代码

**目标**：不依赖 Inspector 即可查看当前文档 DOM 序列化结果。

### 任务清单

#### 2A — 取源与展示

- [x] **2.1** `BrowserWindowController.viewPageSource:`（或 `Developer/` 内 helper）
  - `evaluateJavaScript` 取 `document.documentElement.outerHTML`
  - 空 / 失败 → 简短 Alert
  - 超大字符串截断（阈值按设计，如 5 MB）并提示
- [x] **2.2** 包装为只读 HTML（`<pre>` + 等宽、转义 `<` 等）或 `data:text/plain`
- [x] **2.3** `tabController` 开新标签加载；标题「源代码 — …」
- [x] **2.4** 标记不可会话恢复：扩展 `BrowsingPreferences.isPersistableURL` 或加载前设 tab 标志 / 使用约定 URL scheme（如 `meo-source:` 且 persist 返回 NO）

#### 2B — 入口

- [x] **2.5** `BrowserMenus`：「查看网页源代码」⌘⌥U
- [x] **2.6** `BrowserWebView.willOpenMenu:` 插入右键项 → 转发 window `viewPageSource:`
- [x] **2.7** `validateMenuItem:`：无文档 / Launchpad 禁用

#### 2C — 验收 DI-2

- [ ] **2.8** 普通 HTML 页可显示源码；⌘F 可在源码标签内查找（若用 WebView+`<pre>`）
- [ ] **2.9** 关闭源码标签不留会话垃圾；重启不恢复该标签
- [ ] **2.10** 右键与菜单一致
- [ ] **2.11** 对照设计 §10 清单手测；更新 [acceptance.md](acceptance.md) 可选一行

**DI-2 代码已落地（2026-08-14）**；2.8～2.11 需本机手测。
---

## Phase DI-3：体验（可选，不阻塞首版）

- [ ] **3.1** 命令面板命令：打开 Inspector / 查看源代码 / 强制刷新（依赖命令面板立项）
- [ ] **3.2** 设置内「一键打开 Safari 开发菜单说明」链接到系统偏好或帮助短文
- [ ] **3.3** MAS 构建明确 `-UMEO_ENABLE_PRIVATE_INSPECTOR_SHOW`；CI 双配置编译
- [ ] **3.4** 源代码页空状态文案：「当前为 DOM 快照，可能与原始 HTTP 响应不同」
- [ ] **3.5** 原始响应 body 查看（需另设计：WK 导航数据管道，**不在本方案 V1**）

---

## 关键改动面（预期）

| 文件 / 目录 | 变更 |
|-------------|------|
| `SimpleBrowser/Developer/*` | **新建** Preferences + WebInspector |
| `SimpleBrowser/Tabs/BrowserTab.m` | ensureWebView 后 apply |
| `SimpleBrowser/BrowserMenus.m` | 三项菜单 |
| `SimpleBrowser/BrowserWindowController.m` | actions、validate、通知、view source |
| `SimpleBrowser/BrowserSettingsWindowController.m` | 开发者分区 |
| `SimpleBrowser/Tabs/BrowserWebView.m` | 右键源码 |
| `SimpleBrowser/BrowsingPreferences.*` 或等价 | 源码 URL 不可 persist |
| `Makefile` | 源文件 + 可选宏 |
| `docs/minimal-browser/acceptance.md` | 可选补验收行 |
| `docs/minimal-browser/professional-features-roadmap.md` | 勾选/链到本方案 |

---

## 测试清单（手测）

| # | 步骤 | 期望 |
|---|------|------|
| 1 | 默认设置，开任意站，看 Activity Monitor | 无 Web Inspector 相关常驻 |
| 2 | 设置打开「允许网页检查」，Safari 开发 → MeoBrowser | 可附加，Console 能 `console.log` |
| 3 | 关掉开关，已打开的 Inspector / 附加 | 新 WebView 不可检；说明符合预期即可 |
| 4 | ⌘⌥I 未开偏好 | Alert → 设置 |
| 5 | ⌘⌥I 已开 | 弹出或降级指引 |
| 6 | ⌘⇧R | 强制绕过缓存重载 |
| 7 | ⌘⌥U / 右键查看源代码 | 新标签源码；重启不恢复 |
| 8 | 新标签 Launchpad | Inspector / 源码 / 硬刷菜单禁用 |
| 9 | 休眠标签选中 | 菜单禁用或先唤醒（与刷新一致） |
| 10 | 多窗口各开一页 | 各自可附加 / ⌘⌥I |

---

## 风险与回滚

| 风险 | 回滚 |
|------|------|
| 私有 show 崩溃 / 拒审 | 关编译宏；保留 inspectable + Safari 路径 |
| 源码页进会话 | 修 persist 规则；清理错误写入 |
| 设置窗过高 | 「开发者」区可折叠或缩短 hint |

回滚粒度：可按 DI-2 → DI-1 → DI-0 逆序撤菜单与模块；`inspectable` 相关可整目录删除且不影响浏览主路径。

---

## 完成定义（DoD）

- [ ] DI-0～DI-2 任务清单全部勾选
- [ ] 设计 §10 验收标准全部满足
- [ ] 路线图 §3.2「打开 Web Inspector / 查看源代码 / 硬刷新」可标为已落地（或注明 Safari 附加为等价路径）
- [ ] 无新增常驻 UserScript；无 SBKit 违规输入框
