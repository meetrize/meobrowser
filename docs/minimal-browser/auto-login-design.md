# 站点登录助手（一键 / 自动登录）— 设计方案

> 目标：为常用工作站点提供可控的一键登录与可选自动登录，覆盖账号密码、短信验证码、二维码三类流程；本地优先、按站点配置，不做全网密码管理器。  
> 状态：**V1 已实现**；**V2 Mac 管线 + Android Companion 工程已落地**（端到端待手测 · 2026-07-15）；V3 未实现  
> 后续：[login-form-inline-design.md](login-form-inline-design.md)（表单内联助手 V1.5 设计草案）· [captcha-assist-design.md](captcha-assist-design.md)（图形验证码智能助手设计草案）  
> 关联：[auto-login-development-plan.md](auto-login-development-plan.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [design.md](design.md) · [new-tab-launchpad-design.md](new-tab-launchpad-design.md) · [download-design.md](download-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**登录助手（Login Assist）**：对「你自己配置过的站点」做填表与提交编排；保存的是**站点登录剧本（Recipe）**，不是通用自动填密码引擎。

这与路线图「不做完整密码管理器」相容：范围限定、显式配置、不扫描全网表单、不云同步账号库（默认）。

### 1.2 要解决的痛点

| 用户场景 | 痛点 | 助手价值 |
|----------|------|----------|
| 运维日常开 Grafana / 云控制台 | 每天手动输账密 | 一键 / 自动提交 |
| 国内站短信登录 | 切手机找验证码 | 验证码自动回填 |
| 桌面扫二维码登录 | 掏手机对准显示器 | 减少对准与等待 |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 按 origin（或 URL 模式）配置登录 Recipe | 通用启发式「猜测全站登录框」（V1） |
| Keychain 存密文；元数据本地 JSON | 自建加密同步云、公开「密码库」产品形态 |
| 工具栏「一键登录」点亮 + 可选自动执行 | 无提示静默批量撞库式登录 |
| 短信 OTP：Companion App → 用户可控通道 → 浏览器 | 浏览器直接读系统短信权限（macOS 无合规通用 API） |
| 二维码：检测 + 手机侧确认联动（见 §5） | 保证破解所有扫码风控 / 滑块验证码 |
| 与 Launchpad 快捷方式可选绑定 | Chromium 扩展生态兼容 |

### 1.4 设计原则

1. **显式优于聪明**：站点必须先有 Recipe；自动登录默认关，仅白名单开启。  
2. **人在回路**：一键登录默认；自动登录需二次确认设置；敏感操作可要求 Touch ID。  
3. **本地优先**：凭证进钥匙串；Companion 通道可选自建 / 私有，不强迫账号体系。  
4. **失败可解释**：选择器失效、验证码超时、扫码过期都有明确 UI，便于修好 Recipe。  
5. **与现有 chrome 同构**：工具栏 ActionGroup 按钮 + 独立设置窗，模式对齐下载管理。

### 1.5 可行性总评

| 能力 | 可行性 | 说明 |
|------|--------|------|
| 用户名密码 + 点击/回车提交 | **高** | `evaluateJavaScript` / `WKUserScript` 已可用；Keychain + 设置 UI 可新建 |
| 工具栏点亮 + 自动登录策略 | **高** | ActionGroup 已有占位扩展位；URL 匹配规则清晰 |
| 短信验证码闭环 | **中** | 浏览器侧填码易；难在手机收短信与安全传通道；需 Companion |
| 二维码减负 | **中偏低** | 无统一 Web API；按站点策略 + 图像检测/剪贴板/Companion 组合；无法「零操作通吃」 |
| 滑块 / 图形验证 / 风控 | **中（可选模块）** | 见 [captcha-assist-design.md](captcha-assist-design.md)；默认关、白名单、不保证通杀 |

**结论**：V1 做「密码 Recipe + 一键/自动」即可交付核心价值；短信与二维码作为 V2/V3 增量，且把 Companion 设计成同一通道复用。

---

## 2. 用户体验总览

### 2.1 Chrome 落点

```
[ ← → ↻ ] [ ========== 地址栏 ★ ========== ] [ ↓  …  key.horizontal  … ]
                                                    ↑
                                         登录助手（有匹配 Recipe 时可用/点亮）
```

| 状态 | 视觉 / 行为 |
|------|-------------|
| 当前页无匹配 Recipe | 按钮灰色或收入「更多」；tooltip「当前页无可登录配置」 |
| 有 Recipe，未登录迹象 | **点亮**；单击执行一键登录 |
| 正在执行 | 转圈 / 禁用重复点击 |
| 登录成功（Cookie / URL 离开登录页） | 恢复常态或短暂勾选动画 |
| 配置了自动登录 | 进入匹配页后短暂延迟自动跑同一流程（可 Esc 取消） |

快捷键建议：⌘⇧L（Login）触发当前页一键登录；⌘, 设置里管理 Recipe。

### 2.2 设置界面（必做）

独立窗口或设置内分区「登录助手」：

| 区块 | 内容 |
|------|------|
| 站点列表 | origin / 名称 / 登录方式徽章 / 自动登录开关 |
| 编辑 Recipe | URL 匹配、字段选择器、触发方式、凭证引用、自动登录、超时 |
| Companion | 配对状态、通道类型、短信规则、二维码策略 |
| 安全 | 使用前要求 Touch ID、自动登录最短间隔、导出加密备份（可选） |

输入框一律 `SBTextField` / `SBSecureTextField`（见全局文本输入规范）。

### 2.3 与 Launchpad 的关系

可选：快捷方式编辑页增加「打开后一键登录」。打开 URL → 导航完成 → 若有匹配 Recipe 且勾选，自动执行。  
数据源仍分离：快捷方式管「去哪」；Recipe 管「如何登」。

---

## 3. 核心模型：Login Recipe

### 3.1 数据结构（概念）

```text
LoginRecipe
  id, title
  match: { host, pathPrefix? | regex? }     // 默认 host 精确或 eTLD+1
  mode: password | sms_otp | qr_assisted | hybrid
  autoLogin: bool                            // 默认 false
  requireUnlock: bool                        // Touch ID / 系统解锁
  steps: [LoginStep...]
  credentialsRef: KeychainAccount            // 用户名/手机/密码等
  successHints: { urlNotMatching?, cookieName?, jsPredicate? }
  updatedAt
```

```text
LoginStep（按序执行）
  waitFor: css | timeoutMs
  fill: { css, valueFrom: username|password|phone|otp|literal }
  click: { css }
  pressEnter: { css }                        // 对焦点字段发 keydown
  waitOTP: { css, maxWaitMs }                // 阻塞至收到码或超时
  waitUser: { reason: "qr_confirm" }         // 等人在手机侧确认
  pauseMs
```

V1 可用「录制辅助」降复杂度：用户在页面点选输入框/按钮，浏览器写入 CSS 选择器（优先稳定属性：`name`、`id`、`autocomplete`、`data-testid`），并允许手工改。

### 3.2 执行引擎

```
匹配当前 URL →（自动？）→ 取 Keychain 凭证
        → 按 steps 注入 JS
        → OTP 步：订阅 Companion 通道
        → 成功判定 / 失败提示
```

实现勾子：

| 钩子 | 用途 |
|------|------|
| `WKUserScript`（document-end） | 登录页早期就绪、可选 MutationObserver |
| `didFinishNavigation` / `didCommit` | 触发匹配与自动登录调度 |
| `evaluateJavaScript:` | 逐步 fill / click（已有同类用法） |
| `WKScriptMessageHandler` | 页面侧回报「找到表单 / 提交完成 / 出现验证码框」 |

自动登录防抖：同一 tab + 同一 Recipe 在 N 秒内不重复；检测到已登录（成功 hint）则跳过。

### 3.3 凭证存储

| 数据 | 存储 |
|------|------|
| 密码、手机号等敏感字段 | macOS Keychain（`kSecClassGenericPassword`，service=`MeoBrowser.LoginAssist`） |
| Recipe 元数据、选择器、开关 | `Application Support/MeoBrowser/LoginAssist/recipes.json` |
| Companion 配对 token | Keychain |

清除「网站数据」**不**删 Recipe/Keychain（与 Cookie 分开）；设置页单独「删除该站点登录配置」。

---

## 4. 登录方式详细设计

### 4.1 用户名密码（V1 — 必做）

**流程**

1. 用户配置：用户名选择器、密码选择器、提交方式（点击按钮 CSS 或对某字段回车）。  
2. 一键：填入 → 触发提交。  
3. 可选：成功后记住「上次成功」时间，供状态灯使用。

**技术风险与对策**

| 风险 | 对策 |
|------|------|
| SPA 晚渲染 | `waitFor` + 短轮询 / MutationObserver |
| 选择器因改版失效 | 执行失败对话框：「打开编辑」；可选多选择器兜底 |
| 站点禁用 programmatic input | 派发 `input`/`change`/`keydown` 事件；仍失败则提示手动 |
| HTTP Basic Auth | 另案：`WKNavigationDelegate` 鉴权回调填 `NSURLCredential`（与表单分流） |

**更好的建议（相对「纯手写选择器」）**

1. V1.5：对常见框架生成模板（`input[type=password]` + 前一个 text/email + `button[type=submit]`）。  
2. 优先读 `autocomplete="username|current-password"`。  
3. **不**默认开启自动登录；首次成功一键后弹一次「是否下次自动？」。

### 4.2 手机验证码（V2）

浏览器无法直接读系统短信。闭环必须是：

```
短信到达手机
  → Companion App 解析 OTP
  → 加密上报用户选定通道
  → MeoBrowser 拉取 / 推送接收
  → 填入 waitOTP 对应字段 → 可选自动提交
```

**Companion 职责**

- 读取通知或短信（Android 相对容易；iOS 需用户「分享到 App」或通知扩展，完整系统短信权限受限 —— **Android 优先，iOS 降级为通知/粘贴板/手动分享**）。  
- 本地正则：`\b(\d{4,8})\b`，结合发件人白名单。  
- 只上传「验证码 + 时间戳 + 可选发件人 hash」，不上传全文（隐私默认）。

**云通道选型（按推荐序）**

| 方案 | 优点 | 缺点 | 建议 |
|------|------|------|------|
| A. 用户自建（Cloudflare Worker / 小 VPS + WebSocket） | 数据自主 | 配置成本 | **专业用户默认推荐** |
| B. 私有中继（你方可选运营） | 开箱即用 | 信任与合规成本 | 可选，默认关 |
| C. 局域网 Bonjour + 同 Wi‑Fi | 无公网 | 不在同一网失效 | 作为「办公室模式」 |
| D. 仅剪贴板：手机复制，Mac Universal Clipboard | 零基建 | 非自动、依赖 Apple 生态 | V2 降级路径 |

**OTP 判定规则**

- 只接受配对后、最近 T 秒（默认 120s）内、未被消费的验证码。  
- 可选匹配：当前站点关联的「发件人关键词」（如 阿里云、腾讯）。  
- 消费后即作废，防重放。

**更好的建议**

1. 能用邮件 OTP / Authenticator TOTP 的站点，优先引导用户改认证方式，短信作兜底。  
2. 浏览器侧对 OTP 输入框优先认 `autocomplete="one-time-code"`。  
3. **不要**做永久短信全文云端存储。

### 4.3 二维码（V3 — 智能减负）

二维码登录的本质矛盾：**凭证在手机 App，挑战在桌面页面**。浏览器既不能替手机「同意登录」，也难统一所有 QR 协议。目标应改为：**减少「对准屏幕」和「来回确认状态」的摩擦**，而不是承诺全自动。

#### 4.3.1 推荐交互策略（按减负程度）

| 策略 | 用户操作 | 适用 | 说明 |
|------|----------|------|------|
| **S1 传图到手机** | 手机点「确认登录」即可，无需对准显示器 | 大多数扫码页 | 浏览器检测登录区 QR → Companion 展示可扫图或系统扫码器打开该图 |
| **S2 解析跳转** | 手机打开深度链接 / 内置 WebView 完成授权 | App 支持 URL Scheme | 解析 QR 为 URL，推到手机直接打开（比「再扫一次」更短） |
| **S3 反向登录** | 手机先登录，桌面输入配对码 / 等推送 | 少数支持「手机开通向桌面」的产品 | 产品侧能做时最优，但不通用 |
| **S4 会话接力** | 用户已在手机登录同一服务 | Cookie/Token 无法安全搬运则放弃 | **不要**尝试导出 App Cookie 到桌面（高风险且常不可行） |
| **S5 人机协作 HUD** | 扫完后看桌面状态灯 | 所有方案兜底 | 检测「二维码消失 / 跳转成功」给出明确成功/过期提示 |

**默认推荐组合：S1 + S5**；能解析 URL 时升级为 S2。

#### 4.3.2 桌面侧智能检测

1. **DOM**：`img[src^=data:image]`、canvas、带 `qr`/`login` class 的节点；站点 Recipe 可写死选择器。  
2. **视觉**：对登录主区域截图，跑轻量 QR 解码（如 CIQRCode / zxing 类库）——作 DOM 失败时的兜底。  
3. **生命周期**：页面刷新后 QR 常变；助手应缓存「当前 challenge」并在过期时自动刷新截图再推。

#### 4.3.3 手机侧体验（Companion）

```
桌面：检测到 QR → 通知 Companion「某某站点待确认」
手机：推送 → 打开 App → 大图展示 QR / 一键用系统相机扫相册图 / 直接打开 URL
桌面：轮询 successHints → 「已登录」
```

关键路径：同局域网时用 Bonjour，延迟与可靠性更好；外出再用加密中继。

#### 4.3.4 明确不承诺

- 微信 / 银行级风控、活体、滑块：超出范围。  
- 「自动点手机上的同意」若需 Accessibility 滥用或私有 API：不做。  
- 伪造扫码协议、中间人登录：禁止。

---

## 5. 架构（落到现有代码）

```
BrowserWindowController
  ├─ ActionGroup「登录」按钮状态 ←── LoginAssistController
  ├─ WKNavigationDelegate（匹配 / 自动调度）
  └─ 共享 WKWebViewConfiguration
        ├─ WKUserScript（可选观察）
        └─ WKScriptMessageHandler（页面回调）

LoginAssistController
  ├─ RecipeStore (JSON)
  ├─ CredentialStore (Keychain)
  ├─ LoginRunner (逐步 JS)
  └─ CompanionChannel (V2+)
        ├─ LocalBonjour
        └─ RelayClient (用户配置 endpoint)

BrowserLoginAssistSettingsWC
  └─ Recipe 列表 / 编辑 / Companion 配对
```

| 建议新增文件（示意） | 职责 |
|----------------------|------|
| `SimpleBrowser/LoginAssist/LoginRecipe.h/.m` | 模型编解码 |
| `.../LoginRecipeStore.h/.m` | JSON 持久化 |
| `.../LoginCredentialStore.h/.m` | Keychain |
| `.../LoginRunner.h/.m` | 执行 steps |
| `.../LoginAssistController.h/.m` | 匹配、按钮、自动登录策略 |
| `.../BrowserLoginAssistSettings*.m` | 设置 UI |
| `.../Companion/*.m`（V2） | 配对与 OTP/QR 通道 |

复用模式：下载管理的 ActionGroup 角标、设置窗 `NSStackView` 布局、Keychain 不进 `NSUserDefaults`。

---

## 6. 安全与隐私

1. 密码只进 Keychain；日志禁止打印明文。  
2. 自动登录默认关；开启时设置页醒目提示。  
3. 可选：执行前 `LAContext`（Touch ID）。  
4. Companion 通信：TLS + 配对码（一次性）+ 设备密钥；OTP 消息短 TTL。  
5. 不上传浏览历史；中继若启用，仅传 OTP/QR 载荷。  
6. 与「清除网站数据」边界写进设置文案，避免用户误以为登出会删 Recipe。

---

## 7. 分阶段交付

### V1 — 密码一键登录（建议先做）

- Recipe CRUD（密码模式）+ Keychain  
- 工具栏点亮 + ⌘⇧L  
- fill + click/enter  
- 自动登录开关（带防抖与成功 hint）  
- 选择器「点选拾取」基础版  

**验收**：对 2～3 个自选站（可含 localhost 测试页）一键登录成功；失效选择器有明确错误。

### V2 — 短信 OTP（Android 优先）

- **主路径**：Android Companion 读短信/通知 → 加密推码 → Mac `waitOTP` 自动填入  
- 通道：首版局域网 Bonjour（C）；自建 WS（A）为外出增强  
- Mac 粘贴 / 剪贴板：同一 `OTPInbox` 降级  
- iOS：通知共享 / 手动粘贴；完整读短信不做硬依赖  

### V3 — 二维码辅助

- DOM/截图检测 QR  
- S1 传图 + S5 状态 HUD  
- 可解析则 S2  

### 明确后续可选

- HTTP Basic / 客户端证书  
- TOTP（本地 Authenticator，比短信更合适专业用户）  
- 配方市场 / 导入 JSON 模板（仅选择器，不含密码）

---

## 8. 相对原设想的调整建议

| 原设想 | 建议调整 | 原因 |
|--------|----------|------|
| 接近完整账密保存 + 全站智能 | **站点 Recipe + 显式配置** | 对齐「非密码管理器」；降低误填与维护成本 |
| 自动登录与一键并列主推 | **一键为主，自动为可选** | 防惊喜登错号、防循环刷新触发 |
| 自研 Pushbullet 式短信云 | **通道可插拔；优先自建/局域网** | 信任与合规；专业用户可接受自建 |
| 二维码「智能到接近自动」 | **传图 / 深链减负 + 状态联动** | 协议碎片化；保证体验上限诚实 |
| 三者同时开工 | **V1→V2→V3** | Companion 基建可复用；先验证填表引擎 |

**额外高价值建议（尤其面向本产品用户）**

1. **TOTP 优先于短信**：运维面板常支持；本地算码，无 Companion。可在 V1.5 插入。  
2. **环境隔离**：Staging/Prod 两套 Recipe + Launchpad 环境角标，避免登错环境。  
3. **失败录屏式调试**：开发模式下展示「当前 step / 选择器是否命中」，方便修 Recipe。  

---

## 9. 开放问题（待拍板）

1. Companion：**自研最小 Android App**（V2 主路径）；Mac 粘贴为降级。  
2. 中继：首版 **Bonjour 局域网**；另提供自建 WS/Worker 模板；不做强制公有托管。  
3. Recipe 是否允许 path 级多账号（同一 host 两个账号）？建议：**同一 match 多 Recipe，工具栏长按选账号**。  
4. 与系统「密码」App / iCloud 钥匙串是否互通？建议 V1 **不通**，避免范围爆炸。  
5. 自动登录是否允许在「仅固定标签」生效，进一步降低误触？  

---

## 10. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：可行性、三类登录、二维码策略、分阶段与架构落点 |
| 0.2 | 2026-07-15 | 补充开发计划链接（LA-0～LA-7） |
| 0.3 | 2026-07-15 | V1 落地：Recipe/Keychain/Runner/设置/拾取/自动登录 |
| 0.4 | 2026-07-15 | V2 开放问题拍板：Android Companion 主路径；Bonjour P0；粘贴降级 |

分阶段任务与验收清单见 [auto-login-development-plan.md](auto-login-development-plan.md)；本文件保持产品与技术方案真相来源。
