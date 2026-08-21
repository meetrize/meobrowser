---
name: 更多菜单自动滚大小窗
overview: 按 MO-0→MO-3 在置顶右侧加 ⋯ 菜单：自动竖向滚动（设置调速即时生效）+ 大窗/小窗布局预设（小窗含透明）。
todos:
  - id: mo-0-ellipsis
    content: MO-0：置顶右侧 ⋯ 入口与菜单骨架
    status: completed
  - id: mo-1-autoscroll
    content: MO-1：自动滚动 + 设置滑杆即时生效 + 打断/到底
    status: completed
  - id: mo-2-layout
    content: MO-2：大窗/小窗预设与透明快照
    status: completed
  - id: mo-3-polish
    content: MO-3：全屏禁用、手测、文档勾选
    status: completed
isProject: true
---

# 标签栏「更多」菜单 — Cursor 计划

> **已完成（MO-0～MO-3）**

## 实现摘要

- Chrome `ellipsis` → 菜单：自动滚动 / 滚动速度… / 窗口放大↔缩小（单项切换）  
- `BrowserAutoScrollController` + 设置滑杆（20–500 px/s）  
- `BrowserWindowLayoutPresetStore` + 缩小态透明快照  
