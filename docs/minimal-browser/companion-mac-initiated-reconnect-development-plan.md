# Mac 启动促成手机重连 — 开发计划（Cursor 可执行）

> 背景：Mac 开浏览器后常处于「等待手机」，而 Android 断线只重试一次，Mac 再上线时手机未必在扫。  
> 策略：**不翻转业务 TCP 角色**（Mac 仍为服务端）；先让手机持续等 Mac，再让 Mac 能主动 invite。  
> 协议基线：[companion-protocol.md](companion-protocol.md) · 工具栏语义：[companion-link-toolbar-mac-design.md](companion-link-toolbar-mac-design.md)  
> 状态：**MR-0～MR-3 已落地**；真机手测待勾选

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 业务通道 | 仍为 Mac Bonjour `_meologin._tcp` + TCP 服务端；鉴权仍用 `hello` / `deviceToken` |
| Mac 是否主动连业务端口 | **否**（不做角色对调） |
| 阶段 MR-1 | Android **指数退避持续重连**；已配对时断线不杀 FGS |
| 阶段 MR-2 | Mac 文案区分「待配对」vs「已配对等重连」；工具栏标题对齐 |
| 阶段 MR-3 | Mac 发现 `_meocompanion._tcp` 并发 `invite`；手机收 invite 后走现有 connect |
| 云推送 / 跨网 | **不做**（另立项） |
| iOS Companion | **不做** |

**首版交付：MR-1 + MR-2。** MR-3 为增强项，可同 PR 或紧随其后。

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase MR-0 | 文档与验收 | 完成 | 本计划；协议差分草案（MR-3） |
| Phase MR-1 | Android 持续重连 | 完成 | 退避调度；缓存失败后 Bonjour；保持前台「等待 Mac」 |
| Phase MR-2 | Mac 状态文案 | 完成 | `CompanionChannel` / `CompanionLinkUI` 已配对文案 |
| Phase MR-3 | Mac invite | 完成 | 手机广告 + Mac `nw_browser` + `invite` 消息 |
| Phase MR-4+ | 云唤醒 | 不做 | — |

---

## Phase MR-1 — Android 持续重连

### 目标

已配对（有 `deviceToken` 或安全码）且非用户主动断开时：

1. 断线 / 连接失败 → **指数退避重连**（约 0.5s → 1s → 2s → …，上限 **60s**）
2. **不**因单次失败 `stopSelf`（保持 FGS，文案「等待 Mac…」）
3. 连续失败若干次后强制 **Bonjour 再发现**（应对 Mac 临时端口 / IP 变化）
4. `hello_ok` 后清零退避计数

### 任务清单

- [x] **MR-1.1** `CompanionConnectionService`：引入 `reconnectGeneration` / `consecutiveFailures`；`scheduleReconnect` / `cancelReconnect`
- [x] **MR-1.2** `onPeerClosed`：改为 `scheduleReconnect`，去掉单次 `sleep(400)+connect`
- [x] **MR-1.3** `connectInternal` 失败：可持久重连时调度重试，否则才停 FGS
- [x] **MR-1.4** `resolveTarget`：支持 `forceRediscover`（优先 Bonjour，成功则写回 `lastHost/lastPort`）
- [x] **MR-1.5** `ACTION_DISCONNECT` / 用户断开：取消挂起重连；`hello_ok` 重置失败计数
- [x] **MR-1.6** 状态文案：`等待 Mac（Ns 后重试）` / `正在重连…` / 已连接保持不变

### 验收

- [ ] Mac 退出 → 手机显示等待重试且 FGS 仍在
- [ ] Mac 再打开（同 Wi‑Fi）→ **≤ 约 10～70s**（视退避进度）自动连上，无需点手机
- [ ] 用户点「断开」→ 不再自动重连，服务可停
- [ ] 未配对 → 行为与现网一致（失败可停）

---

## Phase MR-2 — Mac 状态文案

### 目标

用户打开 Mac 时，一眼区分「还要配对」和「已配对，等手机自己连上来」。

### 任务清单

- [x] **MR-2.1** `CompanionChannel.start`：启动后进入广告态并套用已配对文案（`applyAdvertisingStatusText`）
- [x] **MR-2.2** `CompanionLinkUI`：新增 `titleForChannel:`；已配对 + Waiting →「已配对，等待手机重连…」
- [x] **MR-2.3** 工具栏 / 设置页改用 `titleForChannel:`

### 验收

- [ ] 无配对设备：等待文案仍为待配对语义
- [ ] 有配对 hint：工具栏 / 设置卡片显示「已配对，等待手机重连…」
- [ ] 连上后仍为「已连接到手机」

---

## Phase MR-3 — Mac invite（增强）

### 协议差分（草案）

| 项 | 值 |
|----|-----|
| 手机广告类型 | `_meocompanion._tcp.` |
| 手机广告时机 | 已配对且允许自动连接时（与 FGS 同生命周期） |
| 消息 | `{ "v":1, "type":"invite", "from":"mac", "hostName":"…", "nonce":"…" }` |
| 鉴权 | invite **不含** token；手机收到后对 Mac sticky 端口发现有 `hello` |

### 任务清单

- [x] **MR-3.1** 更新 `companion-protocol.md`（服务发现 + `invite`）
- [x] **MR-3.2** Android：已配对时广告 `_meocompanion._tcp`；收 invite → `connectInternal`
- [x] **MR-3.3** Mac：`CompanionPhoneDiscovery`（`nw_browser`）；启动 / 点「邀请手机重连」时发 invite
- [x] **MR-3.4** 多设备：仅 invite 白名单 `deviceId`（服务名 `MeoC-<uuid>` / TXT）

### 验收

- [ ] 手机在后台、未主动 connect；开 Mac → 发现并 invite → 自动业务连接
- [ ] 未配对手机不广播 / 不响应
- [ ] 设置页「邀请手机重连」可手动触发
- [ ] 已连接时停止手机侧 `_meocompanion` 广告与 Mac 侧浏览

---

## 附录：手动验收（MR-1 + MR-2 + MR-3）

- [ ] 同 Wi‑Fi；已配对；Mac 杀进程再开 → 手机自动连上（退避或 invite）
- [ ] Mac 工具栏琥珀点 +「已配对，等待手机重连…」
- [ ] 手机设置关「启动自动连接」时：不因本改动强行常驻重连（可选：仅 `canAutoConnect` 为真时持续等）
- [ ] 安全码模式无 token 时仍可用安全码退避重连
- [ ] 手机在「等待 Mac」时广告 `_meocompanion`；Mac 开后主动 invite 连上
- [ ] 点「邀请手机重连」可立即触发一轮 invite
