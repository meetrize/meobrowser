# 助手侧栏「显示表单按钮」— 开发计划

> 基于 [assist-sidebar-form-buttons-toggle-design.md](assist-sidebar-form-buttons-toggle-design.md)。  
> 状态：**已实现**（FB-0～FB-3）  
> 预估：约 **1～1.5 人日**（含即时显隐与双端同步验收）

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 入口 | 助手侧栏 footer：**显示表单按钮** checkbox |
| 默认 | 勾选（YES） |
| 关闭效果 | 登录内联 + 备忘内联图标全部不显示；填入/登录能力保留 |
| 偏好 | 关：`inlineAssistEnabled=NO` 且 `inlineSaveEnabled=NO`；开：两者皆 YES |
| 侧栏勾选态 | `inlineAssistEnabled \|\| inlineSaveEnabled` |
| 生效时机 | **立即**（当前窗口 WebView 推 JS），不只新标签 |
| 高级设置 | 保留细项；与侧栏双向同步；文案去掉「仅新标签」误导 |

---

## 总览

| 阶段 | 名称 | 产出 |
|------|------|------|
| Phase FB-0 | 页面即时显隐 API | Detector JS 可开关并清理/重建 DOM |
| Phase FB-1 | Native 推送与偏好联动 | Controller 监听通知后全窗口推送 |
| Phase FB-2 | 侧栏 UI | footer checkbox + 读写偏好 |
| Phase FB-3 | 高级设置对齐与验收 | 文案、同步刷新、测试清单打勾 |

建议顺序：**FB-0 → FB-1 → FB-2 → FB-3**（先能用 JS 控显隐，再挂 UI）。

---

## Phase FB-0：页面即时显隐 API

**目标**：不重建 WebView，也能打开/关掉两类表单旁图标。

### 任务清单

- [ ] **0.1** `LoginFormDetector.m` 嵌入 JS：增加 `window.__meoLoginAssistSetInlineEnabled(enabled)`
  - 写 `window.__meoLoginInlineEnabled`
  - `enabled === false`：移除所有 `meo-login-*` 相关按钮，停止/跳过本轮装饰
  - `enabled === true`：触发与现有 detect 同等的一次扫描（复用已有 debounce 入口）
- [ ] **0.2** `FormMemoInlineDetector.m`：对称实现 `window.__meoFormMemoSetInlineSaveEnabled(enabled)`（函数名可按现有全局标志命名习惯微调，但须稳定可被 Native 调用）
  - 关：移除 `#meo-form-memo-save-btn`、`.meo-form-memo-fill-btn`
  - 开：按现有逻辑允许 save/fill 再出现（fill 仍依赖 Native push targets）
- [ ] **0.3** 确认配置期注入的初始 `__meo*Enabled` 仍读 Preferences（冷启动正确）
- [ ] **0.4** 风险 host 分支：在 setEnabled(true) 的 rescan 路径上继续走现有 suppress，不绕过 policy

### 完成标准

- 在测试页 DevTools / Native `evaluateJavaScript` 手动调 `SetInlineEnabled(false)` 后图标消失；`true` 后可恢复。

---

## Phase FB-1：Native 推送与偏好联动

**目标**：Preferences 一变，当前窗口页面立刻跟手。

### 任务清单

- [ ] **1.1** `LoginAssistController` 新增方法，例如：
  - `-applyInlineChromeVisibilityToWebViewsInWindow:` 或作用于 `activeBrowserWindow` 内全部 tab
- [ ] **1.2** 实现内容：
  - 读 `LoginAssistPreferences.inlineAssistEnabled` / `FormMemoPreferences.inlineSaveEnabled`
  - 对每个 WKWebView `evaluateJavaScript` 调用 FB-0 暴露的函数
  - 若登录内联为开：在成功回调后继续 `pushFieldAssistTargetsToActiveWebView`（或 per-webView 等价），保证 fill 态正确
  - 若备忘为开：同样补推 memo fill targets（走现有 push 路径）
- [ ] **1.3** 改 `loginAssistPreferencesDidChange:`：调用 1.1（保留或合并原 `pushFieldAssistTargets…`）
- [ ] **1.4** 改 `formMemoPreferencesDidChange:`：同样调用 1.1（今日为空实现，须补上）
- [ ] **1.5** 导航完成 / URL 变化等现有刷新点：若总开关为关，确保不会再次画出图标（依赖页面标志即可；抽查即可）

### 完成标准

- 仅改 Preferences（临时用高级设置勾选）即可让**当前标签**图标显隐，无需新开标签。

---

## Phase FB-2：侧栏 UI

**目标**：打开助手侧栏即可看到并操作系统级「显示表单按钮」。

### 任务清单

- [ ] **2.1** `AssistSidebarController`：footer 增加 `NSButton` checkbox，标题 **显示表单按钮**
- [ ] **2.2** Auto Layout：竖向 stack 于「高级设置…」之上（或同 footer 内先 checkbox 后按钮）；窄宽 320 不裁切
- [ ] **2.3** `-reloadFormButtonsCheckbox`：按 `inlineAssistEnabled \|\| inlineSaveEnabled` 设 state
- [ ] **2.4** action：  
  - On → `setInlineAssistEnabled:YES` + `setInlineSaveEnabled:YES`  
  - Off → 两者 `NO`  
  - 依赖 Preferences 内已有 `DidChangeNotification`，不要在侧栏里直接操 WebView（保持单通道）
- [ ] **2.5** 打开侧栏 / 收到两个 DidChange 通知时刷新 checkbox（避免高级设置改完侧栏状态旧）
- [ ] **2.6** `toolTip`：说明关闭后页内无图标，侧栏与快捷键仍可用
- [ ] **2.7** 遵守 SBKit：本控件为 checkbox，**无新文本输入框**；若有说明文案用 `NSTextField` label 即可（非输入）

### 完成标准

- 侧栏取消勾选 → 当前页图标立刻无；再勾选 → 恢复；高级设置与侧栏状态一致。

---

## Phase FB-3：高级设置对齐与验收

### 任务清单

- [ ] **3.1** `BrowserLoginAssistSettingsWindowController`：登录内联 / 备忘内联相关标题去掉或改写「新标签生效」→「立即生效」
- [ ] **3.2** 设置窗在显示时 / 收到通知时刷新对应 checkbox（若尚无监听则补上，防止侧栏改完设置窗仍显示旧值）
- [ ] **3.3** 按设计文档 §5 跑 T1～T8；记录于本文件下方验收表
- [ ] **3.4** 若有 `assist-sidebar-design.md`「做什么」列表，补一句：侧栏可关页内表单按钮（全局）

### 验收表

| # | 场景 | 结果 |
|---|------|------|
| T1 | 默认勾选 + 测试页有图标 | ☐ |
| T2 | 侧栏取消 → 图标立即消失 | ☐ |
| T3 | 再勾选 → 图标恢复 | ☐ |
| T4 | 关图标后侧栏执行 / ⌘⇧L / ⌘⇧M | ☐ |
| T5 | 高级设置只开一类 → 侧栏仍勾选 | ☐ |
| T6 | 侧栏关闭 → 高级设置两类均关 | ☐ |
| T7 | 同窗多标签状态一致 | ☐ |
| T8 | 风险域名不放宽 | ☐ |

### 完成标准

- 验收表全过；无新增偏好键；无 Recipe/Memo schema 变更。

---

## 非目标（本迭代不做）

- 按网站禁用内联图标  
- 侧栏 checkbox 三态（mixed）UI  
- 关闭自动登录 / 保存成功提示（仍归高级设置）  
- PagePack、通知侧栏改动  

---

## 实现时注意

1. **单通道写偏好**：UI → Preferences → Notification → Controller → JS；侧栏不要直接 `evaluateJavaScript`。  
2. **双 Detector 都要关**：只关登录会导致「备忘 ↓ / ＋」仍在，不符合「表单右侧不出现本插件图标」。  
3. **fill targets**：重新打开内联后必须再 push，否则可能只有空壳 `+` 而无填入态。  
4. **提交信息**（若单独提交）：按仓库规范用简体中文，例如 `feat: 助手侧栏支持开关网页表单内联按钮`。
