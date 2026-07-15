# 登录表单内联助手 — 开发计划

> 基于 [login-form-inline-design.md](login-form-inline-design.md) 的分阶段实施计划。  
> 前置：登录助手 V1（LA-0～LA-3）已完成。  
> **状态：IF-0～IF-3（V1.5）已完成（2026-07-15）。**  
> Cursor 计划：`.cursor/plans/login-form-inline.plan.md`

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 图标密度 | 默认每登录上下文 **一枚**（贴密码框右侧） |
| 内联菜单 | **NSMenu**（锚定点击处 / 鼠标位置） |
| 有 OTP | 默认 **仅填入**，不点提交 |
| 系统密码 | `ASAuthorizationPasswordProvider`；默认填入不提交 |
| 保存提示 | 默认开；确认后才写 Keychain；默不勾选自动登录 |
| 跨域 iframe | V1.5 **不做** |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase IF-0 | 检测与装饰 | **完成** | UserScript + 内联图标 + formDetected |
| Phase IF-1 | 菜单与 Recipe | **完成** | NSMenu + fillOnly/一键 + OTP |
| Phase IF-2 | 系统密码桥 | **完成** | AuthenticationServices 回填 |
| Phase IF-3 | 保存提示与开关 | **完成** | 成功启发式 + Prefs + 验收 |

---

## Phase IF-0：检测与装饰

**目标**：登录页密码框右侧出现钥匙按钮；Native 得知「本页有登录表单」。

### 任务清单

- [ ] **0.1** `LoginFormDetector`：嵌入式 JS（启发式 + MutationObserver 防抖）
- [ ] **0.2** `WKUserScript` document-end 注入；handler 名 `loginFormInline`
- [ ] **0.3** 密码框右侧注入 `#meo-login-assist-btn`；`padding-right` 让位
- [ ] **0.4** message：`formDetected` / `formCleared` / `iconClicked`（含选择器、hasOTP、formId）
- [ ] **0.5** `LoginAssistController`：`hasDetectedLoginForm` → 工具栏强调态（无 Recipe 也可点亮）
- [ ] **0.6** Pref：`inlineAssistEnabled`（默认 YES）；关则不注入
- [ ] **0.7** Makefile 链入新源文件（若拆文件）

### 完成标准

- 打开 `login-assist-test.html` 可见内联钥匙；控制台/Native 收到 formDetected。

---

## Phase IF-1：菜单与 Recipe

**目标**：点图标弹出菜单，可一键登录或仅填入匹配 Recipe。

### 任务清单

- [ ] **1.1** `LoginFormInlineController`（或并入 `LoginAssistController`）：`presentMenuForMessage:`
- [ ] **1.2** 菜单项：匹配 Recipe「一键登录」/「仅填入」；有 OTP 时主项为「填入帐密…」
- [ ] **1.3** `LoginRunner` 增加 `fillOnly:`；OTP 默认 fillOnly
- [ ] **1.4** 「管理登录配置…」
- [ ] **1.5** 无 Recipe 时工具栏单击 → 同菜单（含系统密码入口占位）
- [ ] **1.6** 填入成功短提示（OTP 场景说明手动登录）

### 完成标准

- 已有 Recipe 时点内联图标可登录测试页；OTP 模拟字段时不自动 submit。

---

## Phase IF-2：系统密码桥

**目标**：菜单「用系统密码填充…」经系统 UI 选密后双字段回填。

### 任务清单

- [ ] **2.1** `SystemPasswordBridge`：`ASAuthorizationPasswordProvider` + presentation anchor
- [ ] **2.2** 选中后 JS 填入当前 form 的 username/password 选择器（不提交）
- [ ] **2.3** 失败/取消/无可用性：诚实文案（ad-hoc 可能不可用）
- [ ] **2.4** Makefile：`-framework AuthenticationServices`
- [ ] **2.5** （可选）菜单「聚焦密码框」尝试唤起系统 AutoFill

### 完成标准

- 开发者签名环境下可选密回填；ad-hoc 下优雅降级不崩溃。

---

## Phase IF-3：保存提示

**目标**：手输登录成功后询问是否保存/更新 Recipe。

### 任务清单

- [ ] **3.1** JS：草稿标记（仅 hasUser/hasPass，明文仅在 maybeSuccess / 拉取时传）
- [ ] **3.2** `maybeSuccess` 启发式 + Native `SaveRecipePromptCoordinator`
- [ ] **3.3** Alert：保存 / 不保存 / 本站不再询问；同用户名则更新
- [ ] **3.4** Pref：`promptSaveOnSuccess`；host 抑制列表
- [ ] **3.5** 设置窗勾选「检测到登录表单时显示内联图标」「登录成功后询问保存」
- [ ] **3.6** 菜单「将当前输入保存为配置…」（主动保存）
- [ ] **3.7** `make browser`；更新 design / acceptance；本计划勾选

### 验收清单

- [ ] 测试页有内联图标且不严重挡字
- [ ] Recipe 一键 / 仅填入正确；OTP 不自动提交
- [ ] 系统密码路径不崩溃（能用则回填）
- [ ] 成功询问保存；取消不写库
- [ ] 关闭开关后无图标、无保存询问

---

## 建议实现文件

```text
SimpleBrowser/LoginAssist/
  LoginFormDetector.h/.m          # JS 源 + registerUserScript
  LoginFormInlineController.h/.m  # 菜单编排（可与 AssistController 合并，优先独立）
  SystemPasswordBridge.h/.m
  LoginAssistPreferences.h/.m
  SaveRecipePromptCoordinator.h/.m
  LoginRunner.*                   # fillOnly 扩展
  LoginAssistController.*         # 接线、工具栏态、message 分发
  BrowserLoginAssistSettings*.m   # 开关
```

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：IF-0～IF-3 任务拆分 |
| 0.2 | 2026-07-15 | IF-0～IF-3 实现完成 |
