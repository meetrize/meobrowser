# Meo Companion 协议（V2 / V2.1 / V3）

> MeoBrowser（Mac）↔ MeoCompanion / Android MeoBrowser：局域网 OTP、通知镜像、来电提醒与可选数据同步。  
> 传输：Bonjour `_meologin._tcp` + 长度前缀 JSON。  
> 同步设计：[companion-sync-design.md](companion-sync-design.md) · 通知镜像：[companion-notification-mirror-design.md](companion-notification-mirror-design.md) · 来电提醒：[companion-call-alert-feasibility-and-design.md](companion-call-alert-feasibility-and-design.md)

## 服务发现

| 项 | 值 |
|----|-----|
| 类型 | `_meologin._tcp.` |
| 名称 | `MeoBrowser`（可带主机后缀） |
| 端口 | **固定 sticky 端口**（首次启动写入 UserDefaults；仅用户在设置中确认「更换端口」后才变） |

Android 应缓存 `lastHost:lastPort`，依赖 sticky 端口做快速重连；Bonjour 作兜底发现。

## 帧格式

```text
uint32 big-endian length
UTF-8 JSON payload（length 字节）
```

单帧上限 64 KiB。

## 鉴权模式（Mac / Android 需一致）

| 模式 | 说明 |
|------|------|
| 临时配对码 | 6 位数字，5 分钟有效，成功后作废（一次性） |
| 固定安全码 | 用户自设 4～12 位字母/数字，可重复使用；适合日常自动连接 |

线协议统一使用 `pairingToken` 字段承载配对码或安全码；Mac 按当前鉴权模式解释。

## 消息

### hello（配对或重连）

```json
{ "v": 1, "type": "hello", "deviceId": "android-uuid", "pairingToken": "123456" }
```

或已配对：

```json
{ "v": 1, "type": "hello", "deviceId": "android-uuid", "deviceToken": "long-token" }
```

### hello_ok

```json
{ "v": 1, "type": "hello_ok", "deviceToken": "long-token", "hostName": "…" }
```

### otp

```json
{
  "v": 1,
  "type": "otp",
  "code": "123456",
  "ts": 1710000000,
  "senderHash": "optional-sha256-prefix",
  "deviceToken": "long-token"
}
```

### error

```json
{ "v": 1, "type": "error", "message": "invalid pairing" }
```

### phone_notification（V2.1，Android → Mac）

用户在 Companion 开启「全部通知」时发送。默认「仅验证码」模式**不**发送本消息。

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
| `deviceToken` | ✅ | 同 `otp` |
| `id` | ✅ | 去重 / 通知 request 标识 |
| `packageName` | ✅ | 来源包名 |
| `appLabel` | 推荐 | 应用显示名 |
| `title` / `body` | 推荐 | 截断：title ≤ 200，body ≤ 1000 字符 |
| `ts` | ✅ | Unix 秒 |
| `postTimeMs` | 可选 | 原始通知时间 |
| `flags` | 可选 | Android 侧应已过滤 ongoing |

Mac 展示：系统通知标题用 `appLabel`（及可选 `title`）前缀；**左侧图标仍为 MeoBrowser**（系统限制）。

### phone_notification_ok（V2.1，Mac → Android）

```json
{ "v": 1, "type": "phone_notification_ok", "id": "stable-dedupe-key" }
```

鉴权失败等仍用 `error`。Mac 即使因用户关闭镜像或未授权通知而跳过展示，也应回 `phone_notification_ok`，避免客户端重试风暴。

### 与 otp 的并存（V2.1）

| Android 模式 | 验证码类通知 | 普通通知 |
|--------------|--------------|----------|
| 仅验证码（默认） | 只发 `otp` | 不发 |
| 全部通知 | `phone_notification` + 若解析出码再发 `otp` | 只发 `phone_notification` |

Mac：未知 `type` 必须安全忽略。

### call_event（V2.2，Android → Mac）

用户在 Companion 开启「来电提醒」且已授予 Call Screening 时发送。默认关闭。

```json
{
  "v": 1,
  "type": "call_event",
  "deviceToken": "long-token",
  "id": "call-uuid-or-stable-key",
  "state": "ringing",
  "number": "+8613812345678",
  "numberRaw": "13812345678",
  "presentation": "allowed",
  "contactName": "张三",
  "ts": 1710000000,
  "eventMs": 1710000000123
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `deviceToken` | ✅ | 同 `otp` |
| `id` | ✅ | 同一次通话稳定 id（响铃生成，挂断前不变） |
| `state` | ✅ | `ringing` \| `active` \| `ended` \| `missed` |
| `number` | 推荐 | E.164；未知可空 |
| `numberRaw` | 可选 | 原始显示串 |
| `presentation` | 可选 | `allowed` \| `restricted` \| `unknown` \| `payphone` |
| `contactName` | 可选 | 通讯录匹配名（后期）；MVP 可空 |
| `ts` | ✅ | Unix 秒 |
| `eventMs` | 可选 | 毫秒时间戳 |

Mac：系统通知 + 浏览器跨窗来电条；类型文案由 Mac 本地轻量规则表计算。无黑名单/拒接字段。

### call_event_ok（V2.2，Mac → Android）

```json
{ "v": 1, "type": "call_event_ok", "id": "call-uuid-or-stable-key" }
```

鉴权失败用 `error`。即使用户关闭来电提醒或未授权通知，Mac 也应回 `call_event_ok`。

## V3 同步消息（快捷方式 / 历史 / 书签）

> 设计详见 [companion-sync-design.md](companion-sync-design.md)。所有 sync_* 须带有效 `deviceToken`。单帧 ≤ 64 KiB，超出用 `sync_chunk`。

| type | 说明 |
|------|------|
| `sync_hello` | 交换 deviceId、supportedKinds、epoch |
| `sync_pull` | `kind` + `sinceEpoch` |
| `sync_push` | `kind` + `records[]` + `epoch` |
| `sync_chunk` | 分片：`transferId`、`index`、`total`、`payload` |
| `sync_ack` | `kind` + `appliedEpoch` |
| `sync_error` | `message` |

`kind`：`shortcut` | `history` | `bookmark`。冲突：记录级 LWW（`updatedAt`，平局比 `deviceId`）。删除用 `deleted` tombstone。

预留：`qr_image`。

## 配对规则

1. **临时配对码**：Mac 生成 6 位数字 `pairingToken`，默认有效 5 分钟，可刷新；校验通过后签发长期 `deviceToken` 并清除 pending 码。  
2. **固定安全码**：用户在 Mac / Android 设定相同安全码；`pairingToken` 与安全码匹配即签发/更新 `deviceToken`，**安全码不清除**。Android 在安全码模式下打开 App 应默认自动连接。  
3. 之后 `otp` / `phone_notification` / `call_event` 必须带有效 `deviceToken`。  
4. Mac「注销设备」删除 token；临时配对码需重新配对，安全码模式可用同一安全码再次连接。

## OTP 接受规则（Mac `OTPInbox`）

- `code` 为 4～8 位数字  
- `ts` 与本地时间差默认 ≤ 120s（亦可用接收时刻作龄期）  
- 同一 `code` 只消费一次  
- 来源标记：`companion` / `paste` / `clipboard` / `mock`

## 安全说明（V2 / V2.1）

- 通道为同 Wi‑Fi 明文 JSON + 设备 token；防 LAN 外随意推码。  
- 已知局限：同网嗅探可见验证码；开启「全部通知」时同网可嗅探通知正文——须用户显式确认。  
- 后续可升级帧级 AES-GCM。  
- 不做公有强制托管；外出场景见自建 WS 模板（另文）。
