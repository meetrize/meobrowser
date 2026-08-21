---
name: 摸鱼模式
overview: 按 AFK-0→AFK-2 在透明图标左侧增加摸鱼模式：鼠标移出窗 frame 则仅 alpha=0 视觉隐藏（不做点击穿透），移入按原透明/非透明形态还原；与透明正交。
todos:
  - id: afk-0-entry
    content: AFK-0：Chrome 图标顺序摸鱼→透明→精简→置顶；WC 布尔；查看菜单勾选
    status: completed
  - id: afk-1-conceal
    content: AFK-1：AfkModeController + 全局鼠标监视；仅 alpha conceal/reveal（不改 ignoresMouseEvents）；与透明叠加手测
    status: completed
  - id: afk-2-polish
    content: AFK-2：Status Item 出口、全屏拦截、session、文档验收勾选
    status: completed
isProject: true
---

# 摸鱼模式 — Cursor 自动开发计划

> **依据**：[afk-mode-design.md](docs/minimal-browser/afk-mode-design.md) · [afk-mode-development-plan.md](docs/minimal-browser/afk-mode-development-plan.md)  
> **范围**：**AFK-0～AFK-2（首版）** · **已完成**  
> **构建**：每阶段结束后 `make browser`  
> **提交信息语言**：简体中文（仅当用户要求 commit 时）

## Goal

在标签栏 Chrome 动作区增加「摸鱼模式」：

1. **移出隐藏**：鼠标离开本窗 `frame` → 整窗视觉不可见（`alphaValue=0`）  
2. **移入还原**：回到 frame → 恢复显示；透明开着仍透明，未开则完整窗  
3. **不做穿透**：不设置 `ignoresMouseEvents`（移出后点击本就不在窗内）  
4. **正交**：不翻转 `transparentMode` / 精简 / 置顶布尔  

## 行为定稿

| 决策 | 定稿 |
|------|------|
| D1 位置 | 摸鱼 → 透明 → 精简 → 置顶 |
| D2 隐身 | **仅** `alphaValue=0` |
| D3 侦测 | 全局 + 本地 NSEvent + `NSMouseInRect` |
| D4 透明 | 正交叠加 |
| D5 全屏 | 禁止开；进全屏强制关 |
| D6 Dock | 不强制现身 |
| D7 session | `afkMode` |
| D11 穿透 | **V1 不做** |

## 实现摘要

| 阶段 | 产出 |
|------|------|
| AFK-0 | `BrowserChromeActionAfkModeID`、图标、`afkModeEnabled`、查看菜单 |
| AFK-1 | `BrowserAfkModeController` + MouseRouter；alpha conceal/reveal |
| AFK-2 | Status Item 进出摸鱼、全屏拦截、session、文档勾选 |

## 手测清单

1. 移出隐、移入现  
2. 透明+摸鱼移入仍透明  
3. 关摸鱼后不再隐  
4. Status Item 隐身可退出  
5. 全屏拦截；多窗隔离  
6. 无摸鱼相关 `ignoresMouseEvents` 赋值  
