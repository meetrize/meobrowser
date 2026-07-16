# Meo Companion 协议（V2）

> MeoBrowser（Mac）↔ MeoCompanion（Android）局域网推送 OTP。  
> 传输：Bonjour `_meologin._tcp` + 长度前缀 JSON。  
> 隐私：只传验证码与时间戳（及可选发件人 hash），不传短信全文。

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

预留：`qr_image`（V3）。

## 配对规则

1. **临时配对码**：Mac 生成 6 位数字 `pairingToken`，默认有效 5 分钟，可刷新；校验通过后签发长期 `deviceToken` 并清除 pending 码。  
2. **固定安全码**：用户在 Mac / Android 设定相同安全码；`pairingToken` 与安全码匹配即签发/更新 `deviceToken`，**安全码不清除**。Android 在安全码模式下打开 App 应默认自动连接。  
3. 之后 `otp` 必须带有效 `deviceToken`。  
4. Mac「注销设备」删除 token；临时配对码需重新配对，安全码模式可用同一安全码再次连接。

## OTP 接受规则（Mac `OTPInbox`）

- `code` 为 4～8 位数字  
- `ts` 与本地时间差默认 ≤ 120s（亦可用接收时刻作龄期）  
- 同一 `code` 只消费一次  
- 来源标记：`companion` / `paste` / `clipboard` / `mock`

## 安全说明（V2 首版）

- 通道为同 Wi‑Fi 明文 JSON + 设备 token；防 LAN 外随意推码。  
- 已知局限：同网嗅探可见验证码；后续可升级帧级 AES-GCM。  
- 不做公有强制托管；外出场景见自建 WS 模板（另文）。
