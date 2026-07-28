# Meo 云同步（PocketBase）— 完整方案

> 目标：用 **PocketBase（单二进制 + SQLite）** 提供可复用的多应用云端同步；**首版打通 MeoBrowser**（快捷方式 + 表单备忘）；不依赖 Apple Developer / CloudKit。  
> 状态：**已落地（2026-07-28）** — PocketBase + `SimpleBrowser/ServerSync/`；CloudKit 模块已移除。公网实例细节见本地私密文档 `docs/local/pocketbase-deploy.local.md`（gitignore）。  
> 开发计划：[server-sync-development-plan.md](server-sync-development-plan.md) · Cursor：[.cursor/plans/server-sync.plan.md](../../.cursor/plans/server-sync.plan.md)  
> 服务端脚手架：[`server/pocketbase/`](../../server/pocketbase/)  
> 关联：[cloud-sync-design.md](cloud-sync-design.md)（归档） · [companion-sync-design.md](companion-sync-design.md) · [site-form-memo-design.md](site-form-memo-design.md)

---

## 0. 一句话

**服务端 = PocketBase；客户端 = 复用 SyncCore + 新 ServerSync 传输层；多应用 = 同一张 `sync_records` + `app_id`。**

预算：本机 / Tunnel 可接近 ¥0；小 VPS 约 ¥0～30/月。无需 $99 Apple 年费即可异地同步。

---

## 1. 范围与边界

### 1.1 做

| 层 | 内容 |
|----|------|
| 服务端 | PocketBase 安装、集合、API Rules、备份、本机/Tunnel/VPS 部署 |
| MeoBrowser | 注册登录、HTTPS 同步 shortcut + form_memo、设置 UI |
| 多应用 | 协议与表结构一次定好，第二应用只加 `app_id` |

### 1.2 不做（首版）

- 自研账号中台 / 计费  
- 端到端加密  
- 历史 / 书签 / Cookie / 密码上云  
- Companion 通知 / OTP 上云  
- CloudKit 双通道（已从客户端移除，仅保留本文档归档）

### 1.3 与现有通道

| 通道 | 角色 |
|------|------|
| Companion LAN | 同 Wi‑Fi Mac↔Android |
| **Meo 云同步（本文）** | 跨设备云通道（当前唯一云同步） |

二者共用 **SyncRecord + LWW**（`SimpleBrowser/SyncCore/`）。

---

## 2. 总架构

```
                    ┌─────────────────────────────────────┐
                    │  PocketBase                         │
                    │  ┌─────────┐  ┌──────────────────┐  │
 HTTPS JSON         │  │ users   │  │ sync_records     │  │
┌──────────────┐    │  │ email   │  │ app_id + kind    │  │
│ MeoBrowser   │◄──►│  │ token   │  │ payload JSON     │  │
│ SyncCore     │    │  └─────────┘  └──────────────────┘  │
│ ServerSync*  │    └─────────────────────────────────────┘
└──────────────┘              ▲
                              │ 同一 REST
                    ┌─────────┴─────────┐
                    │ 未来 App B / C     │
                    │ app_id=meonotes…  │
                    └───────────────────┘
```

**服务端职责**：鉴权、按用户隔离存取、可选实时订阅。  
**客户端职责**：导出本地 → 与远端 LWW 合并 → 写回本地 → 上传胜出记录。  
**服务端不做冲突算法**（保持简单）。

---

## 3. 服务端设计

### 3.1 为什么选 PocketBase

| 点 | 说明 |
|----|------|
| 交付物 | 一个可执行文件 + `pb_data/` 目录 |
| 自带 | 用户系统、Admin UI、REST、Realtime、文件（暂不用） |
| 客户端 | ObjC `NSURLSession` 即可，无官方 macOS SDK 依赖 |
| 备份 | 拷贝 `pb_data/` |

下载：[https://pocketbase.io/docs/](https://pocketbase.io/docs/)（选对应 OS/CPU，如 macOS arm64 / Linux amd64）。

### 3.2 目录约定（仓库内）

```
server/pocketbase/
├── README.md                 # 运维说明（本文 §3/§4 摘要）
├── scripts/
│   ├── download.sh           # 下载对应平台二进制
│   ├── serve-dev.sh          # 本机开发启动
│   ├── backup.sh             # 备份 pb_data
│   └── setup-collections.md  # Admin 建表检查清单
├── config/
│   ├── Caddyfile.example     # VPS 反代示例
│   ├── cloudflared.example.yml
│   └── meo-pocketbase.service.example  # systemd
└── pb_data/                  # .gitignore；运行时数据，勿提交密钥
```

二进制可不入库：用 `download.sh` 拉到 `server/pocketbase/bin/pocketbase`。

### 3.3 集合：`sync_records`

在 Admin UI（首次 `./pocketbase serve` 后浏览器打开提示的地址，一般是 `http://127.0.0.1:8090/_/`）创建 **Base collection**。

| 字段名 | 类型 | 必填 | 索引 / 约束 | 说明 |
|--------|------|------|-------------|------|
| `user` | Relation → `users` | 是 | 是 | 所属用户 |
| `app_id` | Text | 是 | 复合唯一 | 如 `meobrowser` |
| `record_id` | Text | 是 | 复合唯一 | 业务 UUID |
| `kind` | Text | 是 | 建议索引 | `shortcut` / `form_memo` |
| `updated_at` | Number | 是 | 建议索引 | Unix 秒 |
| `device_id` | Text | 是 | | 设备 id |
| `deleted` | Bool | 是 | | 默认 false |
| `schema_version` | Number | 是 | | 默认 1 |
| `payload` | JSON | 是 | | 业务体 |

**唯一索引**：`(user, app_id, record_id)` —— Admin → 集合 → Indexes 添加 unique。

PocketBase 主键 `id` 用系统自动 id 即可；业务键是 `(app_id, record_id)`。客户端 upsert 时：

1. `GET .../records?filter=(app_id='meobrowser' && record_id='{uuid}')&perPage=1`  
2. 有则 `PATCH /api/collections/sync_records/records/{pb_id}`  
3. 无则 `POST /api/collections/sync_records/records`

### 3.4 API Rules（必须）

集合 `sync_records` → API Rules（PocketBase 语法，以实际版本为准）：

| 操作 | Rule |
|------|------|
| List / View | `@request.auth.id != "" && user = @request.auth.id` |
| Create | `@request.auth.id != "" && user = @request.auth.id` |
| Update | `@request.auth.id != "" && user = @request.auth.id` |
| Delete | `@request.auth.id != "" && user = @request.auth.id` |

可选加严（防乱写 app）：

```
@request.auth.id != "" && user = @request.auth.id && app_id ~ '^(meobrowser)$'
```

第二应用接入时把正则扩成 `meobrowser|meonotes`。

`users` 集合：保持 PocketBase 默认（用户只能改自己资料）；**关闭公开 List**。

### 3.5 Auth

| 项 | 定稿 |
|----|------|
| 方式 | Email + Password（PB 内置） |
| 注册 | `POST /api/collections/users/records` |
| 登录 | `POST /api/collections/users/auth-with-password` |
| Token | 响应 `token`；客户端放 Keychain；请求头 `Authorization: {token}` |
| 刷新 | 用 auth-refresh；过期则要求重新登录 |

首版不做邮箱验证（私有服务器可关）；若公网开放，建议在 Admin 打开验证或限制注册。

### 3.6 REST 契约（MeoBrowser 用）

**Base URL**：用户配置，如 `https://sync.example.com`（无尾斜杠）。

#### 登录

```http
POST /api/collections/users/auth-with-password
Content-Type: application/json

{"identity":"user@example.com","password":"***"}
```

响应关键字段：`token`、`record.id`。

#### 注册

```http
POST /api/collections/users/records
Content-Type: application/json

{"email":"user@example.com","password":"***","passwordConfirm":"***"}
```

注册后立刻再调登录拿 token。

#### 拉取（全量，首版）

```http
GET /api/collections/sync_records/records?filter=(app_id='meobrowser')&perPage=500&skipTotal=1
Authorization: <token>
```

分页：若 `totalItems`/`items` 满页，用 `page=2…` 直至取完。

增量（可选优化）：

```
filter=(app_id='meobrowser' && updated_at>={since})
```

#### 创建

```http
POST /api/collections/sync_records/records
Authorization: <token>
Content-Type: application/json

{
  "user": "<auth_user_id>",
  "app_id": "meobrowser",
  "record_id": "uuid",
  "kind": "shortcut",
  "updated_at": 1710000000,
  "device_id": "mac-...",
  "deleted": false,
  "schema_version": 1,
  "payload": { ... }
}
```

#### 更新

```http
PATCH /api/collections/sync_records/records/<pb_id>
Authorization: <token>
Content-Type: application/json

{ "updated_at": ..., "device_id": "...", "deleted": false, "payload": { ... } }
```

#### 记录 JSON ↔ SyncRecord

| PB 字段 | SyncRecord |
|---------|------------|
| `record_id` | `recordID` |
| `kind` | `kind` |
| `updated_at` | `updatedAt` |
| `device_id` | `deviceId` |
| `deleted` | `deleted` |
| `schema_version` | `schemaVersion` |
| `payload` | `payload` |

### 3.7 MeoBrowser payload（与 CloudKit 方案对齐）

**kind=`shortcut`**

```json
{
  "title": "GitHub",
  "url": "https://github.com",
  "order": 0,
  "kind": "link",
  "folderId": "",
  "iconURL": ""
}
```

**kind=`form_memo`**

```json
{
  "title": "报障常用",
  "host": "ops.example.com",
  "pathPrefix": "/tickets/new",
  "isDefault": true,
  "waitTimeoutMs": 8000,
  "fields": [
    {"fieldID":"…","label":"工号","selector":"input[name=employeeId]","value":"E12345","enabled":true}
  ]
}
```

---

## 4. 服务端开发与部署

> 「开发」在本方案中 = **配置 PocketBase + 运维脚本**，不写业务后端代码。

### 4.1 本机开发（SS-0，当天可完成）

```bash
cd server/pocketbase
./scripts/download.sh          # 或手动下载解压到 bin/pocketbase
./scripts/serve-dev.sh         # ./bin/pocketbase serve --http=127.0.0.1:8090
```

1. 浏览器打开 Admin，创建管理员账号（仅本机运维用）  
2. 按 §3.3 建 `sync_records` + 唯一索引  
3. 按 §3.4 设 API Rules  
4. Settings → 按需打开用户注册  
5. 用 curl 注册/登录/写一条记录冒烟  

冒烟示例：

```bash
# 注册
curl -s -X POST http://127.0.0.1:8090/api/collections/users/records \
  -H 'Content-Type: application/json' \
  -d '{"email":"a@test.com","password":"password123","passwordConfirm":"password123"}'

# 登录
TOKEN=$(curl -s -X POST http://127.0.0.1:8090/api/collections/users/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"a@test.com","password":"password123"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

echo "token=$TOKEN"
```

### 4.2 公网暴露：Cloudflare Tunnel（推荐，免费 HTTPS）

1. 安装 `cloudflared`，登录 Cloudflare 账号  
2. 创建 Tunnel，指向 `http://127.0.0.1:8090`  
3. 绑定域名 `sync.example.com`  
4. 客户端 Base URL 填 `https://sync.example.com`  

示例配置见 `server/pocketbase/config/cloudflared.example.yml`。

**注意**：PocketBase Admin（`/_/`）公网暴露有风险；生产建议：

- Admin 仅监听 localhost，或  
- Cloudflare Access 保护 `/_/`，或  
- 防火墙只允许你的 IP 访问管理路径  

### 4.3 VPS 部署（S1）

```text
VPS (1核1G)
  ├── Caddy/Nginx :443 → 127.0.0.1:8090
  ├── systemd: meo-pocketbase.service
  └── cron: backup.sh → 对象存储 / 另一盘
```

步骤概要：

1. 上传 `bin/pocketbase` + 空或已有 `pb_data`  
2. `systemd` 托管（见 `meo-pocketbase.service.example`）  
3. Caddy 自动 HTTPS（见 `Caddyfile.example`）  
4. `backup.sh` 每日打包 `pb_data`  

### 4.4 备份与恢复

```bash
./scripts/backup.sh   # → backups/pb_data-YYYYMMDD-HHMM.tgz
```

恢复：停服务 → 解压覆盖 `pb_data/` → 再启动。

**务必定期备份**；SQLite 文件损坏无主从时，备份是唯一保险。

### 4.5 升级 PocketBase

1. 备份 `pb_data`  
2. 替换二进制  
3. 启动；按官方 changelog 处理迁移  

### 4.6 服务端验收清单

- [ ] Admin 能建用户 / 集合  
- [ ] 用户 A 登录后只能读写自己的 records  
- [ ] 用户 B 看不到 A 的数据  
- [ ] HTTPS 可从另一台机器访问  
- [ ] 备份脚本可还原  

---

## 5. MeoBrowser 客户端设计

### 5.1 模块划分

```
SimpleBrowser/ServerSync/
├── ServerSyncSettings.h/.m      # baseURL、enabled、分项、lastSync、email（不含密码）
├── ServerSyncAuth.h/.m          # 注册/登录/登出；token → Keychain
├── ServerSyncAPIClient.h/.m     # NSURLSession 封装 REST
├── ServerSyncTransport.h/.m     # pullAll / upsertRecords / map PB↔SyncRecord
├── ServerSyncEngine.h/.m        # 启停、debounce、merge、状态
└── ServerSyncKeychain.h/.m      # token / password 可选仅 token
```

**复用（不要复制逻辑）**：

| 已有 | 用途 |
|------|------|
| `SyncCore/*` | SyncRecord / Merger / Device / Kind |
| `CloudSyncShortcutBridge` | 可抽成共享，或 ServerSync 直接调用同一套导出/应用 API |
| `CloudSyncFormMemoBridge` | 同上 |

推荐：把 Shortcut/FormMemo 桥接视为「本地 Store ↔ SyncRecord」与传输无关；`ServerSyncEngine` 与 `CloudSyncEngine` 平行，都调用 Bridge。

### 5.2 设置 UI

在 `BrowserSettingsWindowController` 增加分区 **「Meo 云同步」**（在 iCloud 分区之上或之下，文案区分清楚）：

```
┌─ Meo 云同步（自建服务器）─────────────────────────┐
│  服务器： [ https://sync.example.com        ]     │
│  账号：   [ email@… ]  密码：[ •••• ]             │
│  [ 注册 ] [ 登录 ] [ 退出登录 ]                    │
│  状态：已登录 / 未登录 / 同步中 / 错误…             │
│  ☑ 启用云同步                                      │
│  ☑ 快捷方式   ☑ 站点表单备忘                       │
│  上次同步：…     [ 立即同步 ]                      │
│  说明：数据存你自己的服务器；密码与 Cookie 不上传。  │
│  表单备忘字段为明文。无需 Apple 开发者账号。        │
└────────────────────────────────────────────────────┘
```

控件：`SBTextField` / `SBSecureTextField`（全局规范）。

### 5.3 Engine 流程

```text
syncNow:
  1. 校验 baseURL + token
  2. pullAll(app_id=meobrowser) → [SyncRecord]
  3. 按 enabled kinds：
       local = Bridge.export
       merged = SyncMerger.merge(remote, local)
       Bridge.apply(merged)
  4. upsert 全部 merged（或仅脏集；首版全量 upsert 可接受）
  5. 更新 lastSyncAt / 状态
```

本地变更 → debounce 3s → `syncNow`（或只 push；首版统一 `syncNow` 简单）。

失败：设置页显示错误；**禁止崩溃**（无 URL / 无 token 直接 return）。

### 5.4 常量

```objc
static NSString * const kServerSyncAppId = @"meobrowser";
// SyncKindShortcut / SyncKindFormMemo 已有
```

### 5.5 Makefile

- 增加 `ServerSync/*.m`  
- include 路径 `-IServerSync`  
- **不需要** CloudKit framework  

### 5.6 AppDelegate

启动：若 `ServerSyncSettings.enabled && 已登录` → `ServerSyncEngine startIfNeeded`。  
与 CloudSyncEngine 独立，互不影响。

---

## 6. 同步语义（定稿）

| 项 | 规则 |
|----|------|
| 冲突 | LWW：`updated_at` 大者胜；相等则 `device_id` 字典序大者胜 |
| 删除 | `deleted=true` tombstone，保留 ≥30 天 |
| 默认同步物 | 总开关开后：shortcut + form_memo 默认勾选 |
| 总开关默认 | 关 |
| 密码 / Cookie / Recipe 密文 | 永不上传 |
| 双通道 | 可同时开 Server + CloudKit；靠 LWW 收敛（可接受短暂抖动） |

---

## 7. 安全

| 项 | 做法 |
|----|------|
| 传输 | 生产必须 HTTPS |
| 鉴权 | 每请求 Bearer token；Rules 强制 user 隔离 |
| Token | Keychain；退出清除 |
| Admin | 勿对公网裸奔 |
| 备忘 | 明文入库；UI 明示 |
| 日志 | 禁止打印 memo field value / 密码 |

---

## 8. 第二应用接入（预留）

1. 约定 `app_id`（如 `meonotes`）  
2. 定义 `kind` + payload JSON schema（写进该应用文档）  
3. API Rules 白名单加上新 `app_id`  
4. 客户端实现 Store↔SyncRecord + 同一 `ServerSyncAPIClient`  

**服务端通常零代码、零迁表。**

---

## 9. 分阶段交付

| 阶段 | 侧 | 内容 | 预估 |
|------|----|------|------|
| **SS-0** | 服务端 | 本机 PocketBase + 集合 + Rules + curl 冒烟 | 0.5 日 |
| **SS-1** | 服务端 | Tunnel 或 VPS + HTTPS + 备份脚本 | 0.5～1 日 |
| **SS-2** | 客户端 | ServerSync Auth/API/Transport/Engine + 设置 UI | 2～3 日 |
| **SS-3** | 联调 | 两机同步、tombstone、错误态、文档勾选 | 1 日 |
| **SS-4** | 文档 | 第二应用 checklist（可选） | 0.5 日 |

**MVP = SS-0 + SS-2 + SS-3**（SS-1 可先用局域网 IP `http://192.168.x.x:8090` 开发，上公网再补）。

详细任务勾选见 [server-sync-development-plan.md](server-sync-development-plan.md)。

---

## 10. 验收（MVP）

### 服务端

- [ ] 本机 Admin 可用；集合与 Rules 正确  
- [ ] 用户隔离：A 不可读 B  
- [ ] 备份可还原  

### 客户端

- [ ] 未填服务器时设置不崩溃  
- [ ] 注册/登录/退出正常  
- [ ] 开同步后 shortcut、form_memo 双向对齐  
- [ ] 删除对端收敛  
- [ ] 关开关停止上传  
- [ ] Keychain/Cookie 不上云  
- [ ] `make browser` 通过  

---

## 11. 风险

| 风险 | 缓解 |
|------|------|
| 公网 Admin 暴露 | Tunnel Access / 仅本地 Admin |
| SQLite 单点 | 日备份；小规模够用 |
| 全量 upsert 慢 | 用户量小可接受；后期增量 + 脏集 |
| 与 CloudKit 双开抖动 | LWW；或 UI 提示勿同时开 |

---

## 12. 总结

| 问题 | 答案 |
|------|------|
| 服务端怎么「开发」？ | 不写后端业务代码：装 PocketBase、建表、Rules、部署脚本 |
| 怎么部署？ | 本机 → Tunnel；或 VPS + Caddy + systemd |
| 客户端怎么做？ | ServerSync 模块 + 复用 SyncCore/Bridge + 设置页 |
| 多应用？ | `app_id` 字段隔离 |
| 和 CloudKit？ | 并列可选；无苹果年费时用本方案 |

下一步：按开发计划执行 **SS-0 服务端** → **SS-2 客户端**。
