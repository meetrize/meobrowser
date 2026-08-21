---
name: 输入框文字垂直边距
overview: 在不改输入框高度的前提下，于 SBKit 默认开启紧凑垂直文字 inset，并让 SBSecureTextField 对齐，消除地址栏/新标签页/设置等处文字底切。
todos:
  - id: vi-0-default
    content: VI-0：SBTextField 默认紧凑垂直 inset + 常量收敛
    status: completed
  - id: vi-1-secure
    content: VI-1：SBSecureTextField 自定义 cell 与默认紧凑对齐
    status: completed
  - id: vi-2-docs
    content: VI-2：删除冗余赋值并更新 text-input / cursor 规则
    status: completed
  - id: vi-3-qa
    content: VI-3：全场景目视验收；必要时垂直 inset 2→1
    status: completed
isProject: true
---

# 单行输入框文字垂直边距 — Cursor 计划

> **已完成（VI-0～VI-3）**  
> 设计：[docs/sbkit/text-field-vertical-insets-design.md](../../docs/sbkit/text-field-vertical-insets-design.md)

## 实现摘要

- `SBTextFieldLayout`：紧凑 inset 常量（H3 / V2）+ `SBTextFieldApplyCompactInsets`
- `configureSingleLineTextField:` / Secure 默认 `usesCompactVerticalTextInsets = YES`
- `SBSecureTextField`：`SBStandardSecureTextFieldCell` 对齐 drawing/edit/select
- 删除 Find / History / 通知 / 聊天处冗余 `= YES`
