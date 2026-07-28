# Meo 云同步（PocketBase）— 开发计划

> 基于 [server-sync-design.md](server-sync-design.md)。  
> **MVP = SS-0 + SS-2 + SS-3**（SS-1 公网可后补；开发可用局域网 IP）。  
> 状态：**待开发**  
> Cursor：[.cursor/plans/server-sync.plan.md](../../.cursor/plans/server-sync.plan.md)  
> 脚手架：[`server/pocketbase/`](../../server/pocketbase/)

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 后端 | PocketBase；无自研 API 服务 |
| app_id | `meobrowser` |
| kinds | `shortcut` + `form_memo` |
| 冲突 | SyncCore LWW |
| 鉴权 | email/password；token → Keychain |
| UI | 设置页「Meo 云同步」；SBTextField / SBSecureTextField |
| CloudKit | 保留不动；通道独立 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| SS-0 | 服务端本机 | 0.5 日 | PocketBase 跑通 + 集合 + Rules |
| SS-1 | 公网部署 | 0.5～1 日 | Tunnel/VPS + HTTPS + 备份 |
| SS-2 | MeoBrowser 客户端 | 2～3 日 | ServerSync 全模块 + 设置 UI |
| SS-3 | 联调验收 | 1 日 | 双机同步 + 文档勾选 |
| SS-4 | 多应用文档 | 0.5 日 | 第二应用 checklist |

---

## Phase SS-0：服务端本机

### 任务

- [ ] **0.1** 确认 `server/pocketbase/` 脚手架齐全  
- [ ] **0.2** `./scripts/download.sh` 取得二进制  
- [ ] **0.3** `./scripts/serve-dev.sh` 启动；创建 Admin  
- [ ] **0.4** 创建集合 `sync_records`（字段见设计 §3.3）  
- [ ] **0.5** 唯一索引 `(user, app_id, record_id)`  
- [ ] **0.6** API Rules 仅本人读写  
- [ ] **0.7** 开启用户注册（开发期）  
- [ ] **0.8** curl：注册 → 登录 → POST 一条 → GET 可见；第二用户不可见  

**验收**：冒烟脚本或手测通过。

---

## Phase SS-1：公网（可选，不阻塞 SS-2）

- [ ] **1.1** Cloudflare Tunnel 或 VPS + Caddy  
- [ ] **1.2** HTTPS 从外网可登录  
- [ ] **1.3** Admin 访问收紧  
- [ ] **1.4** `backup.sh` + cron  
- [ ] **1.5** 记录生产 Base URL 供客户端填写  

---

## Phase SS-2：MeoBrowser 客户端

### 2A — 模块

- [ ] **2.1** 创建 `SimpleBrowser/ServerSync/`  
- [ ] **2.2** `ServerSyncSettings`（URL、enabled、分项、lastSync、email）  
- [ ] **2.3** `ServerSyncKeychain` / Auth（login/register/logout）  
- [ ] **2.4** `ServerSyncAPIClient`（REST）  
- [ ] **2.5** `ServerSyncTransport`（pull + upsert；PB↔SyncRecord）  
- [ ] **2.6** `ServerSyncEngine`（debounce、merge、调 Bridge）  
- [ ] **2.7** Makefile 纳入源文件与 `-IServerSync`  

### 2B — 复用桥接

- [ ] **2.8** Engine 调用现有 `CloudSyncShortcutBridge` / `CloudSyncFormMemoBridge`（或抽共享名；禁止复制 LWW）  
- [ ] **2.9** applyingRemote 防回环（对齐 CloudSyncEngine）  

### 2C — UI 与生命周期

- [ ] **2.10** 设置页「Meo 云同步」分区（SBKit 输入框）  
- [ ] **2.11** AppDelegate：启动按需 `startIfNeeded`  
- [ ] **2.12** `make browser` 通过；未配置服务器不崩溃  

---

## Phase SS-3：联调

- [ ] **3.1** 两台 Mac（或两用户数据目录）同一账号对齐 shortcut  
- [ ] **3.2** form_memo 含字段 value 对齐  
- [ ] **3.3** 删除 tombstone  
- [ ] **3.4** 关开关停传  
- [ ] **3.5** 错误态可读（错误密码 / 宕机）  
- [ ] **3.6** 更新 design/development-plan 状态  
- [ ] **3.7** `make browser`  

---

## Phase SS-4：多应用（文档）

- [ ] **4.1** 在 design 中固化第二应用 checklist  
- [ ] **4.2** Rules 白名单扩展示例  

---

## Agent 约束

1. ObjC + ARC；新输入框用 SBTextField / SBSecureTextField  
2. 不删除 CloudKit 模块  
3. 不打印密码与 memo value  
4. 提交信息仅在用户要求时写，且用简体中文  
5. 服务端以配置 + 脚本为主，不引入第二套后端框架  
