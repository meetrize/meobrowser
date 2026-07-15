---
name: 登录表单内联助手
overview: 按 IF-0→IF-3 实现登录表单检测、密码框内联钥匙菜单、Recipe 一键/仅填入、系统密码桥、登录成功询问保存；复用 LoginAssist V1。
todos:
  - id: if-0-detector
    content: IF-0：LoginFormDetector UserScript + MutationObserver + 内联图标 + message
    status: completed
  - id: if-0-toolbar
    content: IF-0：formDetected 反哺工具栏点亮；inlineAssistEnabled Pref
    status: completed
  - id: if-1-menu-runner
    content: IF-1：内联 NSMenu + LoginRunner fillOnly + OTP 默认不提交
    status: completed
  - id: if-2-system-password
    content: IF-2：SystemPasswordBridge（AuthenticationServices）+ 双字段回填
    status: completed
  - id: if-3-save-prompt
    content: IF-3：maybeSuccess 询问保存/更新 + 设置开关 + 主动保存菜单项
    status: completed
  - id: if-3-build-docs
    content: IF-3：make browser；更新 design/dev-plan/acceptance/README
    status: completed
isProject: true
---

# 登录表单内联助手 — Cursor 自动开发计划

> **状态：已完成（2026-07-15）** · `make browser` 通过  
> **依据**：[login-form-inline-design.md](docs/minimal-browser/login-form-inline-design.md) · [login-form-inline-development-plan.md](docs/minimal-browser/login-form-inline-development-plan.md)

## 交付摘要

| 模块 | 文件 |
|------|------|
| 检测/图标 | `LoginFormDetector.*` |
| Prefs | `LoginAssistPreferences.*` |
| 系统密码 | `SystemPasswordBridge.*` |
| 保存询问 | `SaveRecipePromptCoordinator.*` |
| 编排 | `LoginAssistController.*`（message + 菜单） |
| Runner | `LoginRunner` 支持 `fillOnly` |

## 手测

见 acceptance「登录表单内联助手 V1.5」。测试页：`MeoBrowser.app/Contents/Resources/login-assist-test.html`。
