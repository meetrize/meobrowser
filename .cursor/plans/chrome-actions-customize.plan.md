---
name: Chrome动作图标定制
overview: 七项 Chrome 动作（含自动滚动/滚动速度/窗口缩放）默认均显示在条上；可拖排序、可钉可藏；⋯ 为单一图钉菜单。
todos:
  - id: cp-0-store
    content: CP-0：Catalog 扩三项 + Layout Store + 默认全部可见渲染
    status: completed
  - id: cp-1-drag
    content: CP-1：拖拽改序 + 拖到⋯（三项行为已在 CP-0 wire）
    status: completed
  - id: cp-2-pin-menu
    content: CP-2：⋯ 单一图钉菜单（去掉两段式）
    status: completed
  - id: cp-3-polish
    content: CP-3：态同步、多窗、无障碍、文档验收
    status: completed
isProject: true
---

# 标签栏 Chrome 动作区定制 — Cursor 计划

> 设计：[docs/minimal-browser/chrome-actions-customize-design.md](../../docs/minimal-browser/chrome-actions-customize-design.md)  
> 开发：[docs/minimal-browser/chrome-actions-customize-development-plan.md](../../docs/minimal-browser/chrome-actions-customize-development-plan.md)

## 范围

- Catalog：摸鱼 / 透明 / 精简 / 置顶 / **自动滚动** / **滚动速度** / **窗口缩放**  
- 默认：七项全部在条上（hidden 空）  
- ⋯：不可拖；菜单 = 单一列表 + 图钉  

## 阶段

CP-0 Catalog+Store → CP-1 拖拽 → CP-2 单一菜单 → CP-3 打磨
