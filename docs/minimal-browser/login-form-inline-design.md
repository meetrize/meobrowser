# 登录表单内联助手 — 设计方案（V1.5）

> 目标：在检测到登录表单时，于帐号/邮箱/密码框内侧提供统一入口，打通 **系统「密码」自动填充**、**登录助手 Recipe**、以及 **登录成功后保存 Recipe** 三条路径。  
> 状态：**V1.5 已实现**（IF-0～IF-3 · 2026-07-15）  
> 前置：登录助手 V1 已落地（[auto-login-design.md](auto-login-design.md) · [auto-login-development-plan.md](auto-login-development-plan.md)）  
> 开发计划：[login-form-inline-development-plan.md](login-form-inline-development-plan.md) · Cursor：`.cursor/plans/login-form-inline.plan.md`  
> 关联：`SimpleBrowser/LoginAssist/*` · `MeoBrowser.entitlements`

---

## 1. 方案定位

### 1.1 相对 V1 的升维

| | V1（已有） | V1.5（本方案） |
|--|-----------|----------------|
| 入口 | 工具栏钥匙 + 设置窗 | **表单字段内联图标**（检测登录表单后出现） |
| 凭证来源 | 仅 Meo Recipe / Keychain | Recipe **+** 系统 Passwords（能调则调） |
| 配置方式 | 手动建 Recipe / 点选拾取 | 登录成功后**建议保存**为 Recipe |
| 提交策略 | 默认填完并提交 | 区分「填入」「填入并登录」；有验证码则只填不提交 |

产品仍叫 **登录助手**，不演化成通用密码管理器：启发式只用于「识别登录表单并露出入口」，正式凭证仍以 Recipe 或系统密码库为准。

### 1.2 用户故事（验收导向）

1. 打开某站登录页 → 用户名/密码框右侧出现钥匙图标。  
2. 点图标 → 菜单：**用系统密码填充…** / **用登录助手：xxx** / **保存当前为配置…**（条件显示）。  
3. 选系统密码中匹配本域的一项 → 用户名+密码同时写入（不强制提交）。  
4. 选某个 Recipe → 一键填入；若判定存在验证码字段则**不点登录**，提示「请完成验证后手动登录」。  
5. 用户手输帐密并成功进入站内 → 弹原生提示「是否保存为登录助手配置？」确认后写入 Recipe + Keychain。

---

## 2. 可行性与边界（务必先读）

### 2.1 系统「密码」自动填充 — 分层现实

MeoBrowser 已声明受限 entitlement `com.apple.developer.web-browser`（见 `MeoBrowser.entitlements`），**本地 ad-hoc 签名下该能力通常不会真正生效**；正式分发需 Apple 审批与带 entitlement 的描述文件。

| 路径 | 能力 | 可行性 | 说明 |
|------|------|--------|------|
| **A. 系统字段级 AutoFill** | 焦点落在 `autocomplete=username/password` 时弹出系统建议 | **依赖 entitlement** | 与 Safari 同机制；图标侧可「聚焦字段」间接唤起 |
| **B. `ASAuthorizationPasswordProvider`** | App 主动弹出系统凭证选择器，选后回填 Web 表单 | **中高**（需开发者签名；与 A 可并存） | 最适合「图标点一下 → 选密码」 |
| **C. 静默读 iCloud「密码」库** | 无 UI 直接取密文 | **基本不可行 / 不做** | 无关联域名白名单时系统不放行；安全与审核也不允许 |

**定稿策略：A 尽量启用 + B 作为显式「用系统密码填充」主路径；永不做 C。**

无有效 browser entitlement 时：菜单项文案降级为「系统密码填充（需正式签名启用）」或隐藏，并保证 Recipe 路径仍可用。

### 2.2 表单内嵌 UI — 可行且可控

通过 `WKUserScript`（document-end）+ `MutationObserver` 检测表单，在字段右侧注入按钮（`position:absolute` / 包裹层），再经已有 `WKScriptMessageHandler` 回传 Native。与现有「点选拾取」同一通道族。

风险：站点 CSP、Shadow DOM、跨域 iframe、强样式覆盖。应对：尽力注入；失败则仅依赖工具栏入口（V1 保底）。

### 2.3 「登录成功」判定 — 启发式，可错但要可关

无法 100% 知道业务是否登录成功。采用多重弱信号 + 用户确认框，**禁止静默写入密钥**。

---

## 3. 交互设计

### 3.1 登录表单判定（启发式）

同一「登录上下文」（优先同一 `<form>`，否则同一可视容器）同时满足：

1. **至少一个密钥类字段**：`input[type=password]`，或 `autocomplete` 含 `current-password` / `new-password`。  
2. **至少一个帐号类字段**（在密钥字段之前或同容器）：  
   - `type=email` / `type=tel` / `type=text` / 无 type 的 text；且  
   - `autocomplete` ∈ `username` / `email` / `tel` / `nickname` 等，**或**  
   - `name`/`id`/`placeholder`/`aria-label` 匹配正则：`(user|login|account|email|mail|手机|帐号|账号|邮箱|phone)`（大小写不敏感）。  
3. **排除**：注册向倾向（同时出现两个 password 且 autocomplete 含 `new-password`）；搜索框（`type=search`）；明显非登录（仅 card number 等）。

命中后对该上下文挂接 **一个** 内联控件组（见下），避免每个字段各塞一个大红图标。

### 3.2 内联图标布局（建议修订原设想）

原设想「每个帐号/密码/email 框右侧都有图标」在多字段、窄宽度、双列布局上易打架。

**推荐定稿：**

| 原则 | 说明 |
|------|------|
| **每登录上下文一枚主图标** | 默认贴在 **password 字段右侧内缘**（最能代表「登录助手」） |
| 帐号字段聚焦时 | 主图标可临时跟随焦点字段（可选），或帐号框显示更淡的次要指示点 |
| 尺寸 | ~18×18 pt 等价 CSS px；`padding-right` 给输入框让出空间，避免挡字 |
| 样式 | 使用与工具栏一致的钥匙语义；浅/深色用 `color-scheme` / CSS 变量；不抢站点品牌色 |
| 无障碍 | `aria-label="登录助手"`；键盘可聚焦打开菜单 |

若用户强烈要求「每框都有」，可做成设置项「图标密度：精简 / 每个相关字段」，默认精简。

### 3.3 点击菜单（Popover / NSMenu）

由页面按钮 `postMessage` → Native 在按钮屏幕坐标锚定弹出（优先 **AppKit `NSMenu`/`NSPopover`**，避免网页内再画一层菜单不好做系统密码）。

```
┌ 登录助手 ─────────────────┐
│ 用系统密码填充…            │  ← 路径 B；列表空则灰色 + 说明
│ ───────────────────────── │
│ 一键登录 · 工作账号        │  ← 匹配当前 origin 的 Recipe（可多项）
│ 一键登录 · 个人账号        │
│ 仅填入 · 工作账号          │  ← 有验证码或用户偏好时
│ ───────────────────────── │
│ 将当前输入保存为配置…      │  ← 字段非空时可用
│ 管理登录配置…              │
└───────────────────────────┘
```

**有验证码 / OTP 时的行为（相对原设想 2 的完善）：**

- 检测同上下文是否存在 `autocomplete=one-time-code`、或 name/placeholder 含 `otp|code|验证码|校验码` 的可见输入框。  
- 若有：**默认走「仅填入」**（写帐密，不点提交）；菜单主项标题改为「填入帐密（请手动完成验证后登录）」。  
- 用户仍可长按 / 次级项选「强制一键登录」（高级，默认不展示，防误触）。

### 3.4 保存 Recipe 提示（原设想 3）

#### 触发条件（需同时满足）

1. 用户曾在本页登录上下文的帐号+密码字段输入过非空值（监听 `input`/`change`，值只在页面会话内存，提交前不落盘）。  
2. 随后发生「疑似成功」之一：  
   - 主文档导航离开登录 URL（host 同、path 不再像 login，或 query 登录参数消失）；或  
   - password 字段从 DOM 移除且出现登录后特征（弱）；或  
   - 同源下 `submit` 后短时间内 URL 变化。  
3. 当前 origin **尚无完全相同选择器+用户名** 的 Recipe；若已有同用户名 → 改为「是否更新已有配置？」。  
4. 设置中「登录成功后询问保存」默认 **开**。

#### 提示 UI

原生 `NSAlert` / 薄 sheet：

- 标题：保存登录助手配置？  
- 正文：站点 host、用户名（密码不回显）、自动生成的选择器摘要。  
- 按钮：保存 / 不保存 / 不再询问此站点。  

保存动作：复用 V1 `LoginRecipeStore` + `LoginCredentialStore`；选择器用检测阶段已解析的稳定 CSS（同拾取逻辑）。提交方式默认「点击检测到的 submit」或「密码框回车」。

**绝不**在未确认时写 Keychain。

---

## 4. 架构

```
WKUserScript (LoginFormDetector.js)
  detect → decorate → observe
        │ postMessage: formDetected / iconClicked / credentialsTyped / maybeSuccess
        ▼
LoginAssistScriptMessageProxy（已有弱代理模式）
        ▼
LoginFormInlineController  ←── 新
  ├─ 同步检测结果 → 工具栏按钮也可点亮（即使尚无 Recipe）
  ├─ presentMenu(anchor)
  ├─ SystemPasswordBridge (ASAuthorizationPasswordProvider)
  ├─ LoginRunner（fillOnly / fillAndSubmit）
  └─ SaveRecipePromptCoordinator
        ▼
LoginRecipeStore / LoginCredentialStore（V1）
```

| 新增/扩展 | 职责 |
|-----------|------|
| `LoginFormDetector`（JS + 薄 ObjC 壳） | 启发式、注入图标、事件上报 |
| `LoginFormInlineController` | 菜单、与 Runner/系统密码桥接 |
| `SystemPasswordBridge` | `ASAuthorizationPasswordProvider` 选密 → 回填 |
| `LoginRunner` 扩展 | `fillOnly` 模式；OTP 感知时强制 fillOnly |
| `SaveRecipePromptCoordinator` | 成功启发式 + 确认框 + 写库 |

工具栏 V1 按钮：**有 Recipe 或有检测到登录表单** 均可点亮；无 Recipe 时点工具栏直接打开「系统密码 / 保存 / 管理」。

---

## 5. 系统密码回填细节

1. 用户点「用系统密码填充…」。  
2. Native 启动 `ASAuthorizationController` + `ASAuthorizationPasswordProvider`。  
3. 用户选择一条凭证 → 拿到 `user` / `password`（经系统 UI 授权）。  
4. 向当前检测上下文注入：帐号字段 ← user，密码字段 ← password（派发 `input`/`change`，与 V1 Runner 一致）。  
5. **默认不提交**，让用户核一眼再登录（避免填错号直接冲进去）；菜单可提供「填充并提交」。

与 web-browser entitlement 的关系：

- Entitlement 生效时，用户也可直接点击网页字段使用系统建议条；内联图标仍提供「显式、可发现」入口。  
- Entitlement 未生效时，路径 B 仍可能在开发者签名下部分可用，需真机验证；文档与空态要诚实。

---

## 6. 隐私与安全

1. Detector 日志禁止打印密码明文；调试仅 `hasPassword=YES`。  
2. 页面会话中的「待保存草稿」仅存内存，关标签即丢。  
3. 系统密码只经 AuthenticationServices，不自建爬 Keychain 网络密码库。  
4. 保存提示可按站点压制；全局可关。  
5. 内联脚本不读取非登录表单（支付卡、搜索）——用启发式排除 + 可选「不在此站显示图标」。

---

## 7. 相对原设想的建议修订（摘要）

| # | 原设想 | 建议 | 理由 |
|---|--------|------|------|
| 1 | 每个帐号/密码/email 框都有图标 | **每表单一主图标**（密码框），密度可设 | 少挡字、少裂布局 |
| 2 | 一键调出系统 Passwords 并多字段填充 | **ASAuthorization 选条回填**；真 AutoFill 靠 entitlement | 合规且可实现 |
| 3 | Recipe 有验证码仍想登录 | **默认只填不提交** | 验证码无法可靠自动过 |
| 4 | 登录成功自动提示保存 | **确认框 + 可关 + 同账号改更新** | 防误存、防重复 |
| 5 | — | 增加「仅填入」与「填入并登录」分项 | 覆盖内网 / 双因素站 |
| 6 | — | 检测结果反哺工具栏点亮 | 无 Recipe 时仍有入口 |
| 7 | — | SPA：`MutationObserver` 持续扫描，防抖 200–300ms | React/Vue 登录页晚渲染 |
| 8 | — | iframe 内登录：V1.5 只做 **同站同源 frame**；跨域 iframe 标明「暂不支持」 | WK 跨域限制 |

**可选下一增强（不进 V1.5 必做）**

- TOTP 本地算码（设计稿 LA-4）。  
- 保存时询问「是否同时写入系统密码」（需 entitlement / 系统 API，优先级低）。  
- 字段 `autocomplete` 不合格时，探测后临时标记便于系统 AutoFill（谨慎，可能扰动站点脚本）。

---

## 8. 分阶段交付

### Phase IF-0 — 检测与装饰

- UserScript 登录表单启发式 + MutationObserver  
- 密码框内联主图标；message：`formDetected` / `iconClicked`  
- 工具栏：检测到表单亦可强调态  

### Phase IF-1 — 菜单与 Recipe 联动

- Native 锚定菜单：匹配 Recipe 一键登录 / 仅填入  
- OTP 字段检测 → 默认 fillOnly  
- 复用 `LoginRunner`  

### Phase IF-2 — 系统密码桥

- `SystemPasswordBridge` + 回填  
- Entitlement 缺失时的空态文案  
- （可选）聚焦字段尝试唤起系统 AutoFill  

### Phase IF-3 — 保存提示

- 输入草稿追踪 + 成功启发式  
- 确认保存 / 更新 / 本站不再询问  
- 与设置项「登录成功后询问保存」  

### 验收要点

- [ ] 测试页与至少 2 个真实登录页出现内联图标且不严重挡字  
- [ ] Recipe 一键与「仅填入」行为正确；有 OTP 框时不自动点登录  
- [ ] 系统密码路径：有签名条件下可选中并双字段回填  
- [ ] 手输登录成功后出现保存提示；取消不写库；确认后工具栏可一键复用  
- [ ] 关闭全局开关后不再注入图标、不再弹保存  

---

## 9. 开放问题

1. 内联菜单用 `NSMenu` 还是自定义 `NSPopover`（视觉更贴近网页）？建议 **先 NSMenu，快且稳**。  
2. 「保存」是否默认勾选自动登录？建议 **默认不勾选**。  
3. 是否在设置中提供「可信站点列表」才显示内联图标？建议 V1.5 默认全站检测，提供单站闭嘴。  
4. Apple web-browser entitlement 申请进度是否阻塞 IF-2？建议 **不阻塞**：IF-0/1/3 先交付，IF-2 可并行验证。

---

## 10. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：表单检测、内联入口、系统密码分层、Recipe/保存流、修订建议与 IF-0～3 |
| 0.2 | 2026-07-15 | V1.5 落地：IF-0～IF-3 实现 |

实现任务见 [login-form-inline-development-plan.md](login-form-inline-development-plan.md)；本文件为产品与技术定稿来源。
