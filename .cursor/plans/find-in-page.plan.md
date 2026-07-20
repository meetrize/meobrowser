---
name: 页面内查找
overview: 按 FI-0→FI-2 实现页面内查找：工具栏🔍+⌘F 浮动条、JS 全部高亮与计数、字面/通配符双模式、F3/⌘G 循环跳转。
todos:
  - id: fi-0-docs
    content: 开发计划与 Cursor plan 落盘；更新 docs/README
    status: completed
  - id: fi-0-skeleton
    content: FI-0：FindInPage 模块骨架（Session/BarView/Controller）+ Makefile
    status: completed
  - id: fi-0-chrome
    content: FI-0：ActionGroup findInPage、⌘F/Esc、WindowController 挂载
    status: completed
  - id: fi-1-engine
    content: FI-1：find-in-page.js + BrowserFindEngine 注入与 search/next/prev/clear
    status: completed
  - id: fi-1-wire
    content: FI-1：防抖搜索、高亮计数、⌘G/F3、每标签 Session
    status: completed
  - id: fi-2-wildcard
    content: FI-2：模式标识通配符、选区/⌘E、导航清理、Mutation 防抖、Aa
    status: completed
  - id: fi-2-build-docs
    content: make browser 通过；勾选 development-plan；更新 design 状态
    status: completed
isProject: true
---

# 页面内查找 — Cursor 自动开发计划

> **依据**：[find-in-page-design.md](docs/minimal-browser/find-in-page-design.md) · [find-in-page-development-plan.md](docs/minimal-browser/find-in-page-development-plan.md)  
> **范围**：**FI-0～FI-2（首版）**；不做 FI-3 涟漪/胶囊/正则。  
> **状态**：**已完成（2026-07-20）** · `make browser` 通过。

## 交付摘要

| 模块 | 路径 |
|------|------|
| UI | `FindInPage/BrowserFindBarView*` · `BrowserFindBarController*` |
| 状态 | `BrowserFindSession*`（挂 `BrowserTab.findSession`） |
| 引擎 | `BrowserFindEngine*` · `Resources/find-in-page.js` |
| Chrome | ActionGroup `findInPage` · 查看菜单 ⌘F / ⌘G / ⌘⇧G / ⌘E |

## 手测

1. 打开普通网页 → ⌘F 或点 🔍 → 输入关键词 → 见高亮与 `n / m`
2. F3 / ⌘G 循环；Esc 清高亮
3. 点模式标识切通配，试 `foo*bar`
4. 选中文字后 ⌘F / ⌘E 自动填入
5. 新标签页 ⌘F 静默无效
