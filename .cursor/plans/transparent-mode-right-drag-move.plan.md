---
name: 透明右键拖窗
overview: 透明模式下网页区右键拖拽移动窗口；用 5pt 阈值保留普通右键菜单。按 RD-0→RD-2 实现。
todos:
  - id: rd-0-monitor
    content: RD-0：透明进出挂卸 RightMouse 本地监视器 + Idle/Armed 状态机
    status: completed
  - id: rd-1-move
    content: RD-1：超 5pt 后按屏幕 delta 更新 window.frame 跟手移窗
    status: completed
  - id: rd-2-menu
    content: RD-2：拖后抑菜单（吞 Up + willOpenMenu）并验收/文档
    status: completed
isProject: true
---

# 透明模式右键拖窗 — Cursor 计划

> **依据**：[transparent-mode-right-drag-move-design.md](docs/minimal-browser/transparent-mode-right-drag-move-design.md) · [transparent-mode-right-drag-move-development-plan.md](docs/minimal-browser/transparent-mode-right-drag-move-development-plan.md)  
> **范围**：RD-0～RD-2 · **状态：已完成（RD-0～RD-2）**  
> **构建**：每阶段 `make browser`  
> **提交信息**：简体中文（仅用户要求 commit 时）

## Goal

透明模式无标题栏可拖时，在网页区域右键拖拽即可移动窗口；短按右键仍弹出 WebKit 上下文菜单。

## 定稿

| 项 | 值 |
|----|-----|
| 范围 | 仅透明模式 + 网页内容区 |
| 阈值 | 5pt |
| 移窗 | 屏幕 delta → `setFrame` |
| 菜单 | 未超阈值放行；拖后吞 Up + willOpenMenu 取消 |

## 实现顺序

1. **RD-0** install/uninstall + Armed  
2. **RD-1** 跟手移窗  
3. **RD-2** 菜单双保险 + 文档勾选  

## 手测

1. 透明 → 右键单击出菜单  
2. 透明 → 右键拖动画移动且无菜单  
3. 退出透明 → 右键恢复  
4. 滚动/左键/链接点击正常  
