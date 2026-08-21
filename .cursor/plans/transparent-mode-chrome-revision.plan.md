---
name: 透明模式保留标签栏
overview: 按 TC-0→TC-2 修订透明模式壳显隐：保留标签条与交通灯；地址栏跟随精简模式；透明态可切精简与 Peek。
todos:
  - id: tc-0-enter
    content: TC-0：enter 不卸标签条、显示交通灯；去掉 toolbar 强制隐藏；走精简显隐
    status: completed
  - id: tc-1-compact-peek
    content: TC-1：透明态精简联动；允许 Peek
    status: completed
  - id: tc-2-exit-docs
    content: TC-2：退出路径清理、手测、文档交叉更新
    status: completed
isProject: true
---

# 透明模式 Chrome 修订 — Cursor 计划

> **依据**：[transparent-mode-chrome-revision-design.md](docs/minimal-browser/transparent-mode-chrome-revision-design.md) · [transparent-mode-chrome-revision-development-plan.md](docs/minimal-browser/transparent-mode-chrome-revision-development-plan.md)  
> **范围**：**TC-0～TC-2** · **已完成**

## 实现摘要

- `enterTransparentModeChrome`：保留 accessory；交通灯显示；按精简布局 toolbar/◀▶  
- `applyToolbarVisibilityForCompactState`：不再因透明强制藏栏  
- `beginAddressBarPeek` / `focusAddressBar`：透明态可用  
- 删除 `transparentModeAccessoryRemoved`  
