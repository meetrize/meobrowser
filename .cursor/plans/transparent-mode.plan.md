---
name: 透明模式
overview: 按 TM-0→TM-2 实现透明模式：Chrome 图标（精简左侧）、全 UI 隐藏、窗口/WebView 透明、页面只留文字样式；菜单栏 Status Item 负责进入/退出透明与退出应用。
todos:
  - id: tm-0-chrome-icon
    content: TM-0：ChromeActions 注册 transparentMode（插在精简左侧）+ WC wire
    status: completed
  - id: tm-0-status-item
    content: TM-0：BrowserStatusItemController 菜单栏图标与菜单（切换透明 / 退出 App）
    status: completed
  - id: tm-1-snapshot-hide
    content: TM-1：TransparentModeController 快照；隐藏全部 chrome；与 compact 显隐合并
    status: completed
  - id: tm-1-window-clear
    content: TM-1：窗口/WebView 透明；退出还原；全屏禁用进入
    status: completed
  - id: tm-2-page-style
    content: TM-2：页面 CSS/JS 只留字；导航/切标签重注
    status: completed
  - id: tm-2-session-docs
    content: TM-2：session 持久化；验收；更新 design/plan/README
    status: completed
isProject: true
---

# 透明模式 — Cursor 自动开发计划

> **依据**：[transparent-mode-design.md](docs/minimal-browser/transparent-mode-design.md) · [transparent-mode-development-plan.md](docs/minimal-browser/transparent-mode-development-plan.md)  
> **范围**：**TM-0～TM-2（首版）** · **TM-0～TM-2 已完成（首版）**  
> **构建**：每阶段结束后 `make browser`  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）

## Goal

开启透明模式后：浏览器壳全部消失，窗口与页面背景透明，大致只看见网页文字；通过 macOS 菜单栏 MeoBrowser 图标进入/退出透明，并可退出应用。

## 行为定稿

| 决策 | 定稿 |
|------|------|
| 图标顺序 | **透明 → 精简 → 置顶** |
| 页面 | 背景透明 + 藏媒体 + text-shadow |
| Status Item | 启动常驻 |
| 作用域 | key 窗口 |
| Esc | 不退出 |

## Scope

| 做 | 不做 |
|----|------|
| Chrome 图标 + Status Item | 鼠标穿透下层 App |
| 全 chrome 隐藏 + 窗透明 | Esc 退出 |
| 页面只留字注入 | 透明度滑杆 / 全局热键 |
| session `transparentMode` | 按域名样式 |

## 关键文件

| 区域 | 路径 |
|------|------|
| 新模块 | `SimpleBrowser/TransparentMode/*` |
| Chrome 注册表 | `ChromeActions/BrowserChromeActionItem*` · `BrowserTabStripChromeActionsView*` |
| 窗口壳 | `BrowserWindowController*` |
| 启动 | `AppDelegate*` |
| 会话 | `BrowsingPreferences*` |
| 构建 | `Makefile` |
| 文档 | `docs/minimal-browser/transparent-mode-*.md` · `docs/README.md` |

## 实现顺序

### TM-0

1. 注册 `transparentMode` 到精简左侧  
2. `BrowserStatusItemController` + 菜单  
3. toggle 先打通布尔与图标态  

### TM-1

1. 快照 / 还原  
2. hideAllChrome + 窗 clear + WebView drawsBackground=NO  
3. 与 compact 显隐统一  

### TM-2

1. 样式注入与导航重注  
2. session  
3. 验收与文档状态  

## 手测清单

1. 点透明 → 壳全无、可透视桌面  
2. 菜单栏退出透明 → UI 恢复（含精简/置顶）  
3. 菜单栏进入透明；退出 App  
4. 多窗 key 窗切换正确  
5. 精简 + 透明进出不打架  
