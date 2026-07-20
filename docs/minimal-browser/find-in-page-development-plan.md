# 页面内查找 — 开发计划

> 基于 [find-in-page-design.md](find-in-page-design.md) 的分阶段实施计划。  
> 前置条件：多标签、ActionGroup、SBKit 文本输入、`BrowserMenus` chrome 菜单已就绪。  
> **状态：FI-0～FI-2 已完成（2026-07-20）。**  
> Cursor 计划：[.cursor/plans/find-in-page.plan.md](../../.cursor/plans/find-in-page.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| ⌘F | 打开并聚焦；已打开则全选查询词（**不** toggle 关闭） |
| Esc | 关闭查找条 + 清除高亮 + 焦点回 WebView |
| 下一处 | F3 / ⌘G / 条内 Return |
| 上一处 | ⇧F3 / ⌘⇧G / 条内 ⇧Return |
| ⌘E | 使用选区填入并打开查找（FI-2） |
| Launchpad / 不可查页 | ⌘F **静默忽略** |
| 锚点 | 内容区右上角 overlay（可成为 key） |
| 区分大小写 | Aa 选项菜单；默认忽略；窗口级记忆 |
| JS 资源 | `FindInPage/Resources/find-in-page.js` 拷入 App Resources |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase FI-0 | 骨架 | 完成 | ActionGroup + 查找条 UI + ⌘F/Esc |
| Phase FI-1 | 字面查找 | 完成 | JS 引擎、高亮全部、计数、上下跳转、wrap |
| Phase FI-2 | 通配与打磨 | 完成 | 模式标识、通配、选区/⌘E、导航清理、Mutation 防抖 |
| Phase FI-3 | 体验（可选） | 待办 | 涟漪、胶囊、避让、`?` 通配 |

**首版交付目标：FI-0 + FI-1 + FI-2（已完成）。**

---

## Phase FI-0：骨架

**目标**：工具栏与菜单能打开浮动查找条，输入框可用，尚不搜索网页。

### 任务清单

#### 0A — 模块与构建

- [x] **0.1** 创建 `SimpleBrowser/FindInPage/`
- [x] **0.2** `BrowserFindBarView.h/.m`（模式位、`SBTextField`、清空、上/下、计数）
- [x] **0.3** `BrowserFindBarController.h/.m`（show/focus/hide、锚到 `contentContainer`）
- [x] **0.4** `BrowserFindSession.h/.m`（query / mode / caseSensitive / index / count）
- [x] **0.5** Makefile：源文件 + `-IFindInPage`

#### 0B — Chrome 入口

- [x] **0.6** ActionGroup 注册 `findInPage`（`magnifyingglass`），暴露 `findInPageButton`
- [x] **0.7** `BrowserWindowController` wire 按钮 → `showFindBar:`
- [x] **0.8** `BrowserMenus`：查看菜单「在页面中查找」⌘F；校验 `!isNewTabPage`
- [x] **0.9** Esc 关闭（条内 `cancelOperation:` + local key monitor）

#### 0C — 条 UI 行为

- [x] **0.10** 打开：贴内容区右上；聚焦输入；有字显示 ✕
- [x] **0.11** 已打开再 ⌘F：聚焦并全选
- [x] **0.12** 清空 ✕ 清空文字；上下按钮随匹配启用
- [x] **0.13** 计数显示 `当前 / 总数` 或 `—`

---

## Phase FI-1：字面查找

**目标**：忽略大小写的字面匹配；全部高亮；`当前/总数`；循环跳转。

### 任务清单

#### 1A — 引擎

- [x] **1.1** `BrowserFindEngine` + `Resources/find-in-page.js`
- [x] **1.2** `configureWebViewConfiguration:` 注入 UserScript
- [x] **1.3** API：`search` / `next` / `prev` / `clear`；返回 JSON
- [x] **1.4** 跳过 `script`/`style`；不进入 `input`/`textarea`
- [x] **1.5** 匹配上限 2000；查询经 JSON 转义

#### 1B — 联调

- [x] **1.6** 输入防抖 100 ms → `search`；更新计数与按钮 enabled
- [x] **1.7** 非当前 / 当前命中两套高亮样式；`scrollIntoView` center
- [x] **1.8** F3 / ⌘G / Return → next；⇧ 变体 → prev；wrap
- [x] **1.9** Esc / hide → `clear` 高亮
- [x] **1.10** 每标签 `BrowserFindSession`；切标签换绑并恢复 UI

#### 1C — 菜单

- [x] **1.11** 「查找下一个」⌘G、「查找上一个」⌘⇧G

---

## Phase FI-2：通配与打磨

**目标**：双模式、选区填入、导航与 SPA 稳定。

### 任务清单

- [x] **2.1** 模式标识切换字面 ⇄ 通配符；窗口级记住上次模式
- [x] **2.2** 通配：`*` → `[\s\S]*?`，其余转义；仅 `*` 视为无效
- [x] **2.3** 打开时取选区填入（截断 200）；⌘E 同路径
- [x] **2.4** `didCommit`/`didFinish`：clear 高亮，保留 query/mode，完成后自动重搜
- [x] **2.5** MutationObserver 防抖 250 ms 重搜
- [x] **2.6** Wrap 时计数短暂强调色
- [x] **2.7** Aa 选项：区分大小写（默认关）
- [x] **2.8** `make browser` 通过；对照设计 §8 手测

---

## Phase FI-3：体验（可选，不阻塞首版）

- [ ] **3.1** 当前命中涟漪
- [ ] **3.2** 失焦收成胶囊 `n/m`
- [ ] **3.3** 条避让当前命中矩形
- [ ] **3.4** 通配 `?` 单字符

---

## 验收清单（首版 FI-0～FI-2）

- [x] 工具栏 🔍 与 ⌘F 打开查找条；溢出菜单可用
- [x] Esc 关闭并清高亮
- [x] `SBTextField` 编辑快捷键；清空 ✕
- [x] 字面忽略大小写；全部高亮；`当前/总数`
- [x] F3/⌘G 循环；通配 `foo*bar`；字面下 `*` 为普通字符
- [x] 选区 → ⌘F / ⌘E；标签状态隔离；换页清高亮留词
- [x] 超多匹配有上限；查询 JSON 转义防注入

### 发布检查

```bash
make clean && make browser
make run-browser
```

---

## 实现文件

| 路径 | 阶段 |
|------|------|
| `SimpleBrowser/FindInPage/BrowserFindBarView.*` | FI-0 |
| `SimpleBrowser/FindInPage/BrowserFindBarController.*` | FI-0 |
| `SimpleBrowser/FindInPage/BrowserFindSession.*` | FI-0 |
| `SimpleBrowser/FindInPage/BrowserFindEngine.*` | FI-1 |
| `SimpleBrowser/FindInPage/Resources/find-in-page.js` | FI-1 |
| `SimpleBrowser/AddressBar/BrowserAddressBarActionGroup.*` | FI-0 |
| `SimpleBrowser/BrowserMenus.m` | FI-0 / FI-1 |
| `SimpleBrowser/BrowserWindowController.m` | FI-0～FI-2 |
| `SimpleBrowser/Tabs/BrowserTab.h`（`findSession`） | FI-1 |
| `Makefile` | FI-0～FI-1 |
