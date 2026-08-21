---
name: 透明模式自动藏壳
overview: 按 TH-0→TH-2：透明模式下鼠标移出窗 frame 自动隐藏标签条（及交通灯）；地址栏精简始终藏、非精简随指针显隐；Peek 例外。
todos:
  - id: th-0-monitor
    content: TH-0：指针监视 + applyChromeVisibility 统一入口；进出透明启停
    status: completed
  - id: th-1-hide
    content: TH-1：藏条/灯/栏 + 移出延迟；四格矩阵手测
    status: completed
  - id: th-2-peek-docs
    content: TH-2：Peek 优先、精简联动、文档验收
    status: completed
isProject: true
---

# 透明模式自动藏壳 — Cursor 计划

> **已完成（TH-0～TH-2）**

## 实现摘要

- `BrowserTransparentChromeAutoHideController`：全局+本地监视；移出 100ms 延迟；移入立即  
- `applyChromeVisibilityForCurrentMode`：条/灯/栏统一公式  
- Peek 强制显地址栏；精简永不因移入显栏  
