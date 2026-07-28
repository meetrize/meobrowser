# 自建多应用云端同步 — 最低预算方案

> 目标：在**不依赖 Apple Developer / CloudKit** 的前提下，用**最低预算、最少运维**提供可复用的云端同步后端；**先服务 MeoBrowser**（快捷方式 + 表单备忘），同一套服务可挂接其他应用。  
> 状态：设计草案（未实现）  
> 关联：[cloud-sync-design.md](cloud-sync-design.md)（CloudKit 方案，已有客户端 SyncCore）· [companion-sync-design.md](companion-sync-design.md) · [site-form-memo-design.md](site-form-memo-design.md)

---

## 1. 一句话结论

**推荐：PocketBase（单二进制 + SQLite）自托管，前面可套 Cloudflare Tunnel / 廉价 VPS。**  

客户端**复用已有 SyncCore（SyncRecord + LWW）**，只换传输层：`CloudKitTransport` → `MeoServerSyncTransport`（HTTPS JSON）。  
多应用用同一张 `sync_records` 表 + `app_id` 字段隔离，零第二套协议。

预算量级：**约 ¥0～30/月**（免费试用 / 最小云主机 / 家里闲置机器 + Tunnel）。

---

## 2. 为什么不继续只靠 CloudKit

| 问题 | 说明 |
|------|------|
| 门槛 | 需付费 Apple Developer（约 $99/年）+ 正式签名 |
| 生态 | 难服务 Android / 非 Apple 应用 |
| 产品 | 你已明确要「自建、多应用共用」 |

CloudKit 方案文档仍保留作 Apple 用户可选通道；**自建通道与之并列**，用户可二选一或都关。

---

## 3. 候选对比（最低预算优先）

| 方案 | 复杂度 | 月费量级 | 多应用 | 结论 |
|------|--------|----------|--------|------|
| **PocketBase** | 极低：一个二进制 + Admin UI | ¥0～30（VPS/闲置机） | collection / `app_id` | **首选** |
| Cloudflare Workers + D1 | 低：无服务器进程 | 免费额度通常够用 | 表内 `app_id` | 备选（更省运维） |
| Supabase 免费层 | 中：托管 Postgres | $0（有限额） | schema / RLS | 可，但比 PB 重 |
| 自写 Go/Node + Postgres | 高 | VPS + 自己写 CRUD/鉴权 | 自由 | **不做**（过度） |
| Firebase | 中 | 免费层 | 项目隔离 | 可，但厂商绑定 |

**定稿：PocketBase。**  
理由：安装 1 条命令、自带用户鉴权 / REST / 实时订阅 / 管理后台；MeoBrowser 用 `NSURLSession` 调 REST 即可，无需 ObjC SDK。

---

## 4. 总架构

```
┌─────────────┐   HTTPS JSON    ┌──────────────────────────────┐
│ MeoBrowser  │ ──────────────► │ PocketBase                   │
│ SyncCore    │ ◄────────────── │  users + sync_records        │
│ + ServerTx  │                 │  (app_id 隔离多应用)           │
└─────────────┘                 └──────────────┬───────────────┘
                                               │ 同库
┌─────────────┐                                │
│ 其他 App    │ ───────────────────────────────┘
│ (同协议)    │
└─────────────┘
```

与现有通道关系：

| 通道 | 用途 |
|------|------|
| Companion LAN | 同 Wi‑Fi Mac↔Android |
| CloudKit（可选） | 有 Apple 开发者签名时 |
| **本方案 Server Sync** | 无 CloudKit、多应用、跨平台 |

三者共用 **SyncRecord + LWW**；传输互不替代。

---

## 5. 数据模型（多应用通用）

### 5.1 集合 `sync_records`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | text（主键） | 建议：`{app_id}:{record_id}` 或 PB 自动 id + 唯一索引 `(user, app_id, record_id)` |
| `user` | relation → users | 所属账号 |
| `app_id` | text | 应用标识，如 `meobrowser`、`notes`、`todo` |
| `record_id` | text | 业务 UUID（shortcut itemID / memoID） |
| `kind` | text | `shortcut` / `form_memo` / … |
| `updated_at` | number | Unix 秒，LWW |
| `device_id` | text | 写入设备 |
| `deleted` | bool | tombstone |
| `schema_version` | number | 默认 1 |
| `payload` | json | 业务字段 |

**唯一约束**：`(user, app_id, record_id)`。

**API 规则（API Rules 示例）**：

- list/view/create/update/delete：仅 `user = @request.auth.id`
- 可选：再限制 `app_id` 白名单（防乱写）

### 5.2 MeoBrowser 的 `app_id` / `kind`

| app_id | kind | 首版 |
|--------|------|------|
| `meobrowser` | `shortcut` | ✅ |
| `meobrowser` | `form_memo` | ✅ |
| `meobrowser` | `bookmark` / `history` / `prefs` | 后期 |

payload 与 [cloud-sync-design.md](cloud-sync-design.md) §5 / §5.1 **完全一致**，客户端桥接可复用 `CloudSyncShortcutBridge` / `CloudSyncFormMemoBridge`。

### 5.3 其他应用如何接入（预留）

新应用只需：

1. 约定自己的 `app_id`（如 `meonotes`）  
2. 定义若干 `kind` + payload schema  
3. 客户端实现：本地 Store ↔ SyncRecord ↔ 同一 REST  

**服务端零改表**（或最多加 API Rule）。

---

## 6. 同步协议（尽量简单）

不做 OT/CRDT；与现有一致：**客户端 LWW 合并，服务端只做存取**。

### 6.1 鉴权

- PocketBase 内置 email/password（首版）  
- Token 存 Mac Keychain  
- 后期可选：magic link、OAuth  

### 6.2 拉取

```
GET /api/collections/sync_records/records
  ?filter=(app_id='meobrowser' && updated_at>={since})
  &perPage=200
```

或首版更粗暴：**全量拉该 app 下当前用户全部记录**（快捷方式+备忘通常 &lt; 几千条，可接受）。

### 6.3 推送

对每条本地胜出记录：

```
PUT/PATCH 或 upsert：按 (app_id, record_id) 更新
```

PocketBase 无原生 upsert 时：先 list by filter，有则 PATCH，无则 POST。客户端可批量串行/小并发。

### 6.4 删除

写 `deleted=true` + 刷新 `updated_at`（tombstone）；30 天后客户端可请求物理删，或服务端定时清理。

### 6.5 触发（对齐现有 Engine）

1. 登录且开关开 → pull + merge + push  
2. 本地变更 debounce 2～5s → push  
3. 「立即同步」→ 全量 pull/merge/push  
4. 前台恢复 → 轻量 sync  

---

## 7. 部署：最低预算路径

### 路径 S0 — 几乎免费（推荐先跑通）

| 项 | 做法 |
|----|------|
| 机器 | 家里 Mac mini / 旧 PC / 树莓派，或免费云试用 |
| 进程 | `./pocketbase serve --http=127.0.0.1:8090` |
| 公网 | **Cloudflare Tunnel**（免费）→ `https://sync.你的域名` |
| HTTPS | Tunnel 自带 |
| 备份 | 每天拷贝 `pb_data/` 到对象存储 / 另一盘 |

月费：**域名（可选）+ 电费**；无域名可用 Tunnel 临时 hostname 开发。

### 路径 S1 — 最省事付费

| 项 | 做法 |
|----|------|
| VPS | 1 核 1G（甲骨文免费层 / 搬瓦工 / 轻量云等）约 ¥0～30/月 |
| 反向代理 | Caddy 或 Nginx + Let’s Encrypt |
| 备份 | cron + `pb_data` 打包 |

### 路径 S2 — 更零运维备选

Cloudflare Workers + D1：无 PocketBase Admin，需自己写薄 API；适合你熟悉 CF 生态时再迁。

**首版选 S0 或 S1 + PocketBase。**

---

## 8. MeoBrowser 客户端改动（最小）

在现有 CloudSync 旁加 **Server Sync** 通道（勿拆掉 SyncCore）：

```
SimpleBrowser/ServerSync/
├── ServerSyncSettings.h/.m     # 服务器 URL、开关、账号
├── ServerSyncAuth.h/.m         # login / token（Keychain）
├── ServerSyncTransport.h/.m    # REST pull/push
└── （复用 CloudSyncEngine 模式或抽 SyncEngine 共用）
```

设置页新增分区 **「Meo 云同步」**（与「iCloud 同步」并列）：

- 服务器地址（默认可空，填 `https://sync.example.com`）  
- 登录 / 注册  
- 总开关；shortcut / form_memo 分项（默认同 CloudKit 方案）  
- 立即同步 / 上次时间  

**无服务器、未登录：本地照常，不崩溃**（已有 Capability 思路可复用）。

---

## 9. 安全与隐私（够用即可）

| 项 | 定稿 |
|----|------|
| 传输 | HTTPS 必须（Tunnel / Caddy） |
| 隔离 | 每用户只能读写自己的 records |
| 密码 | 不进同步（与现有产品边界一致） |
| Cookie | 不同步 |
| 备忘明文 | 进你的服务器；设置页明示 |
| 备份 | `pb_data` 加密或私有桶 |
| 多租户应用 | `app_id` 隔离；不要共享 payload schema |

首版**不做**端到端加密（可 P2：客户端加密 payload，服务端只存密文）。

---

## 10. 费用与容量粗算

| 场景 | 估算 |
|------|------|
| 单用户 MeoBrowser | 快捷方式+备忘 &lt; 5 MB |
| 100 用户 | 通常仍 &lt; 1 GB SQLite，轻松 |
| PocketBase | 免费开源 |
| Cloudflare Tunnel | 免费 |
| 小 VPS | 可选 ¥0～30/月 |

对比：Apple Developer **$99/年** 仅换 CloudKit 签名；自建更适合「多应用 + 无苹果账号门槛」。

---

## 11. 分阶段落地（先本应用）

| 阶段 | 内容 | 预估 |
|------|------|------|
| **SS-0** | 本地方案定稿；本机跑 PocketBase；建 `sync_records` + Rules | 0.5 日 |
| **SS-1** | Tunnel / 域名；注册登录通；手测 REST upsert | 0.5～1 日 |
| **SS-2** | MeoBrowser：`ServerSyncTransport` + 设置 UI；复用 Shortcut/FormMemo 桥 | 2～3 日 |
| **SS-3** | 立即同步、错误态、备份脚本；验收两台 Mac | 1 日 |
| **SS-4** | 文档：第二应用接入 checklist | 0.5 日 |

**MVP = SS-0～SS-3**：两台电脑用同一账号对齐快捷方式与表单备忘。

---

## 12. 验收（MeoBrowser MVP）

- [ ] 未配置服务器时打开设置不崩溃  
- [ ] 注册/登录后可同步 shortcut + form_memo  
- [ ] A 机改 → B 机拉齐（秒～分钟级）  
- [ ] 删除走 tombstone  
- [ ] 关开关后不再上传  
- [ ] Keychain / Cookie 不上传  
- [ ] Admin 可见 `app_id=meobrowser` 记录；换账号不可见他人数据  

---

## 13. 明确不做（保持简单）

- 自研完整账号/计费中台  
- 多区域多活、Kafka、微服务  
- 首版端到端加密  
- 首版把 Companion 通知/OTP 上云  
- 首版历史/书签（可后加 kind）  

---

## 14. 与 CloudKit 方案的关系

| | CloudKit | 本方案（PocketBase） |
|--|----------|----------------------|
| 签名 | 需 Apple Developer | 不需要 |
| 多应用 | 弱（偏 Apple 生态） | 强（`app_id`） |
| Android | 难 | 易（同一 REST） |
| 运维 | 零 | 极低（单二进制） |
| 客户端内核 | SyncCore | **同一套 SyncCore** |

建议产品叙事：

> **Meo 云同步**（自建，跨应用）为默认云通道；  
> **iCloud 同步**为可选（有开发者账号时）。

---

## 15. 下一步

1. 本机安装 PocketBase，建集合与 Rules（SS-0）  
2. 出 Cursor 开发计划 `server-sync-development-plan.md` / `.cursor/plans/server-sync.plan.md`  
3. 实现 MeoBrowser `ServerSync*` 传输层，复用现有桥接  

**一句话**：最低预算 = **PocketBase +（Tunnel 或小 VPS）+ 复用 SyncCore**；先打通 MeoBrowser 两个 kind，其他应用只加 `app_id`。
