---
name: 登录助手 V1
overview: 按 LA-0→LA-3 实现站点登录助手 V1：Recipe+Keychain、一键填表提交、设置与点选拾取、可选自动登录；不做短信/二维码/Companion。
todos:
  - id: la-0-models
    content: LA-0：LoginRecipe/LoginStep 模型 + RecipeStore JSON + CredentialStore Keychain
    status: completed
  - id: la-0-makefile
    content: LA-0：Makefile 链入 LoginAssist 源文件与 -ILoginAssist、-framework Security
    status: completed
  - id: la-1-runner
    content: LA-1：LoginRunner（waitFor/fill/click/pressEnter/pauseMs）+ 测试 HTML
    status: completed
  - id: la-1-chrome
    content: LA-1：LoginAssistController + ActionGroup loginAssist 按钮 + ⌘⇧L
    status: completed
  - id: la-2-settings
    content: LA-2：登录助手设置窗（列表/编辑/删除/默认）+ 设置菜单入口
    status: completed
  - id: la-2-picker
    content: LA-2：从当前页点选拾取选择器（message handler + 高亮/Esc）
    status: completed
  - id: la-3-auto
    content: LA-3：自动登录、防抖、多 Recipe 菜单、失败跳转编辑
    status: completed
  - id: la-3-build-docs
    content: LA-3：make browser 通过；更新 design/dev-plan/acceptance 状态
    status: completed
isProject: true
---

# 登录助手 V1 — Cursor 自动开发计划

> **依据**：[auto-login-design.md](docs/minimal-browser/auto-login-design.md) · [auto-login-development-plan.md](docs/minimal-browser/auto-login-development-plan.md)  
> **范围**：仅 **LA-0～LA-3（V1 密码一键/自动）**；不做 TOTP / 短信 / 二维码 / Companion。  
> **状态**：**已完成（2026-07-15）** · `make browser` 通过。

## 交付摘要

| 模块 | 路径 |
|------|------|
| 数据层 | `SimpleBrowser/LoginAssist/LoginRecipe*` · `LoginCredentialStore*` · `LoginRecipeStore*` |
| 执行 | `LoginRunner*` · `LoginAssistController*` |
| 拾取 | `LoginElementPicker*` · `LoginAssistScriptMessageProxy*` |
| 设置 | `BrowserLoginAssistSettingsWindowController*` |
| 测试页 | `login-assist-test.html`（入 App Resources） |
| Chrome | ActionGroup `loginAssist` · 文件菜单 ⌘⇧L / 登录助手… |

## 手测

见 [acceptance.md](docs/minimal-browser/acceptance.md)「登录助手 V1」。测试账号：`demo` / `pass`；file 页 host 填 `file`。
