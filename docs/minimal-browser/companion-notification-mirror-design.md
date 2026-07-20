# Companion 手机通知镜像（MVP）— 设计方案

> 目标：在用电脑时，通过已配对的 Meo Companion，把手机通知以可读方式呈现在 Mac 系统通知栏；支持「仅验证码 / 全部通知」两种模式。  
> 状态：**NM-0～NM-3 代码已完成**；真机手测见 [acceptance.md](acceptance.md)（2026-07-20）  
> 开发计划：[companion-notification-mirror-development-plan.md](companion-notification-mirror-development-plan.md)  
> 关联：[companion-protocol.md](companion-protocol.md) · [auto-login-design.md](auto-login-design.md) · [companion/android/MeoCompanion/README.md](../../companion/android/MeoCompanion/README.md)

---

## 1. 方案定位

### 1.1 产品一句话

**手机通知镜像（Notification Mirror）**：Meo Companion 按用户选择监听通知，经现有局域网 Companion 通道推到 MeoBrowser；Mac 用系统通知栏展示，标题带来源 App 前缀，便于在电脑前扫一眼手机动态。

### 1.2 与现有 Companion 的关系

| 能力 | 现状 | MVP 后 |
|------|------|--------|
| 验证码推送 `otp` | ✅ 已有，供登录助手自动填入 | **保留不变** |
| 通知使用权 | ✅ 已有，但只筛验证码 | 扩展为可「全部转发」 |
| Mac 系统通知 | ❌ 无 | ✅ 收到镜像消息后弹横幅 |
| App 图标附件 | — | ❌ MVP 不做（见 §1.4） |
| 精选 App 白名单 | — | ❌ MVP 不做（二期） |
| 应用内通知面板 | — | ❌ MVP 不做（二期） |

登录填码链路与通知镜像**解耦**：

- 「仅验证码」：继续走 `otp`（可附带可选的镜像横幅，见 §3.3）。
- 「全部通知」：每条走 `phone_notification`；若正文像验证码，**额外**再发一条 `otp`（填码不丢）。

### 1.3 做什么 / 不做什么（MVP）

| 做 | 不做 |
|----|------|
| Android：模式开关「仅验证码 / 全部通知」 | 精选 App 白名单 UI |
| Android：全部模式下过滤噪音通知后推送 | 图标 PNG 附件 / 自定义 RemoteViews 像素级还原 |
| 协议：新增 `phone_notification` / `phone_notification_ok` | 帧级 AES-GCM（沿用 V2 明文 + deviceToken） |
| Mac：`UNUserNotificationCenter` 横幅，标题前缀来源 | 伪造系统通知左侧为第三方 App 图标（系统不允许） |
| Mac：通知权限申请与设置入口提示 | 应用内历史列表面板 |
| 去重、字段截断、未连接丢弃（不落盘缓存） | 断线补发队列、跨网 / 云中继 |
| 隐私警告文案（全部模式） | 公有云托管、短信全文上传（验证码模式仍只传码） |

### 1.4 关键约束（已拍板）

1. **macOS 通知左侧图标永远是 MeoBrowser**  
   无法显示微信 / 短信等原 App 图标。MVP 用 **标题前缀** 区分来源：  
   `微信 · 张三` / `短信` / `com.example.app`（无 label 时退回包名）。

2. **默认模式 = 仅验证码**  
   与现有隐私承诺一致：「默认不上传短信/通知全文」。

3. **全部模式 = 显式用户选择 + 警告**  
   全文经同 Wi‑Fi 明文通道；UI 必须提示敏感风险。

4. **不做图标附件**  
   二期再评估 `UNNotificationAttachment` + package 图标缓存。

---

## 2. 用户场景

### 2.1 仅验证码（默认）

```
用户在 Mac 登录某站 → 手机收到验证码短信/通知
  → Companion 解析出 code → 发 type=otp
  → OTPInbox 收码 → 登录助手自动填入
  → （可选）Mac 弹一条系统通知：「验证码 · 123456」便于确认已收到
```

### 2.2 全部通知

```
用户在 Companion 切到「全部通知」并确认隐私提示
  → 微信来一条消息
  → Companion 组装 phone_notification（appLabel=微信, title=张三, body=下午见面）
  → Mac 弹系统通知：
       标题：微信 · 张三
       正文：下午见面
  → 若同时像验证码，再发 otp 供填码
```

### 2.3 适用与不适用

| 场景 | 行为 |
|------|------|
| 手机与 Mac 已配对且 TCP 连接中 | ✅ 实时推送 |
| 未连接 / Wi‑Fi 断开 | ❌ 丢弃（MVP 不缓存）；Android 可记本地「最近事件」日志 |
| 音乐播放中、导航进行中等 ongoing | ❌ 过滤，不推 |
| 本 App（Meo Companion）自身通知 | ❌ 过滤 |
| 无 title/text 的自定义布局通知 | ⚠️ 尽力提取；为空则跳过 |
| Mac 勿扰 / 专注模式 | 遵循系统；本 App 不强制突破 |

---

## 3. 产品行为定稿

### 3.1 Android 模式枚举

```text
NotificationMirrorMode
  otp_only   = 仅验证码（默认）
  all        = 全部通知（过滤后转发）
```

持久化：`SharedPreferences`（如 `PairingPrefs` 旁新增字段 `notificationMirrorMode`）。

### 3.2 UI 入口（Companion 首页）

- 分段控件或单选：**仅验证码** | **全部通知**
- 切到「全部」时弹出确认对话框，文案要点：
  - 将上传通知标题与正文到已配对的 Mac（同局域网）
  - 通道当前为明文，请勿在不可信网络开启
  - 可随时切回「仅验证码」
- 设置摘要行展示当前模式 + 通知使用权状态（复用现有就绪检测）

### 3.3 Mac 系统通知展示规则

| 字段 | 规则 |
|------|------|
| 标题 | `{appLabel}`；若有 `title` 且与 appLabel 不同：`{appLabel} · {title}` |
| 正文 | `body`；空则用 `title`；仍空则不弹 |
| 前缀兜底 | `appLabel` 空 → 用 `packageName`；再空 → `手机通知` |
| 声音 | 默认系统提示音（可后续加静音选项） |
| 点击 | MVP：激活 MeoBrowser（不要求深链到某页） |
| 标识 | `threadIdentifier` = `packageName`（同 App 通知在通知中心可分组） |
| 去重 key | 见 §5.4 |

**验证码模式是否弹系统通知**：MVP 建议 **可选、默认开**（轻量确认「码已到」）。实现上：

- `otp` 到达时，若用户开启「验证码也显示系统通知」（Mac 设置，默认 true），则弹：标题 `验证码`，正文为 code（或 `来自 Companion`）。
- 「全部」模式下验证码类通知：以 `phone_notification` 的完整文案弹一次即可；`otp` 只进 Inbox，**避免双弹**。

### 3.4 Mac 设置入口

放在现有「登录助手 → 手机 Companion」区域下方，增加：

- 开关：**收到验证码时显示系统通知**（默认开）
- 开关：**接收手机通知镜像**（默认开；关闭后忽略 `phone_notification`，仍收 `otp`）
- 文案：说明系统通知图标为 MeoBrowser，来源看标题前缀
- 若未授权通知权限：按钮「打开系统通知设置」

---

## 4. 协议扩展（V2.1）

传输、发现、鉴权、帧格式不变。新增消息类型；`otp` 语义不变。

权威字段表同步维护于 [companion-protocol.md](companion-protocol.md)（V2.1 节）。

### 4.1 `phone_notification`（Android → Mac）

```json
{
  "v": 1,
  "type": "phone_notification",
  "deviceToken": "long-token",
  "id": "stable-dedupe-key",
  "packageName": "com.tencent.mm",
  "appLabel": "微信",
  "title": "张三",
  "body": "下午见面",
  "ts": 1710000000,
  "postTimeMs": 1710000000123,
  "flags": {
    "ongoing": false,
    "groupSummary": false
  }
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `deviceToken` | ✅ | 与 `otp` 相同鉴权 |
| `id` | ✅ | 去重键；建议 `{packageName}:{sbn.key}` 或 hash(package+title+body+postTime桶) |
| `packageName` | ✅ | Android 包名 |
| `appLabel` | 推荐 | `PackageManager` 应用名；失败可空 |
| `title` | 推荐 | `EXTRA_TITLE` |
| `body` | 推荐 | 由 text / bigText / textLines / subText 拼接 |
| `ts` | ✅ | Unix 秒；Mac 可做龄期校验 |
| `postTimeMs` | 可选 | 原始 `StatusBarNotification.postTime` |
| `flags` | 可选 | 供 Mac 二次过滤；Android 侧应已过滤 ongoing |

**大小限制**：

- `title` ≤ 200 字符；`body` ≤ 1000 字符；超出截断并加 `…`
- 整帧仍遵守 64 KiB 上限

### 4.2 `phone_notification_ok`（Mac → Android）

```json
{ "v": 1, "type": "phone_notification_ok", "id": "stable-dedupe-key" }
```

失败仍用现有 `error`：

```json
{ "v": 1, "type": "error", "message": "unauthorized" }
```

### 4.3 与 `otp` 的并存规则

| Android 模式 | 验证码类通知 | 普通通知 |
|--------------|--------------|----------|
| `otp_only` | 只发 `otp`（可选 Mac 侧自己弹验证码横幅） | 不发 |
| `all` | 先发 `phone_notification`，若解析出 code 再发 `otp` | 只发 `phone_notification` |

Mac：

- `otp` → 始终进 `OTPInbox`；系统横幅按 §3.3 策略。
- `phone_notification` → 鉴权通过后弹系统通知；**不**自动当 OTP 解析（避免重复逻辑；OTP 仍靠 Android 发 `otp`）。

### 4.4 龄期与鉴权

- `deviceToken` 校验同 `otp`。
- `ts` 与本地差默认 ≤ **300s**（通知可比验证码稍宽；过期可拒或仍展示——MVP：**过期仍展示但打日志**，避免时钟偏差丢消息）。
- 未配对连接直接 `error: unauthorized`。

---

## 5. Android 设计

### 5.1 模块职责

| 组件 | 职责 |
|------|------|
| `OtpNotificationListener` | 继续作为 `NotificationListenerService`；按模式分支 |
| `NotificationMirrorPrefs`（或并入 `PairingPrefs`） | 持久化 `otp_only` / `all` |
| `NotificationPayloadBuilder` | 从 `StatusBarNotification` 提取字段、截断、生成 `id` |
| `NotificationNoiseFilter` | ongoing / group summary / 空内容 / 自身包名 |
| `SmsOtpHandler` | 不变；`all` 模式下在推镜像后再尝试 OTP |
| `CompanionSession` | 新增 `pushPhoneNotification(...)` |

### 5.2 噪音过滤（全部模式）

跳过（不推送）当：

1. `sbn.packageName ==` 本应用包名  
2. `notification.flags & FLAG_ONGOING_EVENT`  
3. `notification.flags & FLAG_GROUP_SUMMARY`（若 API 可得）  
4. 提取后 `title` 与 `body` 皆空  
5. 优先级过低（可选：`IMPORTANCE_MIN` / `IMPORTANCE_NONE`，API 26+ 从 channel 读；读不到则忽略此条）  
6. 短时间重复：同一 `id` 在 **60s** 内已成功入队发送过

**不**在 MVP 按包名黑名单硬编码（留给二期白名单）。

### 5.3 字段提取

与现有 OTP 路径一致，拼 `body`：

```text
title, EXTRA_TEXT, EXTRA_BIG_TEXT, EXTRA_TEXT_LINES, EXTRA_SUB_TEXT
→ 去空白拼接
```

`appLabel`：

```text
pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0))
```

失败则空字符串。

### 5.4 去重 `id`

推荐：

```text
id = packageName + ":" + (sbn.key ?: (title.hash + ":" + body.hash + ":" + (postTimeMs / 5000)))
```

`sbn.key` 在支持的系统上最稳；否则用内容 + 5 秒时间桶，减少更新类通知刷屏。

### 5.5 仅验证码模式

保持现有 `handleSbn` 兴趣过滤 + `SmsOtpHandler`；**不**调用 `pushPhoneNotification`。

### 5.6 连接与前台服务

复用 `CompanionConnectionService` 保活；全部模式不额外要求新权限（通知使用权已有）。Android 13+ 的 `POST_NOTIFICATIONS` 仅影响 Companion 自己发通知，与监听无关。

---

## 6. Mac 设计

### 6.1 模块职责

| 组件 | 职责 |
|------|------|
| `CompanionChannel` | 解析 `phone_notification`，鉴权后交给 Presenter |
| `PhoneNotificationPresenter`（新） | 组装 `UNMutableNotificationContent` 并 deliver |
| `PhoneNotificationSettings`（新或并入 PairingStore） | 两个开关的 UserDefaults |
| 登录助手设置 UI | 开关 + 权限引导 |
| `OTPInbox` | **不改**核心语义；可选在 submit 成功后发通知（由 Presenter 统一） |

### 6.2 通知权限

- App 启动或首次收到镜像前：`requestAuthorization`（alert + sound）
- 拒绝时：设置页提示，不崩溃；消息可 ack 但跳过展示（或 ack 前仍 ok，避免 Android 重试风暴——MVP：**一律 `phone_notification_ok`，展示失败只打日志**）

### 6.3 标题组装伪代码

```text
label = appLabel.nonEmpty ? appLabel : (packageName.nonEmpty ? packageName : "手机通知")
if title.nonEmpty && title != label:
    displayTitle = "\(label) · \(title)"
else:
    displayTitle = label
bodyText = body.nonEmpty ? body : (title if title != label else "")
if bodyText.isEmpty: skip deliver
```

### 6.4 请求标识

```text
UNNotificationRequest.identifier = "phone-notif-" + id（截断至合理长度）
content.threadIdentifier = packageName
content.categoryIdentifier = "MEO_PHONE_NOTIFICATION"  // MVP 无自定义 action 也可预留
```

同一 `id` 重复 deliver：系统替换同 identifier 的通知，利于「通知更新」场景。

### 6.5 与登录助手 UI 的关系

- Companion 连接状态区保持原样。
- 新增镜像相关开关，避免新开独立窗口（MVP 控制面最小）。

---

## 7. 隐私与安全

| 项 | MVP 策略 |
|----|----------|
| 默认 | `otp_only`，只传验证码 |
| 全部模式 | 显式确认；首页常驻隐私提示 |
| 传输 | 同 V2：LAN 明文 + deviceToken |
| 日志 | Android/Mac 日志不打印完整 body（可打 package + 长度） |
| 存储 | Mac 不落盘通知正文；仅 UserDefaults 存开关 |
| 威胁 | 同网嗅探可见通知全文 → 文档与 UI 披露；加密列为二期 |

---

## 8. 失败与边界

| 情况 | 行为 |
|------|------|
| 通知使用权关闭 | 全部/验证码均无法从通知抓取；短信广播路径仍可能收 OTP |
| Listener 断开 | 沿用现有 rebind / 引导 |
| Mac 未授权通知 | 镜像静默跳过展示；OTP 填码不受影响 |
| 超长正文 | 截断 |
| 洪水通知 | 客户端 60s 同 id 去重；可考虑全局每秒最多 N 条（MVP：N=5，多余丢弃并记事件） |
| 旧版 Mac + 新版 Android | Mac 忽略未知 type（需确认现有解析是否安全忽略）；Android 对无 ack 不重试风暴 |
| 旧版 Android + 新版 Mac | 无镜像，仅 otp，兼容 |

**兼容性要求**：`CompanionChannel` 对未知 `type` 应安全忽略（若当前不是，MVP 一并修）。

---

## 9. 验收标准（MVP）

1. Companion 可切换「仅验证码 / 全部通知」，重启后模式保持。  
2. 仅验证码：行为与现网一致，登录助手仍能自动填码；不出现普通微信等镜像。  
3. 全部通知：微信/系统短信等普通通知在 Mac 通知中心出现，标题含 App 名（或包名）前缀。  
4. 全部模式下验证码通知：Mac 能填码，且系统通知不双弹（或符合 §3.3 定稿）。  
5. ongoing / 空内容 / 自身通知不推送。  
6. 未授予 Mac 通知权限时，填码仍可用；设置页有引导。  
7. 断开连接后新通知不丢到错误设备；重连后新通知恢复。  
8. 协议文档 V2.1 与实现一致。

---

## 10. 二期方向（非 MVP）

按优先级：

1. **精选 App 白名单**（比「全部」更适合日常）  
2. **应用内通知面板**（可显示真实图标列表与历史）  
3. **图标附件**（`UNNotificationAttachment`）  
4. **帧级加密**  
5. **断线缓存 / 补发**  
6. **Mac 勿扰联动、静音、点击跳转策略**

---

## 11. 架构示意

```text
┌─────────────────────────────┐         LAN JSON          ┌──────────────────────────────┐
│  Meo Companion (Android)    │  ───────────────────────► │  MeoBrowser (macOS)          │
│                             │                           │                              │
│  NotificationListener       │   otp                     │  CompanionChannel            │
│    ├─ otp_only → SmsOtp     │ ────────────────────────► │    ├─► OTPInbox → LoginAssist│
│    └─ all → Filter+Builder  │   phone_notification      │    └─► PhoneNotification     │
│         ├─ push mirror      │ ────────────────────────► │         Presenter            │
│         └─ maybe push otp   │                           │              │               │
│  CompanionConnectionService │ ◄──────────────────────── │         UNUserNotification   │
│                             │   *_ok / error            │         Center (标题前缀)      │
└─────────────────────────────┘                           └──────────────────────────────┘
```
