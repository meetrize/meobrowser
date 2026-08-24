---
name: 重页 UI 响应性
overview: 按 HP-0→HP-3 治理直播等重页拖慢 UI：标签拖拽门控、切页关键路径瘦身、失活 pause 媒体、mediaHeavy 加速休眠、progress 节流。
todos:
  - id: hp-0-gesture-refresh
    content: HP-0：拖拽 10pt+150ms 门控；refreshTabsUI 关键/延后拆分
    status: completed
  - id: hp-1-pause-media
    content: HP-1：失活 pause/mute 媒体；mediaHeavy；跳过昂贵快照
    status: completed
  - id: hp-2-fast-hibernate
    content: HP-2：mediaHeavy 90s 休眠 + 预算优先淘汰
    status: completed
  - id: hp-3-throttle-polish
    content: HP-3：estimatedProgress 节流；手测与文档勾选
    status: completed
isProject: true
---

# 重页 UI 响应性 — Cursor 计划

> **已完成（HP-0～HP-3 代码）**  
> 设计：[docs/minimal-browser/heavy-page-ui-responsiveness-design.md](../../docs/minimal-browser/heavy-page-ui-responsiveness-design.md)  
> 开发计划：[docs/minimal-browser/heavy-page-ui-responsiveness-development-plan.md](../../docs/minimal-browser/heavy-page-ui-responsiveness-development-plan.md)

## 实现摘要

- `BrowserBackgroundMediaController`：失活 pause+mute；`BrowserTab.mediaHeavy`
- 切走：有媒体则跳过 `takeSnapshot`；无媒体则异步 capture
- `refreshTabsUI`：同步 detach/attach；chrome 次要项 `dispatch_async` + generation 校验
- 标签拖拽：10pt + 150ms
- 休眠：mediaHeavy 90s；预算优先杀重页
- `estimatedProgress` UI 合并（80ms / Δ0.02）
- **不做**默认独立 `WKProcessPool`
