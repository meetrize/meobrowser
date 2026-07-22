# Meo Companion 协议（V2 / V2.1 / V2.2 / V2.3 / V3）

> MeoBrowser（Mac）↔ MeoCompanion / Android MeoBrowser：局域网 OTP、通知镜像、来电提醒、App 图标、可选微信侧栏回复（WR）与数据同步。  
> 传输：Bonjour `_meologin._tcp` + 长度前缀 JSON。  
> 同步设计：[companion-sync-design.md](companion-sync-design.md) · 通知镜像：[companion-notification-mirror-design.md](companion-notification-mirror-design.md) · 来电提醒：[companion-call-alert-feasibility-and-design.md](companion-call-alert-feasibility-and-design.md) · App 图标：[companion-notification-app-icon-design.md](companion-notification-app-icon-design.md) · 微信回复：[companion-wechat-sidebar-reply-design.md](companion-wechat-sidebar-reply-design.md)

## 服务发现

| 项 | 值 |
|----|-----|
| 类型（Mac 业务） | `_meologin._tcp.` |
| 名称（Mac） | `MeoBrowser`（可带主机后缀） |
| 端口（Mac） | **固定 sticky 端口**（首次启动写入 UserDefaults；仅用户在设置中确认「更换端口」后才变） |
| 类型（手机 invite） | `_meocompanion._tcp.` |
| 名称（手机） | `MeoC-<deviceId>`（`deviceId` 为 Android 侧稳定 UUID） |
| TXT（手机，可选） | `deviceId=<uuid>` |

Android 应缓存 `lastHost:lastPort`，依赖 sticky 端口做快速重连；Bonjour 作兜底发现。

**重连（客户端）**：已配对且开启自动连接时，Android 在 Mac 不可达时应**指数退避持续重试**（上限约 60s），并周期性 Bonjour 再发现；不要在单次失败后退出前台服务。详见 [companion-mac-initiated-reconnect-development-plan.md](companion-mac-initiated-reconnect-development-plan.md)。

**Mac 主动 invite（MR-3）**：手机在「已配对且未连上 Mac」时广告 `_meocompanion._tcp`；Mac 浏览到已配对 `deviceId` 后，向该端口发一帧 `invite`（不含 token）。手机收到后立即按现有逻辑连接 `_meologin._tcp` 并 `hello`。业务通道角色不变（Mac 仍为服务端）。

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

### invite（V2.4，Mac → Android，唤醒用）

Mac 发现 `_meocompanion._tcp` 后建立短连接发送；**不含** `deviceToken` / 配对码。

```json
{
  "v": 1,
  "type": "invite",
  "from": "mac",
  "hostName": "MeoBrowser-on-MacBook",
  "nonce": "uuid",
  "deviceId": "optional-target-android-uuid"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `from` | ✅ | 固定 `"mac"` |
| `hostName` | 推荐 | 展示用 |
| `nonce` | 推荐 | 去重；手机可忽略 |
| `deviceId` | 推荐 | 目标手机；与广告名不一致时可忽略本帧 |

手机处理：若已连接则忽略；否则取消当前退避，立即发现/连接 Mac 并 `hello`。可不回包（短连接随即关闭）。

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
| `packageName` | ✅ | 来源包名（厂商代理时尽量归因到真实 App） |
| `appLabel` | 推荐 | 应用显示名；优先 `EXTRA_SUBSTITUTE_APP_NAME` |
| `title` / `body` | 推荐 | 截断：title ≤ 200，body ≤ 1000 字符 |
| `ts` | ✅ | Unix 秒 |
| `postTimeMs` | 可选 | 原始通知时间 |
| `flags` | 可选 | Android 侧应已过滤 ongoing |
| `iconPngBase64` | 可选 | 代理包无法归因时附带的通知自带 PNG（无前缀；解码后 ≤ 12 KiB） |
| `iconHash` | 可选 | 与 `app_icon` 相同算法；有 `iconPngBase64` 时必填 |
| `iconWidth` / `iconHeight` | 可选 | 像素边长 |

Mac 展示：系统通知标题用 `appLabel`（及可选 `title`）前缀；**系统横幅左侧图标仍为 MeoBrowser**（系统限制）。侧栏：有条目 `iconPngBase64` 时优先用该图标，否则用 `packageName` → `app_icon` 缓存。

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

### app_icon（V2.3，Android → Mac）

侧栏等 UI 按 `packageName` 缓存应用小图标。与 `phone_notification` **分开发送**；不修改通知帧结构。

```json
{
  "v": 1,
  "type": "app_icon",
  "deviceToken": "long-token",
  "packageName": "com.tencent.mm",
  "appLabel": "微信",
  "iconHash": "a1b2c3d4e5f67890",
  "mime": "image/png",
  "width": 72,
  "height": 72,
  "pngBase64": "<base64…>",
  "ts": 1710000000
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `deviceToken` | ✅ | 同 otp |
| `packageName` | ✅ | 缓存主键 |
| `appLabel` | 推荐 | 应用显示名 |
| `iconHash` | ✅ | `hex(SHA-256(pngBytes) 前 8 字节)`，16 个 hex 字符 |
| `mime` | ✅ | 固定 `image/png` |
| `width` / `height` | ✅ | 像素边长（优先 72，超 12 KiB 可降 48） |
| `pngBase64` | ✅ | 无前缀；解码后 ≤ 12 KiB |
| `ts` | ✅ | Unix 秒 |

Mac：校验鉴权与 PNG；成功落盘后回 `app_icon_ok`；失败回 `error`（Android 对本会话该 package 不再重试）。日志禁止打印 base64。

### app_icon_ok（V2.3，Mac → Android）

```json
{ "v": 1, "type": "app_icon_ok", "packageName": "com.tencent.mm", "iconHash": "a1b2c3d4e5f67890" }
```

IC-MVP：某 package 在当前 TCP 会话首次发 `phone_notification` 前推送 `app_icon`。跨会话 `app_icon_need` 为后续阶段。

### wechat_reply（WR，Mac → Android）

> 设计：[companion-wechat-sidebar-reply-design.md](companion-wechat-sidebar-reply-design.md)。**实验能力**：手机须开启 Companion「微信回复」开关，并授予无障碍（手势/剪贴板）；优先用通知 `contentIntent` 打开会话。

```json
{
  "v": 1,
  "type": "wechat_reply",
  "deviceToken": "long-token",
  "requestId": "uuid",
  "contact": "平安喜乐",
  "text": "测试自动发送",
  "notificationId": "optional-phone_notification-id",
  "packageName": "com.tencent.mm"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `deviceToken` | ✅ | 同 otp |
| `requestId` | ✅ | 关联 ok/err；Mac 生成 |
| `contact` | ✅ | 侧栏通知 `title`（显示名）；≤ 64 字 |
| `text` | ✅ | 回复正文；≤ 1000 字 |
| `notificationId` | 可选 | 对应 `phone_notification.id`，便于 Mac 标已回复 |
| `packageName` | 可选 | MVP 仅接受 `com.tencent.mm`（缺省视为微信） |

Android：未知/关闭实验开关/无障碍未就绪时回 `wechat_reply_err`。同时只处理一条（忙则 `busy`）。硬限约 20s。

### wechat_reply_ok（WR，Android → Mac）

```json
{
  "v": 1,
  "type": "wechat_reply_ok",
  "deviceToken": "long-token",
  "requestId": "uuid",
  "contact": "平安喜乐",
  "elapsedMs": 4200
}
```

### wechat_reply_err（WR，Android → Mac）

```json
{
  "v": 1,
  "type": "wechat_reply_err",
  "deviceToken": "long-token",
  "requestId": "uuid",
  "code": "disabled|a11y_required|contact_not_found|paste_failed|send_failed|wechat_not_installed|busy|timeout|invalid",
  "message": "人可读说明"
}
```

| code | 含义 |
|------|------|
| `disabled` | 手机未开「微信回复」实验开关 |
| `a11y_required` | Companion 无障碍服务未开启 |
| `contact_not_found` | 无法打开对应会话（无缓存通知 Intent 且无法搜索） |
| `paste_failed` / `send_failed` | 粘贴或发送步骤失败 |
| `wechat_not_installed` | 未安装微信 |
| `busy` | 已有回复任务在执行 |
| `timeout` | 超过时限 |
| `invalid` | 参数非法 |

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
3. 之后 `otp` / `phone_notification` / `call_event` / `app_icon` / `wechat_reply` 必须带有效 `deviceToken`。  
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
