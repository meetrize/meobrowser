# 助手侧栏「显示表单按钮」— 设计方案

> 目标：在打开助手侧栏时，用户可一键开关网页表单旁的本插件内联图标；默认开启，关闭后表单右侧不再出现相关按钮。  
> 状态：**已实现**  
> 前置：助手侧栏 SB-0～SB-3 已落地；登录内联 / 站点备忘内联已落地。  
> 关联：[assist-sidebar-design.md](assist-sidebar-design.md) · [login-form-field-inline-design.md](login-form-field-inline-design.md) · [site-form-memo-design.md](site-form-memo-design.md) · [assist-sidebar-form-buttons-toggle-development-plan.md](assist-sidebar-form-buttons-toggle-development-plan.md)

---

## 0. 一句话结论

| 项 | 结论 |
|----|------|
| 放哪里 | 助手侧栏底部 footer，与「高级设置…」同排（或上一行） |
| 控件 | 勾选框：**显示表单按钮**，默认勾选 |
| 关了会怎样 | 当前页（及已打开标签）立刻去掉表单旁所有 Meo 内联图标；新标签也不再注入显示 |
| 偏好 | **复用**现有全局偏好，不新增第三套存储；侧栏做快捷入口 |
| 与高级设置 | 双向同步；侧栏是「总开关」语义，高级设置保留细粒度项 |

---

## 1. 问题与动机

### 1.1 现状

网页表单旁的图标由两套 `WKUserScript` 注入：

| 系统 | 典型 DOM | 偏好键 | 默认 |
|------|----------|--------|------|
| 登录助手 | `meo-login-field-btn` / `meo-login-menu-btn` / 钥匙 / 跨帧徽标 | `LoginAssistInlineAssistEnabled` | YES |
| 站点备忘 | `#meo-form-memo-save-btn` / `.meo-form-memo-fill-btn` | `FormMemoInlineSaveEnabled` | YES |

这些开关今天只在 **「登录助手与互联（高级）」** 窗口里，且标注「新标签生效」。用户在侧栏管配置时，无法顺手关掉「网页上的插件图标」，发现成本高。

### 1.2 要解决的痛点

| 场景 | 痛点 |
|------|------|
| 演示 / 录屏 / 截图 | 表单旁 `+` / `⋯` / `↓` 干扰画面 |
| 某些站点布局紧 | 图标遮挡或挤占输入框右侧 |
| 临时只要菜单/快捷键填入 | 不需要常驻内联入口，但侧栏与 ⌘⇧L / ⌘⇧M 仍要可用 |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 侧栏增加「显示表单按钮」勾选，默认开 | 改成按站点开关（可列为后续） |
| 关闭后隐藏登录 + 备忘两套页内图标 | 关闭一键登录 / 侧栏 CRUD / 自动登录本身 |
| **当前标签立即生效**（不要求新开标签） | 在侧栏塞入全部高级细项（逐字段模式、额外字段等） |
| 与高级设置对应勾选双向同步 | 另起 UserDefaults 键造成三态不一致 |
| 风险域名仍按既有 policy 抑制 | 改 PagePack 或其它侧栏 |

---

## 2. 产品定义

### 2.1 文案与默认

| 项 | 值 |
|----|-----|
| 标题 | **显示表单按钮** |
| 控件 | `NSButton` checkbox |
| 默认 | **选中**（与现有 `inlineAssistEnabled` / `inlineSaveEnabled` 默认 YES 一致） |
| Tooltip（建议） | 关闭后，网页输入框右侧不再显示登录助手与站点备忘图标；侧栏与快捷键仍可用。 |

### 2.2 语义（总开关）

侧栏勾选表示：**是否在网页表单旁显示本插件图标**。

| 侧栏状态 | 登录内联图标 | 备忘内联图标 | 侧栏 / ⌘⇧L / ⌘⇧M / 自动登录 |
|----------|--------------|--------------|------------------------------|
| 勾选 | 按高级设置细项正常显示 | 按 `inlineSaveEnabled` | 不受影响 |
| 取消勾选 | **全部隐藏** | **全部隐藏** | **不受影响** |

说明：取消勾选时，用户仍可通过助手侧栏「执行」、文件菜单、快捷键完成填入/登录；只是去掉页内入口。

### 2.3 与高级设置的映射

采用 **「侧栏总开关 = 两套内联显示同时开/关」**，避免用户理解成「只关登录、备忘还在」：

| 用户操作 | 写入 |
|----------|------|
| 侧栏勾选 → 开 | `LoginAssistPreferences.inlineAssistEnabled = YES` **且** `FormMemoPreferences.inlineSaveEnabled = YES` |
| 侧栏勾选 → 关 | 两者均为 `NO` |
| 高级设置改「检测到登录表单时显示内联图标」 | 同步刷新侧栏勾选状态（见下） |
| 高级设置改「输入时显示保存到站点备忘」 | 同上 |

**侧栏勾选态计算：**

```text
sidebarChecked = inlineAssistEnabled || inlineSaveEnabled
```

- 两者皆关 → 侧栏未勾选  
- 任一开 → 侧栏勾选（表示「当前仍会显示至少一类表单按钮」）  
- 用户从侧栏**主动勾上**：强制两者都开（恢复「表单按钮完整可用」）  
- 用户从侧栏**主动取消**：强制两者都关  

高级设置里仍可单独只开登录、关备忘；此时侧栏保持勾选（因为登录图标仍在）。若产品后续希望侧栏变成三态（mixed），可在实现阶段用 `allowsMixedState`；**V1 不强制三态**，用上表布尔语义即可。

### 2.4 布局位置

在现有 footer 扩展（窄栏友好）：

```text
┌──────────────────────────────┐
│ … 列表 / 详情 …              │
├──────────────────────────────┤
│ ☑ 显示表单按钮               │  ← 新
│ [高级设置…]                  │
└──────────────────────────────┘
```

或同一 `NSStackView` 竖排：先 checkbox，再「高级设置…」。不放进标题栏，避免与「＋登录 / ＋备忘 / ✕」抢横向空间。

---

## 3. 技术设计

### 3.1 架构（不变分层）

```text
AssistSidebarController
  └─ checkbox → LoginAssistPreferences / FormMemoPreferences
                    │ post DidChangeNotification
                    ▼
              LoginAssistController
                    │ evaluateJavaScript 即时显隐
                    ▼
         LoginFormDetector / FormMemoInlineDetector
         （页面内 __meo*Enabled 标志 + 移除已有按钮）
```

偏好层、Store、Runner **不改职责**；只补「侧栏入口 + 即时推送」。

### 3.2 即时生效（相对现状的关键升级）

现状：标志在 `configureWebViewConfiguration` 时写入 UserScript，注释为「新标签生效」；`loginAssistPreferencesDidChange:` 目前只 `pushFieldAssistTargetsToActiveWebView`，**不会**拆掉已存在的 DOM 按钮。

本需求要求取消勾选后**立刻**看不到图标，因此增加统一推送：

| API（建议名） | 行为 |
|---------------|------|
| `-[LoginAssistController applyInlineChromeVisibilityToActiveWebView]` | 对当前窗口活跃（建议：该窗口所有）WKWebView 执行 JS |
| 登录侧 JS | `window.__meoLoginInlineEnabled = <bool>`；若 false，调用已有 teardown（移除 `.meo-login-*` 按钮、清 observer 装饰）；若 true，触发一次 rescan |
| 备忘侧 JS | 同步 `__meoFormMemoInlineSaveEnabled`（或现有等价标志）；false 时移除 save/fill 按钮 |

实现要点：

1. 在 `LoginFormDetector` / `FormMemoInlineDetector` 的嵌入 JS 中暴露稳定函数，例如：
   - `window.__meoLoginAssistSetInlineEnabled(bool)`
   - `window.__meoFormMemoSetInlineSaveEnabled(bool)`
2. 函数内既改标志，也处理 DOM（hide/remove + 必要时 re-run detect）。
3. `LoginAssistController` 在两个 `*PreferencesDidChangeNotification` 回调里调用上述推送（不仅新建标签）。
4. 配置期注入的初始值仍从 Preferences 读取，保证冷启动一致。

### 3.3 多标签

| 策略 | 说明 |
|------|------|
| **推荐** | 偏好变更时，对**当前 BrowserWindow** 内所有 WebView 推送（与「全局偏好」语义一致） |
| 可接受降级 | 仅活跃 WebView；其它标签在下次导航 / 聚焦时补推 |

V1 推荐窗口内全推，避免「这个标签关了、隔壁标签还在」的困惑。

### 3.4 风险域名与其它门闩

`BrowserRiskHostPolicy` 抑制逻辑保持不变：总开关为开时，风险站仍可不显示。总开关为关时，所有站都不显示——无需额外分支。

### 3.5 高级设置文案微调（可选）

将「（新标签生效）」改为「（立即生效）」或去掉该后缀，避免与真实行为不符。侧栏与设置窗勾选状态在窗口 `windowDidBecomeKey` / 打开时刷新，并监听 `*DidChangeNotification`。

---

## 4. UX 细节

| 项 | 行为 |
|----|------|
| 打开侧栏 | checkbox 反映当前偏好（按 §2.3） |
| 切换勾选 | 立即写 Preferences → 通知 → 推 JS；无需点「保存」 |
| 关图标后执行 | 列表「执行」、快捷键、自动登录照常 |
| 空态 / 过滤 | 与勾选无关；不隐藏新建按钮 |
| 无障碍 | checkbox 有 title；可加 `toolTip` |

---

## 5. 测试要点

| # | 场景 | 期望 |
|---|------|------|
| T1 | 默认新装 / 清偏好 | 侧栏勾选；测试页有登录/备忘图标 |
| T2 | 侧栏取消勾选 | 当前页图标立即消失 |
| T3 | 再勾选 | 图标在仍聚焦/仍匹配的表单上恢复（或短延迟后出现） |
| T4 | 关图标后 ⌘⇧L / 侧栏执行 | 仍可填入/登录 |
| T5 | 高级设置关登录内联、开备忘 | 侧栏仍勾选；页上仅备忘类图标 |
| T6 | 侧栏再取消 | 两类图标都消失；高级设置两勾选均为关 |
| T7 | 多标签同窗 | 切换后各标签图标状态与偏好一致 |
| T8 | 风险域名 | 行为与现网 policy 一致，不因本功能放宽 |

测试页：`login-assist-test.html`、`form-memo-test.html`。

---

## 6. 风险与后续

| 风险 | 缓解 |
|------|------|
| 只关登录、用户以为「表单按钮」全关但备忘还在 | 侧栏关 = 双关；文案写清「登录助手与站点备忘」 |
| JS teardown 不完整导致残影 | 按 class/id 统一 query + remove；rescan 防抖 |
| 与「新标签生效」旧注释/文档不一致 | 同步改高级设置文案与相关 design 文档一句 |

**后续可选**：按 host 禁用内联、侧栏 mixed 三态、仅隐藏登录保留备忘的独立侧栏项。

---

## 7. 文档与实现入口

| 文件 | 角色 |
|------|------|
| `AssistSidebarController.m` | footer checkbox UI + action |
| `LoginAssistPreferences` / `FormMemoPreferences` | 已有 API，直接写 |
| `LoginAssistController.m` | 偏好变更 → 即时 `evaluateJavaScript` |
| `LoginFormDetector.m` / `FormMemoInlineDetector.m` | 暴露 setEnabled + DOM teardown/rescan |
| `BrowserLoginAssistSettingsWindowController.m` | 文案「立即生效」；可选监听刷新 |

不新增 Store；不改 Recipe/Memo JSON schema。
