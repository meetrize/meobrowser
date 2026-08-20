# 标签栏右侧 Chrome 动作区 — 开发计划

> 基于 [tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) 的分阶段实施计划。  
> 前置条件：多标签 titlebar accessory、`BrowserTabStripView` 自适应宽度、多窗口 session、地址栏 ActionGroup 已就绪。  
> 状态：**CA-0～CA-2 已完成**  
> Cursor 计划：[.cursor/plans/tab-strip-chrome-actions.plan.md](../../.cursor/plans/tab-strip-chrome-actions.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 动作区位置 | 标签条右侧：`+` 与 trailingDrag 之间 |
| 精简隐藏范围 | 整行工具栏（◀▶↻ + 地址栏 + ActionGroup） |
| 迁入标签条 | **仅** ◀▶；↻ 随工具栏隐藏（⌘R） |
| 按钮实例 | 同一套 back/forward **搬家**，不双份 |
| 精简改 URL | ⌘L **Peek** 临时展开；Return 后收起；Esc 取消 |
| 置顶 | `NSFloatingWindowLevel`；每窗独立 |
| 持久化 | `sessionDictionary` 键 `compactMode` / `alwaysOnTop` |
| 扩展 | `BrowserTabStripChromeActionsView` 注册表 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase CA-0 | 骨架与动作区 | 完成 | ChromeActions 模块、标签条右侧挂载、两图标 UI（尚无完整行为） |
| Phase CA-1 | 精简模式 | 完成 | 藏工具栏、◀▶ 搬家、紧凑 metrics、Peek ⌘L、菜单 |
| Phase CA-2 | 置顶与持久化 | 完成 | window 切换、浮层 level、session、菜单、验收 |

**首版交付目标：CA-0 + CA-1 + CA-2。**

---

## Phase CA-0：骨架与动作区

**目标**：标签条右侧出现可扩展图标组；精简/置顶按钮可点但可先做 no-op 或仅切换 UI 态。

### 任务清单

#### 0A — 模块与构建

- [x] **0.1** 创建 `SimpleBrowser/ChromeActions/`
- [x] **0.2** `BrowserChromeActionItem`（id / symbol / onSymbol / tooltip / toggles）
- [x] **0.3** `BrowserTabStripChromeActionsView`：横向排布按钮、`reloadWithItems:`、`buttonForItemID:`、`setOn:forItemID:`
- [x] **0.4** 默认 items：`compactMode`、`alwaysOnTop`（SF Symbol 按设计 §3.3）
- [x] **0.5** Makefile：源文件 + `-IChromeActions`（或统一 `-ISimpleBrowser` 既有方式）

#### 0B — 嵌入标签条

- [x] **0.6** `BrowserTabStripView` 增加 `chromeActionsView` 容器；布局扣减其宽度
- [x] **0.7** 保留 `trailingDrag` ≥ 8pt；更新 `layoutTabs` 公式与注释
- [x] **0.8** `BrowserWindowController` 创建 actions view，设 target/action 占位
- [x] **0.9** 手测：多标签溢出、+、拖窗、交通灯不回归；`make browser` 通过

#### 0C — 文档状态

- [x] **0.10** 本计划 CA-0 勾选；design 状态可标「实现中」

---

## Phase CA-1：精简模式

**目标**：完整精简交互 + Peek + 紧凑尺寸。

### 任务清单

#### 1A — 工具栏显隐

- [x] **1.1** 抽出并对 `toolbar` / `navButtons` 强引用
- [x] **1.2** `-setCompactModeEnabled:`：hidden 或高度 0；通知 tabStrip 紧凑 metrics
- [x] **1.3** 切换后 `scheduleTrafficLightPositioning` + strip 重新 layout
- [x] **1.4** Reduce Motion：跳过高度动画

#### 1B — ◀▶ 搬家

- [x] **1.5** `BrowserTabStripView` `-setLeadingNavigationView:`（nil = 常态）
- [x] **1.6** 精简开：将 back/forward（或整 nav 且 reload.hidden）挂到 leading；调整 leading 宽度
- [x] **1.7** 精简关：迁回 toolbar；reload 恢复显示
- [x] **1.8** `updateNavigationButtons`（canGoBack/Forward）在两种挂载下均有效

#### 1C — 紧凑 metrics

- [x] **1.9** 双高度常量 Regular 36 / Compact 32；accessory 高度约束可更新
- [x] **1.10** 精简下 inset / 按钮尺寸按设计 §3.2
- [x] **1.11** 手测交通灯与 ◀▶ 无重叠（多分辨率）

#### 1D — Peek ⌘L

- [x] **1.12** `BrowserMenus`：「打开位置…」⌘L → First Responder
- [x] **1.13** `-focusAddressBar:` / Peek：若 compact，临时展开工具栏并聚焦；设 `addressBarPeekActive`
- [x] **1.14** Return 导航成功路径结束 Peek（保持 compact=YES）
- [x] **1.15** Esc / cancelOperation 结束 Peek；焦点回 WebView
- [x] **1.16** Peek 中关闭精简：退出 compact，工具栏保持开

#### 1E — 入口同步

- [x] **1.17** 精简图标 toggle + `setOn:`
- [x] **1.18** 查看菜单「精简模式」可勾选 + `validateMenuItem:`

---

## Phase CA-2：置顶、持久化与验收

**目标**：置顶可靠；会话恢复；浮层不挡；文档收尾。

### 任务清单

#### 2A — 置顶

- [x] **2.1** `-setAlwaysOnTopEnabled:` 设置 `NSFloatingWindowLevel` / `NSNormalWindowLevel`
- [x] **2.2** 图标 `pin` / `pin.fill` + 菜单「窗口置顶」
- [x] **2.3** 退出全屏后重放 level（若曾开启）
- [x] **2.4** 扫浮层：download / autocomplete / ghost / captcha 等相对父窗可见（设计 §6.3）

#### 2B — 会话

- [x] **2.5** session 键写入 / 读取；旧会话缺省为 NO
- [x] **2.6** `applySessionDictionary:` 在 UI 就绪后应用 compact + onTop
- [x] **2.7** 多窗：A/B 状态独立；重启抽检

#### 2C — 验收与文档

- [x] **2.8** 按 design §9 手测清单全过
- [x] **2.9** 回归：标签拖拽、跨窗拖放、溢出菜单、查找/下载面板
- [x] **2.10** `make browser` 无警告；勾选本计划；design 状态改为已实现；更新 `docs/README.md`（若尚未）

---

## 建议实现顺序（给 Agent）

1. CA-0 整阶段（先看得见按钮）  
2. CA-1A → 1B → 1C → 1D → 1E  
3. CA-2 整阶段  

每阶段结束执行 `make browser`。提交信息使用简体中文（仅当用户要求 commit 时）。

---

## 非目标（本计划不做）

- ActionGroup 图标迁入标签条  
- 应用级一键置顶全部窗口  
- Chrome 动作拖拽排序 / UserDefaults 隐藏  
- V2 ⋯ 溢出与设置里「默认精简」
