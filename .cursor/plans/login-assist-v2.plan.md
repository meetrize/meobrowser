---
name: 登录助手 V2
overview: 以 Android Companion 短信自动推码为主路径打通 V2：协议+Mac 收码+waitOTP+最小 Android App；粘贴为降级；TOTP（LA-4）插在短信闭环之后。
todos:
  - id: v2-protocol
    content: 协议定稿：配对码/设备密钥、otp 消息格式、TTL；CompanionChannel + OTPInbox 单一出口
    status: completed
  - id: v2-mac-channel
    content: Mac：CompanionChannel 收码（先 Bonjour 局域网，或同仓最小本地 Relay Mock）+ 设置配对/连接状态/断连明示
    status: completed
  - id: v2-recipe-waitotp
    content: Mac：Recipe sms/hybrid 字段 + Runner waitOTP→填码→提交；测试页短信流
    status: completed
  - id: v2-android-app
    content: Android 最小 App：读短信/通知→解析 4～8 位码→加密推送到已配对 Mac（不上传全文）
    status: completed
  - id: v2-e2e-accept
    content: 端到端验收：真机/模拟短信→自动填入提交；过期/重放/断连；文档勾选
    status: pending
  - id: v2-paste-fallback
    content: 降级：Mac「粘贴验证码」/waitOTP 期间剪贴板（无 App 仍可完成）
    status: completed
  - id: v2-totp-optional
    content: LA-4（后续插入）：本地 TOTP Keychain + fillTotp，不阻塞短信闭环
    status: pending
isProject: true
---

# 登录助手 V2 — Cursor 自动开发计划（Android 优先）

> **依据**：[auto-login-design.md](../../docs/minimal-browser/auto-login-design.md) · [auto-login-development-plan.md](../../docs/minimal-browser/auto-login-development-plan.md)  
> **前置**：V1（LA-0～3）+ V1.5（表单内联）已完成  
> **范围重排（相对 plan 0.1）**：以 **Android Companion 短信 → 自动填入** 为 V2 主验收；Mac 粘贴降级；**LA-4 TOTP 后置**；不含 LA-6 二维码。  
> **定稿变更**：Companion 不再「粘贴做完再接」——**App 与 Mac 收码通道并行开工，以真机推码闭环为门禁**。

---

## 0. 目标与非目标

### 用户可感知结果（V2 门禁）

1. Android 收到登录短信 → Companion 解析验证码 → 数秒内推到已配对 MeoBrowser。  
2. Mac 正在 `waitOTP`（或一键登录走到 OTP 步）→ **自动填入并提交**（按 Recipe）。  
3. 断连 / 未配对时设置与 HUD **明示**，不无声失败。  
4. 无 App 时仍可用「粘贴验证码」降级完成同流程（不阻塞主验收，可同 PR 或紧随）。

### 明确不做（本 plan）

| 不做 | 说明 |
|------|------|
| iOS 完整读短信 | 文档写分享/粘贴降级即可 |
| 公有强制托管中继 | 可自建模板；首版优先 **同 Wi‑Fi Bonjour** 降低基建 |
| 短信全文上云 | 只传码 + ts + 可选发件人 hash |
| LA-6 二维码 | V3；协议可预留 `qr_image` 类型 |
| 滑块/风控 | 边界不变 |
| 完整密码管理器 | 仍须显式 Recipe |

---

## 1. 为什么这样排

原先「先 Mac 粘贴再 Companion」适合削风险，但**产品核心痛点是切手机找短信**。无 App 的粘贴路径体验接近 Universal Clipboard，无法验收「自动填入」。

因此硬门禁改为：

```text
短信到达 Android → App 推码 → Mac OTPInbox → waitOTP 填码提交
```

Mac 侧仍须先有收码与 `waitOTP`（否则 App 无处可推）；二者 **同波交付**，不是「粘贴做完再开 App」。

---

## 2. 架构

```
┌─ Android: MeoCompanion ─────────────────────────┐
│  SmsReceiver / NotificationListener             │
│  OtpParser (4～8 位)                             │
│  CompanionClient ──encrypt──► channel           │
└───────────────────────────────────────┬─────────┘
                                        │ Bonjour (首选) / 自建 WS
┌─ macOS: MeoBrowser ───────────────────▼─────────┐
│  CompanionChannel → OTPInbox.submit(code, …)    │
│  LoginRunner.waitOTP → fill otpSelector → submit│
│  Settings: 配对码 / 连接状态 / 注销               │
│  Fallback: 粘贴验证码 / 剪贴板 → 同一 OTPInbox   │
└─────────────────────────────────────────────────┘
```

### OTPInbox（单一出口，不变）

```text
submitCode:source:  → 校验长度/TTL/未消费 → 唤醒 waiter
waitForCodeWithTimeout:completion:
来源: companion | paste | clipboard | mock
```

### 通道选型（本 plan 定稿）

| 优先级 | 方案 | 理由 |
|--------|------|------|
| **P0 首版落地** | **局域网 Bonjour（NSNetService + Android NSD/附近设备）** | 办公室同网延迟低、无公网基建、最快闭环 |
| P1 并行文档 | 自建 WebSocket/Worker 模板 | 外出网；不做强制公有托管 |
| P2 | 仅粘贴 | 降级，不挡主路径验收 |

若 Bonjour 真机调试卡关太久：临时用 **同仓 `tools/otp-relay-mock`（本地 WS）** 联调 App，再补 Bonjour——但验收仍以「App → Mac」为准，不只 Mock。

---

## 3. Phase 拆解（硬顺序）

### Phase V2-0 — 协议 + 收件箱（Mac 库，无 UI 美化可接受）

**todo: `v2-protocol`**

- [ ] 文档小节 / 头文件注释写清消息 JSON：
  ```json
  { "v": 1, "type": "otp", "code": "123456", "ts": 1710000000, "senderHash": "…" }
  { "v": 1, "type": "hello", "deviceId": "…", "pairingToken": "…" }
  ```
- [ ] 配对：Mac 生成 6 位配对码（短 TTL）或二维码 payload；Android 输入后交换会话密钥，存 Keychain / App Keystore。  
- [ ] `OTPInbox.h/.m`：TTL 120s、一次性消费、重复码忽略。  
- [ ] `CompanionChannel` 协议接口：`startAdvertising` / `onOTP` → 只调 Inbox。  
- [ ] 单元级：Mock 调 `submitCode` 能唤醒 `waitForCode`。

### Phase V2-1 — Mac 通道与设置

**todo: `v2-mac-channel`**

- [ ] `SimpleBrowser/LoginAssist/Companion/CompanionBonjour*.m`：发布服务（如 `_meologin._tcp`）、接受连接、解密校验。  
- [ ] 设置窗「Companion」分区（`BrowserLoginAssistSettingsWindowController` 或子页）：
  - 显示配对码 /「重新生成」
  - 连接状态：未配对 / 等待 / 已连接 / 断连
  - 注销设备
  - 隐私文案：默认不上传短信全文；仅验证码与时间戳  
- [ ] 断连：waitOTP HUD / toast **明示**「手机未连接，可粘贴验证码」。  
- [ ] Keychain：配对 token / 设备密钥（service 可 `MeoBrowser.LoginAssist.Companion`）。

### Phase V2-2 — Recipe waitOTP

**todo: `v2-recipe-waitotp`**

- [ ] Recipe 扩展（扁平字段即可）：
  - `phoneSelector` / `otpSelector` / `sendCodeSelector`
  - `otpMaxWaitMs`（默认 120000）
  - `mode`: `sms_otp` | `hybrid`（账密+短信）
- [ ] Keychain 可选 `phone`。  
- [ ] Runner 序：fill user/pass → fill phone → click send → **waitOTP** → fill otp → submit。  
- [ ] Esc / `cancelAll` 取消 wait。  
- [ ] `login-assist-test.html`：发送验证码模拟 + OTP 框 + 成功态（App 联调可用「页面显示真码」对照，生产站无）。

### Phase V2-3 — Android 最小 App（主交付）

**todo: `v2-android-app`**

建议仓内路径（新目录，独立 Gradle）：

```text
companion/android/MeoCompanion/
  app/src/main/...
  README.md                 # 构建、权限、配对步骤
```

最小功能清单：

| # | 功能 | 说明 |
|---|------|------|
| 1 | 配对 UI | 输入 Mac 显示的配对码（或扫 Mac 二维码，P1） |
| 2 | 通道连接 | Bonjour/NSD 发现 MeoBrowser；或填局域网 IP+端口（调试后门） |
| 3 | 读短信 | `RECEIVE_SMS` / `READ_SMS` **或** 优先 **Notification Listener**（部分厂商短信进通知，权限叙事更友好——实现时二选一先打通，文档写清） |
| 4 | 解析 | `\b(\d{4,8})\b`；可选发件人关键词过滤（设置项） |
| 5 | 推送 | 加密发送 `{type:otp,…}`；**禁止**上传短信全文 |
| 6 | 前台状态 | 已连接 / 最近一次推码时间（不显示完整码，或仅末 2 位调试开关） |
| 7 | 电池 | 后台保活尽量用系统允许方式；失败时通知用户「请打开 App」 |

技术选型（建议，实现可微调）：

- 语言：**Kotlin**  
- minSdk：26+  
- 网络：OkHttp / 原生 Socket + 与 Mac 对齐的简帧（长度前缀 JSON）  
- 加密：配对后 AES-GCM 或 TLS（Bonjour 上先共享密钥 AES-GCM 可接受；细则写协议）

**不做（App v1）**：账号体系、云同步、完整 UI 品牌化、iOS 版、自动点「同意登录」。

### Phase V2-4 — 端到端验收

**todo: `v2-e2e-accept`**

- [ ] 同 Wi‑Fi：Android 模拟器发测试短信 **或** 真机真实短信 → Mac 测试页自动填入提交。  
- [ ] 过期码（>120s）不填；同码不二次消费。  
- [ ] 断连后 waitOTP：UI 明示 + 粘贴仍可成功。  
- [ ] `make browser` 通过；Android `./gradlew assembleDebug` 通过。  
- [ ] 回写 `acceptance.md`「登录助手 V2」、design 状态、development-plan LA-5 勾选。

### Phase V2-5 — 粘贴降级（可紧随门禁）

**todo: `v2-paste-fallback`**

- [ ] 设置/执行中「粘贴验证码…」（`SBTextField`）。  
- [ ] 仅 waitOTP 期间轮询剪贴板。  
- [ ] 与 Companion **同一** `OTPInbox`。

### Phase V2-6 — TOTP（后置，不挡短信）

**todo: `v2-totp-optional`**

- [ ] 原 LA-4：`totpSecret` + `LoginTOTPGenerator` + `fillTotp`。  
- [ ] 短信闭环稳定后再做；可另 commit。

---

## 4. 建议文件落点

```text
SimpleBrowser/LoginAssist/
  OTPInbox.h/.m
  LoginRecipe.* / LoginCredentialStore.* / LoginRunner.*   # waitOTP 扩展
  BrowserLoginAssistSettingsWindowController.*            # Companion 分区
  Companion/
    CompanionChannel.h/.m
    CompanionBonjourServer.m
    CompanionSessionCrypto.m
  login-assist-test.html

companion/android/MeoCompanion/                           # 新建独立工程
  app/src/main/java/.../pairing/
  app/src/main/java/.../sms/
  app/src/main/java/.../channel/
  README.md

docs/minimal-browser/
  companion-protocol.md          # 配对与消息（新建）
  companion-relay-template.md    # 可选自建 WS（P1）
  acceptance.md / auto-login-*.md
```

---

## 5. 实施顺序（给 Agent）

```text
① v2-protocol          OTPInbox + 消息/配对契约
② v2-mac-channel       Bonjour 服务端 + 设置配对 UI
③ v2-recipe-waitotp    Runner 能等 Inbox 并填码
④ v2-android-app       ★ 主交付：读短信/通知并推码
⑤ v2-e2e-accept        ★ V2 门禁
⑥ v2-paste-fallback    降级补齐
⑦ v2-totp-optional     LA-4 后置
```

并行建议：①～③ 在 Mac；④ 在 Android 可用 Mock Mac（本机 nc/小脚本）先推码，③ 完成后立刻真联。

**SBKit**：Mac 设置与粘贴框用 `SBTextField` / `SBSecureTextField`。

---

## 6. 风险与时间盒

| 风险 | 缓解 | 盒 |
|------|------|----|
| 厂商短信不进广播 | Notification Listener 兜底；文档列机型 | App |
| Bonjour 跨网段失败 | 调试填 IP；P1 自建 WS | 通道 |
| 后台杀进程丢短信 | 前台服务/用户教育；丢了可粘贴 | App |
| 范围膨胀成「第二个密码 App」 | 严格最小：配对+推码+状态 | 全程 |
| 与旧「粘贴优先」文档冲突 | 已回写 development-plan 行为表 | 文档 |

粗估（一人）：协议+Mac 通道+waitOTP **4～7 天**；Android 最小 **5～10 天**；联调 **2～4 天**；粘贴/TOTP 另计。

---

## 7. Definition of Done（V2 门禁）

- [ ] Android 能从短信/通知解析码并推到已配对 Mac  
- [ ] Mac `waitOTP` 自动填入测试页并提交成功  
- [ ] 断连明示；过期/重放正确  
- [ ] 隐私：无全文上传；日志无完整敏感串联  
- [ ] acceptance / design / development-plan 已更新  
- [ ] 粘贴降级至少可用（可与门禁同周补完）  
- [ ] TOTP **不**作为本门禁必选项  

---

## 8. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：LA-4 → 粘贴 → Companion |
| 0.2 | 2026-07-15 | **重排**：Android 短信自动推码为主路径；粘贴降级；TOTP 后置；Bonjour P0 |

实现若再改通道选型，先改 `companion-protocol.md` 与开发计划行为表，再改本 plan。
