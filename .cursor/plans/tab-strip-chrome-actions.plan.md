---
name: 标签栏 Chrome 动作区
overview: 按 CA-0→CA-2 在标签条右侧实现可扩展 Chrome 动作区：精简模式（藏地址栏、◀▶ 迁到交通灯右侧、紧凑 metrics、⌘L Peek）与窗口置顶（NSFloatingWindowLevel + session）；为后续图标预留注册表。
todos:
  - id: ca-0-module
    content: CA-0：ChromeActions 模块（ActionItem + TabStripChromeActionsView）+ Makefile
    status: completed
  - id: ca-0-embed-strip
    content: CA-0：嵌入 BrowserTabStripView 右侧；扣减 layoutTabs 宽度；WC 挂载两图标
    status: completed
  - id: ca-1-compact-toggle
    content: CA-1：setCompactModeEnabled 藏工具栏；双高度 metrics；交通灯重对齐
    status: completed
  - id: ca-1-nav-move
    content: CA-1：◀▶ 搬家到 strip leadingNavigationView；reload 随行隐藏
    status: completed
  - id: ca-1-peek-menu
    content: CA-1：⌘L Peek、Esc/Return；查看菜单精简模式勾选
    status: completed
  - id: ca-2-always-on-top
    content: CA-2：置顶 level、菜单、浮层 order/level、全屏恢复
    status: completed
  - id: ca-2-session-docs
    content: CA-2：session 持久化；手测验收；更新 design/plan 状态与 README
    status: completed
isProject: true
---

# 标签栏右侧 Chrome 动作区 — Cursor 自动开发计划

> **依据**：[tab-strip-chrome-actions-design.md](docs/minimal-browser/tab-strip-chrome-actions-design.md) · [tab-strip-chrome-actions-development-plan.md](docs/minimal-browser/tab-strip-chrome-actions-development-plan.md)  
> **范围**：**CA-0～CA-2（首版）** · **CA-0～CA-2 已完成**  
> **构建**：每阶段结束后 `make browser`  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）

## Goal

在标签栏最右侧增加可扩展窗口级图标区；首版实现：

1. **精简模式**：隐藏整行地址栏（含右侧 ActionGroup）；前进/后退移到交通灯右侧；条高与间距收紧；⌘L Peek 临时改址  
2. **窗口置顶**：本窗 `NSFloatingWindowLevel`；图标/菜单可关  
3. **扩展点**：`BrowserTabStripChromeActionsView` 注册表，后续加图标不改标签布局主干

## 行为定稿

| 决策 | 定稿 |
|------|------|
| D1 刷新进标签条 | **否** |
| D2 精简改 URL | **⌘L Peek** |
| D3 动作区 | **标签条右侧独立模块**（非 AddressBar ActionGroup） |
| D4 置顶 level | **NSFloatingWindowLevel** |
| D5 状态 | **每窗口 + session** |
| D6 按钮 | **同一套 ◀▶ 搬家** |

## Scope

| 做 | 不做 |
|----|------|
| ChromeActions 模块 + 两图标 | 把查找/下载等迁进标签条 |
| 精简藏工具栏 + 紧凑 metrics | 双份 back/forward 按钮 |
| Peek ⌘L | 应用级「全部置顶」 |
| 置顶 + 浮层可见性 | 动作区拖拽排序 |
| session 键 | V2 ⋯ 溢出 / 默认精简偏好 |

## 关键文件

| 区域 | 路径 |
|------|------|
| 新模块 | `SimpleBrowser/ChromeActions/*` |
| 标签条 | `SimpleBrowser/Tabs/BrowserTabStripView.*` |
| 窗口壳 | `SimpleBrowser/BrowserWindowController.*` |
| 菜单 | `SimpleBrowser/BrowserMenus.*` |
| 会话键 | 与 `BrowserWindowSession*Key` 同文件/头 |
| 构建 | `Makefile` |
| 文档 | `docs/minimal-browser/tab-strip-chrome-actions-*.md` · `docs/README.md` |

## 实现顺序

### CA-0 — 骨架

1. `BrowserChromeActionItem` + `BrowserTabStripChromeActionsView`（默认 compactMode / alwaysOnTop）  
2. Strip：`+` 与 trailingDrag 之间嵌入；`layoutTabs` 扣宽  
3. WC wire 按钮（可先 toggle UI on 态）  
4. `make browser`；确认溢出 / 拖窗 / 交通灯无回归  

### CA-1 — 精简

1. `setCompactModeEnabled:` 隐藏 toolbar；Compact 高度 32 与 inset  
2. `setLeadingNavigationView:` 搬家 ◀▶；reload 隐藏  
3. 每次切换 `scheduleTrafficLightPositioning`  
4. ⌘L Peek + Esc/Return；菜单「精简模式」  
5. `make browser` + 手测 Peek / 多标签溢出  

### CA-2 — 置顶与收尾

1. `setAlwaysOnTopEnabled:`；窗口菜单勾选  
2. 浮层 level/order 相对父窗（download、补全、ghost…）  
3. session 读写；多窗重启  
4. 按 design §9 验收；更新文档状态  

## 手测清单

1. 点精简 → 地址栏消失，◀▶ 在交通灯右，再点恢复  
2. 精简下 ⌘L → 展开输入 → Return 收起仍精简；Esc 收起  
3. 置顶开 → 切到其它 App 本窗仍在上；关后正常  
4. 两窗不同状态；重启恢复  
5. 标签拖拽 / 跨窗 / 溢出 / 下载面板 / 查找条不回归  

## 性能约束

- 无 timer 维持置顶  
- 精简用 hidden/约束，不销毁工具栏  
- 标签项保持现有 frame 布局路径  
