---
name: 自动滚速度精细化
overview: 速度范围改为 10～200 px/s；用亚像素累积解决慢速被 delta&lt;0.5 丢掉导致不滚的问题。
todos:
  - id: as-0-range
    content: AS-0：Preferences + 设置滑杆改为 10～200
    status: completed
  - id: as-1-carry
    content: AS-1：tick 亚像素累积，满 1px 再滚
    status: completed
  - id: as-2-verify
    content: AS-2：手测 10/80/200 + 文档勾选
    status: completed
isProject: true
---

# 自动滚动速度精细化

设计：`docs/minimal-browser/auto-scroll-speed-refinement-design.md`  
计划：`docs/minimal-browser/auto-scroll-speed-refinement-development-plan.md`

**已完成。** 根因：约 30Hz 下 `delta < 0.5` 会丢掉 10～25 px/s 的步进；现用 `pendingScrollPx` 累积满 1px 再滚。
