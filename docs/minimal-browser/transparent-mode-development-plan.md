# 透明模式 — 开发计划

> 基于 [transparent-mode-design.md](transparent-mode-design.md) 的分阶段实施计划。  
> 前置条件：ChromeActions（CA-0～CA-2）、多窗口 session、`BrowserWindowController` chrome 显隐已就绪。  
> 状态：**TM-0 / TM-1 / TM-2 已完成（首版交付）**  
> Cursor 计划：[.cursor/plans/transparent-mode.plan.md](../../.cursor/plans/transparent-mode.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 图标位置 | 标签条右侧，**精简左侧**：透明 → 精简 → 置顶 |
| 页面效果 | 背景透明 + 隐藏媒体；文字保留 + text-shadow |
| Status Item | 启动常驻；菜单：进入/退出透明、退出 App |
| 切换作用域 | 优先 key 窗口 |
| Esc | 不退出透明 |
| 全屏 | 禁止新进透明 |
| 持久化 | session 键 `transparentMode` |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase TM-0 | 入口与 Status Item | 完成 | Chrome 图标 + 菜单栏图标与菜单骨架 |
| Phase TM-1 | 壳隐藏与窗口透明 | 完成 | 全 chrome 隐藏、窗口/WebView 透明、可逆快照 |
| Phase TM-2 | 页面「只留字」与打磨 | 完成 | CSS/JS 注入、切标签/导航重注、session、验收 |

**首版交付目标：TM-0 + TM-1 + TM-2。**

---

## Phase TM-0：入口与 Status Item

**目标**：两端入口可见、可点；尚可不改窗口观感（或仅 toggle 布尔 + 图标态）。

### 任务清单

#### 0A — Chrome 图标

- [x] **0.1** `BrowserChromeActionTransparentModeID` + defaultItems 插入到 compact **之前**
- [x] **0.2** SF Symbol / tooltip（设计 §3.1）
- [x] **0.3** `BrowserWindowController` wire `toggleTransparentMode:` → 暂设布尔 + `setOn:`

#### 0B — Status Item

- [x] **0.4** 新建 `BrowserStatusItemController` 单例；`AppDelegate` launch 时 `install`
- [x] **0.5** 菜单：「进入透明模式」/「退出透明模式」（随状态改标题或 state）、「退出 MeoBrowser」
- [x] **0.6** toggle → key `BrowserWindowController`；quit → `[NSApp terminate:nil]`
- [x] **0.7** Makefile：`TransparentMode/*.m` + `-ITransparentMode`
- [x] **0.8** `make browser`；手测菜单栏图标与标签条三图标顺序

---

## Phase TM-1：壳隐藏与窗口透明

**目标**：进入后完全看不到浏览器 UI，窗口可透视；退出完整还原。

### 任务清单

#### 1A — 控制器与快照

- [x] **1.1** `BrowserTransparentModeController` 挂 WC
- [x] **1.2** 进入前快照：opaque / backgroundColor / hasShadow / accessory / toolbar / 交通灯 / 侧栏
- [x] **1.3** `-setTransparentModeEnabled:` 统一入口（图标、Status Item、日后菜单共用）

#### 1B — 隐藏 chrome

- [x] **1.4** 隐藏 titlebar accessory（或高度 0 + 交通灯 hidden）
- [x] **1.5** toolbar / 侧栏 / 查找 / 下载面板等 orderOut 或 hide
- [x] **1.6** 与 compact 的 `applyChromeVisibility` 合并，避免双路径打架

#### 1C — 窗口透明

- [x] **1.7** `opaque=NO`、`backgroundColor=clear`、`hasShadow=NO`
- [x] **1.8** contentContainer / WebView `drawsBackground=NO`（公开 API 优先）
- [x] **1.9** 退出严格按快照还原；compact / alwaysOnTop 布尔保留并重放布局
- [x] **1.10** 全屏中 validate 禁止进入；`make browser` + 手测进出

---

## Phase TM-2：页面样式、会话与验收

**目标**：「只留字」效果可用；导航/切标签不掉样式；文档收尾。

### 任务清单

#### 2A — 样式注入

- [x] **2.1** `BrowserTransparentModeStyle` 资源（JS 插入/移除 style#meo-transparent-mode）
- [x] **2.2** 进入 / `didFinishNavigation` / 选中标签变化时 apply
- [x] **2.3** 退出时 remove；非选中 WebView 不留脏样式（或切回再注）

#### 2B — 同步与持久化

- [x] **2.4** Status Item 菜单文案/勾选与 key 窗状态同步
- [x] **2.5** 可选：查看菜单「透明模式」
- [x] **2.6** session 键读写 + sanitize 透传
- [x] **2.7** NTP/特殊页：允许透明壳，样式尽力而为

#### 2C — 验收与文档

- [x] **2.8** 按 design §8 手测清单
- [x] **2.9** 回归：精简、置顶、多窗、拖标签、下载面板
- [x] **2.10** 更新 design 状态、本计划勾选、`docs/README.md`；`make browser` 无警告

---

## 建议实现顺序（给 Agent）

1. TM-0（入口打通）  
2. TM-1（壳 + 窗透明，先保证「能进出」）  
3. TM-2（页面只留字 + session）  

每阶段结束 `make browser`。提交信息使用简体中文（仅当用户要求 commit 时）。

---

## 非目标（本计划不做）

- 鼠标穿透到下层 App  
- Esc 退出透明  
- 全局快捷键 / 透明度滑杆  
- 按域名的样式配置  
