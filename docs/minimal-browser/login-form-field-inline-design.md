# 登录表单逐字段「＋ / 填入」— 设计方案（V1.6）

> 目标：在登录上下文内，为帐号 / 密码 / 手机等字段提供互斥的「＋（保存）」与「填入」内联图标；支持单字段保存与「保存本表」。  
> 状态：**已实现（IF-D0～IF-D6）**  
> 拍板：覆盖登录相关字段（非全站任意表单）；默认存当前字段 + 「保存本表」批量。  
> 前置：V1.5 内联钥匙（[login-form-inline-design.md](login-form-inline-design.md)）  
> 开发计划：[login-form-field-inline-development-plan.md](login-form-field-inline-development-plan.md)

---

## 1. 定位

产品仍为 **登录助手**：启发式只识别登录表单；凭证仍存 Recipe + Keychain。  
默认密度改为 **每相关字段一枚图标**；可用偏好回退到 V1.5 单钥匙。

与站点备忘分工不变：登录上下文字段由本方案接管；备忘 `FormMemoInlineDetector` 继续让位。

## 2. 交互摘要

| 状态 | 图标 | 行为 |
|------|------|------|
| 该槽无非空预设 | ＋ | 确认后写入对应槽（帐密 phone → Keychain；extra → Recipe） |
| 该槽有非空预设 | 填入 | 只填该字段，不提交 |
| OTP | 仅填入（有 `otpSelector` 时） | 不提供 ＋；填入走 OTPInbox |
| 密码框旁 | 小号菜单钮 | 打开完整助手菜单（系统密码 / 一键登录等） |

「保存本表」：确认 sheet 第二按钮或菜单项；批量写入同上下文已填合格槽（跳过 OTP）。

## 3. 偏好

- `inlineAssistEnabled`：总开关（已有）
- `loginFieldInlineMode`：`perField`（默认）/ `legacySingleKey`
- `loginExtraFieldInlineEnabled`：登录表额外文本框图标（默认关）

## 4. 架构

`LoginFormDetector`（JS）↔ `loginFormInline` 消息 ↔ `LoginAssistController`  
保存：`LoginFieldSaveCoordinator`  
填入：`LoginRunner` 单选择器 API + Keychain / OTPInbox  
Native 经 `__meoLoginAssistSetFieldTargets` 下发 `{slot,selector,hasPreset,label,allowSave}`。

## 5. 明确不做

全站任意表单常驻图标；静默进页灌入；OTP 写入 Keychain；跨域 iframe。
