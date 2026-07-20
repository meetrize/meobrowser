# Companion 手机通知镜像（MVP）— 开发计划

> 基于 [companion-notification-mirror-design.md](companion-notification-mirror-design.md) 的分阶段实施计划。  
> 前置条件：Companion V2 配对 / `otp` 通道、`OtpNotificationListener`、登录助手设置页已就绪。  
> 状态：**NM-0～NM-2 已完成；NM-3 代码打磨完成，真机手测待勾选**（2026-07-20）  
> 协议：[companion-protocol.md](companion-protocol.md)（V2.1）

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 默认模式 | Android `otp_only` |
| 全部模式确认 | 切换时强制确认对话框 |
| Mac「接收手机通知镜像」 | 默认开 |
| Mac「验证码也显示系统通知」 | 默认开；仅对纯 `otp`（无对应镜像）生效 |
| 全部模式验证码 | `phone_notification` + `otp`；系统通知只跟镜像弹一次 |
| 图标附件 | 不做 |
| 断线缓存 | 不做；未连接则丢弃 |
| 限流 | 全局最多约 5 条/秒；同 `id` 60s 去重 |
| `ts` 过期 | MVP 仍展示，打日志 |
| 未知 type | Mac 安全忽略 |

**首版交付目标：NM-0 + NM-1 + NM-2 + NM-3。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase NM-0 | 协议与骨架 | 完成 | 协议文档落地；Mac 忽略未知 type；空 Presenter / Prefs |
| Phase NM-1 | Android 模式与推送 | 完成 | 模式 UI；全部过滤；`phone_notification` 发送 |
| Phase NM-2 | Mac 接收与系统通知 | 完成 | 鉴权、横幅、权限、设置开关 |
| Phase NM-3 | 联调与打磨 | 代码完成 / 手测待办 | 双弹避免、前台横幅、验收文档 |
| Phase NM-4 | 二期（可选） | 不做 | 白名单 / 面板 / 图标 / 加密 |

---

## Phase NM-0：协议与骨架

**目标**：文档与代码边界清晰，旧客户端不因新消息类型崩溃。

### 任务清单

#### 0A — 文档

- [x] **0.1** 确认设计稿与本计划已入库（本文件 + design）
- [x] **0.2** 更新 [companion-protocol.md](companion-protocol.md)：增加 V2.1 `phone_notification` / `phone_notification_ok` 与并存规则
- [x] **0.3** Companion README 增加「通知镜像」一小节（可先链到设计稿）

#### 0B — Mac 骨架

- [x] **0.4** 新增 `PhoneNotificationSettings`（UserDefaults：`mirrorEnabled`、`otpBannerEnabled`，默认 YES）
- [x] **0.5** 新增 `PhoneNotificationPresenter` 空实现：`presentFromPayload:` / `presentOTPBannerIfNeeded:`
- [x] **0.6** `CompanionChannel`：对非 `hello`/`otp`/`phone_notification` 的 type **安全 return**（若已有则核对）
- [x] **0.7** Makefile / 头文件引用就绪（随 NM-2 真正调用亦可）

**完成标准**：编译通过；现有配对与 `otp` 回归无变化。

---

## Phase NM-1：Android 模式与推送

**目标**：手机端可选模式；全部模式下能发出合规 JSON。

### 任务清单

#### 1A — 偏好与 UI

- [x] **1.1** `PairingPrefs`（或新 Prefs）增加 `notificationMirrorMode`：`otp_only` | `all`
- [x] **1.2** `activity_main.xml`：分段控件「仅验证码 / 全部通知」
- [x] **1.3** 切到 `all` 时确认对话框（隐私文案见设计 §3.2 / §7）
- [x] **1.4** 首页摘要展示当前模式；与通知使用权状态并列

#### 1B — 过滤与组装

- [x] **1.5** `NotificationNoiseFilter`：ongoing / group summary / 自身包 / 空内容
- [x] **1.6** `NotificationPayloadBuilder`：appLabel、title、body、截断、id、ts、postTimeMs
- [x] **1.7** 同 id 60s 去重；全局约 5 条/秒限流

#### 1C — Listener 与通道

- [x] **1.8** `OtpNotificationListener.handleSbn`：
  - `otp_only` → 现有 OTP 兴趣过滤 + `SmsOtpHandler`
  - `all` → Filter → `pushPhoneNotification`；再若像 OTP → `SmsOtpHandler`
- [x] **1.9** `CompanionSession.pushPhoneNotification`：组 JSON、`type=phone_notification`、需已连接
- [x] **1.10** 处理 `phone_notification_ok` / `error`（更新 `lastSmsEvent` 即可）
- [x] **1.11** 未连接：丢弃并 `noteSmsEvent("未连接，已跳过通知镜像")`（避免刷屏可节流）

**完成标准**：用调试 Mac 或日志可见完整 JSON；`otp_only` 不发 `phone_notification`。

---

## Phase NM-2：Mac 接收与系统通知

**目标**：鉴权后弹出系统通知；设置可关。

### 任务清单

#### 2A — 通道

- [x] **2.1** `CompanionChannel` 识别 `phone_notification`
- [x] **2.2** 校验 `deviceToken`；非法回 `error`
- [x] **2.3** `mirrorEnabled == NO` 时仍回 `phone_notification_ok`，不展示
- [x] **2.4** 成功展示或主动跳过后发 `phone_notification_ok`（带 `id`）

#### 2B — Presenter

- [x] **2.5** 申请 `UNUserNotificationCenter` 授权（alert + sound）
- [x] **2.6** 按设计 §6.3 组装标题/正文；`threadIdentifier=packageName`
- [x] **2.7** `request.identifier` 基于 payload `id`
- [x] **2.8** `otp` 成功写入 Inbox 后：若 `otpBannerEnabled` 且本次不是「全部模式已镜像」场景——MVP 简化为：**仅当无近期同 code 镜像时**，或更简单：**otp 横幅仅在 Android 为 otp_only 时需要**；因 Mac 不知 Android 模式，定稿为：
  - **实现简化**：`otp` 横幅默认开；`phone_notification` 展示时把 `id`/`package` 记入短 TTL 集合；若随后 2s 内同连接又收到 `otp`，则 **跳过** otp 横幅（避免双弹）
- [x] **2.9** 日志不打印完整 body

#### 2C — 设置 UI

- [x] **2.10** 登录助手 Companion 区域增加两开关 + 权限说明
- [x] **2.11** 未授权时「打开通知设置」按钮（`NSWorkspace` 打开通知设置 URL）

**完成标准**：真机通知 → Mac 横幅标题含 App 前缀；关镜像开关后不再弹出但仍 ack。

---

## Phase NM-3：联调与打磨

**目标**：达到设计稿 §9 验收。

### 任务清单

- [x] **3.1** 端到端：otp_only 填码回归（短信 + 通知栏验证码）— 逻辑回归；**真机待勾选**
- [x] **3.2** 端到端：all 模式普通通知镜像 — 管线已通；**真机待勾选**
- [x] **3.3** 验证码通知：填码成功 + 只弹一条系统通知 — 3s 抑制；**真机待勾选**
- [x] **3.4** ongoing（音乐）不推送 — `NotificationNoiseFilter`
- [x] **3.5** Mac 拒绝通知权限：填码仍可用 — OTPInbox 与 Presenter 解耦
- [x] **3.6** 新旧版本兼容：旧 Mac 忽略 `phone_notification`；旧 Android 无镜像
- [x] **3.7** 更新 Companion README、设计稿状态、acceptance.md
- [x] **3.8** 手动测试清单写入 [acceptance.md](acceptance.md)

**完成标准**：§9 清单全部勾选；无严重刷屏。

---

## Phase NM-4：二期（本计划不实施）

- 精选 App 白名单
- 应用内通知面板
- 图标 `UNNotificationAttachment`
- 帧加密、断线补发

---

## 建议实现顺序（单人）

```text
NM-0.2 协议文档
  → NM-1 全阶段（Android 可先用日志验证 JSON）
  → NM-0.4～0.6 + NM-2（Mac 收包弹通知）
  → NM-3 联调
```

Android 与 Mac 可由两人并行：先冻结 JSON schema（设计 §4），再并行 NM-1 / NM-2。

---

## 关键文件（预期）

### Android

| 路径 | 变更 |
|------|------|
| `.../sms/OtpNotificationListener.kt` | 模式分支 |
| `.../sms/NotificationNoiseFilter.kt` | 新增 |
| `.../sms/NotificationPayloadBuilder.kt` | 新增 |
| `.../pairing/PairingPrefs.kt` | 模式字段 |
| `.../channel/CompanionConnectionService.kt` / `CompanionSession` | `pushPhoneNotification` |
| `.../ui/MainActivity.kt` + `activity_main.xml` | 模式 UI |
| `.../res/values/strings.xml` | 隐私文案 |

### Mac

| 路径 | 变更 |
|------|------|
| `SimpleBrowser/LoginAssist/Companion/CompanionChannel.m` | 处理新 type |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationPresenter.h/.m` | 新增 |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationSettings.h/.m` | 新增 |
| `BrowserLoginAssistSettingsWindowController.m` | 开关 UI |
| `Makefile` | 新源文件 |

### 文档

| 路径 | 变更 |
|------|------|
| `docs/minimal-browser/companion-protocol.md` | V2.1 |
| `companion/android/MeoCompanion/README.md` | 使用说明 |
| 本设计 / 计划 | 状态更新 |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 全部模式刷屏 | 过滤 + 限流 + 去重；默认 otp_only |
| 明文隐私顾虑 | 确认框 + 文档披露；二期加密 |
| 小米 Listener 不稳 | 复用现有 rebind / 向导 |
| 双弹验证码 | NM-2.8 短 TTL 抑制 otp 横幅 |
| 自定义通知无文案 | 空则跳过；不强求 |

---

## 附录：手动验收清单

复制到测试时使用：

- [ ] 默认安装为「仅验证码」
- [ ] 切「全部」有确认；取消则保持原模式
- [ ] 仅验证码：微信普通消息不出现在 Mac
- [ ] 仅验证码：验证码仍可填入登录助手
- [ ] 全部：普通通知 Mac 标题含 App 名
- [ ] 全部：验证码可填码且横幅不双弹
- [ ] 播放音乐时不推 ongoing
- [ ] Mac 关「接收镜像」后不再弹
- [ ] Mac 关系统通知权限后填码仍可用
- [ ] 断线后 Android 有「跳过」类提示（节流后）
