# MeoBrowser 云端同步 — 设计方案

> 目标：在**零自建服务端**前提下，为多台 Mac（及未来同 Apple ID 设备）同步「个人工作区」核心数据；与现有 Companion 局域网同步共用记录模型，互不替代。  
> 状态：**客户端已下线（2026-07-28）** — CloudKit 模块已移除；多设备同步改走 [server-sync-design.md](server-sync-design.md)（PocketBase）。本文档保留作历史方案参考。  
> 开发计划：[cloud-sync-development-plan.md](cloud-sync-development-plan.md) · Cursor：[.cursor/plans/cloud-sync.plan.md](../../.cursor/plans/cloud-sync.plan.md)  
> 关联：[companion-sync-design.md](companion-sync-design.md) · [companion-protocol.md](companion-protocol.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [auto-login-design.md](auto-login-design.md) · [site-form-memo-design.md](site-form-memo-design.md) · [server-sync-design.md](server-sync-design.md)（自建多应用 / 无 CloudKit 签名替代）

---

## 1. 一句话结论

**采用 Apple CloudKit（`CKSyncEngine`）私有库同步**；不自建 API、不运维数据库。  
同步范围默认极小：**Launchpad 快捷方式 + 站点表单备忘**；历史 / 书签 / 轻量偏好分项可选；密码、Cookie、Companion 配对等**默认永不上传**。

Companion（Mac ↔ Android LAN）继续服务「同 Wi‑Fi 互联」；云端同步服务「换机 / 多台 Mac / 不在同一局域网」。二者共用 **SyncRecord + LWW** 内核，只换传输层。

---

## 2. 为何选这条路

| 候选 | 服务端 | 与产品契合度 | 结论 |
|------|--------|--------------|------|
| **CloudKit + CKSyncEngine** | Apple 托管，零部署 | macOS 原生、iCloud 账号现成、隐私模型清晰 | **首选** |
| iCloud Drive 加密大文件 | 零部署 | 实现简单，冲突与增量弱 | MVP 备选 / 降级 |
| Firebase / Supabase | 托管 BaaS，近零运维 | 跨 Android 方便，但引入账号体系与 SDK | 仅当要做「云端 Mac↔Android」再评估 |
| 自建同步服务 | 需部署 | 与「轻量、无遥测」定位冲突 | **不做** |
| 仅依赖 Companion LAN | 零云 | 已有；覆盖不了异地/换机 | 保留为并行通道 |

**选型定稿：CloudKit 私有数据库（Private Database）+ 分区按 kind。**

- 用户用自己的 Apple ID；数据不进 Meo 运营方服务器（因为没有）。
- 免费额度对个人浏览元数据绰绰有余。
- `CKSyncEngine`（macOS 14+ / 可降级到手动 `CKDatabase` 订阅）是 Apple 当前推荐的双向同步 API。

---

## 3. 与 Companion 同步的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    SyncCore（共享）                            │
│  SyncRecord { id, kind, payload, updatedAt, deviceId,        │
│               deleted, schemaVersion }                       │
│  Merge: LWW(updatedAt) → deviceId 字典序                      │
│  Tombstone: 默认保留 30 天                                    │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
     ┌──────────▼──────────┐       ┌──────────▼──────────┐
     │ CloudTransport      │       │ CompanionTransport  │
     │ CloudKit / CKSync   │       │ LAN JSON sync_*     │
     │ Mac ↔ Mac (异地)    │       │ Mac ↔ Android       │
     └─────────────────────┘       └─────────────────────┘
```

| 维度 | 云端（本文） | Companion V3 |
|------|--------------|--------------|
| 场景 | 换机、多 Mac、不在同一 Wi‑Fi | 同 LAN 与手机端对齐 |
| 鉴权 | iCloud 账号 + CloudKit | `deviceToken` 配对 |
| 默认同步物 | shortcut、form_memo | shortcut |
| 冲突 | 同一 LWW | 同一 LWW |
| 开关 | 「iCloud 同步」独立总开关 | 「与 Android 同步」独立总开关 |

**禁止**：云端通道转发 Companion 通知全文、OTP、配对 token。  
**允许**：同一条 shortcut 记录经一端写入后，另一端再拉齐（用户两边都开时可能双通道；以 LWW 收敛，可接受）。

---

## 4. 建议同步什么（产品定稿）

按「用户换机后最痛什么」与「隐私成本」排序。

### 4.1 同步（推荐）

| Kind | 本地来源 | 默认同步 | 说明 |
|------|----------|----------|------|
| `shortcut` | `BrowserShortcutStore` | **开**（总开关打开后） | Launchpad / 星标 / 地址栏补全的**单一数据源**；跨设备价值最高 |
| `form_memo` | `FormMemoStore` | **开**（总开关打开后） | 站点表单备忘整份同步（含字段 value）；换机后工单/CRM 常用文本可继续一键填入，见 §5.1 |
| `bookmark` | `CompanionBrowseSyncStore` / 未来书签库 | 关 | 与 Companion AB-5 字段对齐；无独立书签 UI 前可与 shortcut 共用或暂不暴露开关 |
| `history` | 未来历史库 / BrowseSync | 关 | 条数上限默认 **500**；设置中强提示「URL 会进 iCloud」 |
| `prefs` | `BrowsingPreferences` 子集 | 关 | 仅非敏感偏好：默认搜索引擎、UA 预设 ID、部分 UI 开关（见 §4.3） |

### 4.2 明确不同步（默认永久本地）

| 数据 | 原因 |
|------|------|
| Keychain 密码 / 登录密文 | 产品边界：不做云端密码库（[auto-login-design.md](auto-login-design.md)） |
| `LoginRecipe` 中含选择器以外的敏感字段若绑定凭证 | Recipe **元数据**可后期可选；密文永不进 CloudKit |
| WebKit Cookie / 本地存储 / 缓存 | 会话态、体积大、安全面大 |
| 窗口 / 标签会话全文 | 含临时页、内网 URL；改做可选「打开的标签」接力（§4.4） |
| Launchpad 壁纸二进制 | 体积大、可本地重设；最多同步「已选文件哈希/关闭」标志 |
| Favicon 磁盘缓存 | 可再拉取 |
| Companion 配对、通知收件箱、来电策略、聊天衍生数据 | 设备与隐私场景，走 LAN 或不落云 |
| SSL 例外、下载路径与记录 | 本机路径无效；安全例外不宜漫游 |
| Captcha / AI API Key、consent | Keychain + 本机同意 |

### 4.3 `prefs` 白名单（若启用）

仅同步下列键（示例名，实现时集中在一张表）：

| 键 | 含义 |
|----|------|
| `defaultSearchEngineID` | 默认搜索引擎 |
| `userAgentPresetID` | UA 预设（不含自定义完整字符串也可同步） |
| `cloudSyncEnabledKinds` | 各 kind 开关（设备间对齐体验） |

**不同步**：窗口 frame、侧栏宽度、本机路径、开发者模式等机器相关项。

### 4.4 打开的标签（可选，P2）

不做成「完整会话镜像」，避免内网标签意外上云。

| 方案 | 说明 |
|------|------|
| **推荐** | 「发送标签到其他设备」一次性 `open_tabs` 队列（类似 Chrome Send Tab），TTL 短（如 7 天） |
| 不做 | 持续双向同步全部 `savedWindowSessions` |

可与 Companion `open_url` 语义对齐，云端只是多一个投递箱。

---

## 5. 记录模型（与 Companion 对齐）

```json
{
  "id": "uuid",
  "kind": "shortcut",
  "updatedAt": 1710000000,
  "deviceId": "mac-<hardwareUUID>",
  "deleted": false,
  "schemaVersion": 1,
  "payload": {
    "title": "GitHub",
    "url": "https://github.com",
    "order": 0,
    "kind": "link",
    "folderId": "",
    "iconURL": ""
  }
}
```

| 字段 | 规则 |
|------|------|
| `id` | 稳定 UUID；本地增删改不换 id |
| `kind` | `shortcut` / `form_memo` / `bookmark` / `history` / `prefs` /（P2）`open_tabs` |
| `updatedAt` | Unix 秒；本地写入时刷新 |
| `deviceId` | 本机稳定 id（存 Keychain 或 Application Support） |
| `deleted` | tombstone；物理清理默认 30 天 |
| `payload` | kind 相关字段；CloudKit 存为 `CKRecord` 字段或 JSON blob |

### 5.1 `form_memo` payload

一条 SyncRecord ↔ 一份 `FormMemo`；`id` = `memoID`。

```json
{
  "id": "memo-uuid",
  "kind": "form_memo",
  "updatedAt": 1710000000,
  "deviceId": "mac-<hardwareUUID>",
  "deleted": false,
  "schemaVersion": 1,
  "payload": {
    "title": "报障常用",
    "host": "ops.example.com",
    "pathPrefix": "/tickets/new",
    "isDefault": true,
    "waitTimeoutMs": 8000,
    "fields": [
      {
        "fieldID": "field-uuid",
        "label": "工号",
        "selector": "input[name=\"employeeId\"]",
        "value": "E12345",
        "enabled": true
      }
    ]
  }
}
```

| 规则 | 定稿 |
|------|------|
| 粒度 | **整份 Memo**（含全部 `fields[]`）；字段级不拆成多条 SyncRecord |
| 冲突 | 整记录 LWW；两端同时改同一 Memo 的不同字段时，较新整份覆盖（可接受；不做字段级 merge） |
| 明文 | value 为工作常用文本（非密码）；进用户私有 iCloud；开启时设置页提示「备忘字段内容会同步到 iCloud」 |
| 本地 | 仍写 `Application Support/.../FormMemo/memos.json`；CloudKit 为副本，清除网站数据仍不删 Memo |
| Companion | 首版 **不**经 LAN 同步 Memo（云端 Mac↔Mac；手机端无填入能力前不做） |

**Merge（与 Companion 相同）**：

```text
for each incoming:
  local = find(id)
  if local == null: insert（除非纯 tombstone 且无历史）
  else if incoming.updatedAt > local.updatedAt: replace
  else if equal && incoming.deviceId > local.deviceId: replace
  else: keep local
purge tombstones > 30d
```

CloudKit 侧建议：

| CKRecord Type | 用途 |
|---------------|------|
| `MeoSyncRecord` | 一条 SyncRecord；`kind` 为可查询字段；`payload` 为 `Bytes` 或 `String(JSON)` |
| `MeoSyncMeta`（可选） | 每设备 `lastSyncAt`、schema 版本 |

Zone：使用 **自定义 Private Zone**（如 `meo-sync-v1`），便于整区重置与 schema 演进；或默认 zone + record type 前缀，MVP 可先默认 zone。

---

## 6. 架构（Mac 落地）

### 6.1 模块划分

```
SimpleBrowser/CloudSync/
├── CloudSyncSettings.h/.m          # 总开关、分项、上次同步时间
├── CloudSyncEngine.h/.m            # 启停、账号状态、触发 pull/push
├── CloudSyncTransport.h/.m         # CKSyncEngine / CKDatabase 封装
├── CloudSyncRecordCoder.h/.m       # SyncRecord ↔ CKRecord
└── CloudSyncAccountObserver.h/.m   # iCloud 可用性、退出登录处理
```

共享层（建议从 Companion 抽出，避免双份 merge）：

```
SimpleBrowser/SyncCore/
├── SyncRecord.h/.m
├── SyncMerger.h/.m                 # LWW + tombstone
└── SyncKind.h                      # 枚举 / 字符串常量
```

`CompanionShortcutSync` / `CompanionBrowseSyncStore` 改为调用 `SyncCore`；Cloud 与 Companion 都是 Transport。  
`FormMemoStore` 在 `persist` / 合并成功后发既有 `FormMemoStoreDidChangeNotification`；`CloudSyncEngine` 监听后把变更映射为 `form_memo` SyncRecord。

### 6.2 触发

1. 总开关打开且 iCloud 可用 → 启动 `CKSyncEngine`，按 enabled kinds 同步  
2. 本地 Store 变更（含 `BrowserShortcutStore` / `FormMemoStore`）→ debounce **2～5s** → 写入 SyncCore → Transport 上报  
3. 设置「立即同步」→ 强制 fetch + send  
4. App 进入前台 / 网络恢复 → 轻量 fetch  

### 6.3 账号与权限

| 项 | 要求 |
|----|------|
| Entitlement | `com.apple.developer.icloud-services` = CloudKit；`icloud-container-identifiers` |
| 容器 | `iCloud.<bundle-id>`（如 `iCloud.com.meobrowser.app`） |
| 未登录 iCloud | 设置页说明原因；本地照常工作 |
| 用户关闭开关 | 停止上传；可选「从 iCloud 删除本机已传数据」（二次确认） |

当前 `MeoBrowser.entitlements` 仅有 `web-browser`；落地时**追加** CloudKit，不替换现有项。

### 6.4 最低系统版本

| 策略 | 说明 |
|------|------|
| **推荐** | macOS 14+ 用 `CKSyncEngine` |
| 兼容 | 若仍需支持更低版本：同一 `SyncCore`，Transport 退化为 `CKQuerySubscription` + 手动 CRUD（工作量大，可声明「云同步需 macOS 14+」） |

与产品「轻量专业」一致时，**可要求云同步功能最低 macOS 14**，降低实现面。

---

## 7. 设置 UI

设置 → **iCloud 同步**（与「与 Android 同步」并列，文案区分清楚）：

```
┌─ iCloud 同步 ─────────────────────────────────────┐
│  ○ 状态：已连接 / 未登录 iCloud / 同步中 / 错误     │
│  [ 总开关 ] 使用 iCloud 同步浏览数据                 │
│                                                    │
│  ☑ 快捷方式（Launchpad）     ← 总开关开后默认勾选   │
│  ☑ 站点表单备忘              ← 总开关开后默认勾选   │
│  ☐ 书签                                            │
│  ☐ 历史（最多 500 条）                             │
│  ☐ 偏好设置（搜索引擎等）                           │
│                                                    │
│  上次同步：2026-07-28 12:40                        │
│  [ 立即同步 ]                                      │
│                                                    │
│  说明：密码、Cookie、Companion 通知不上传。         │
│  开启「站点表单备忘」时字段明文会进入你的 iCloud。   │
└────────────────────────────────────────────────────┘
```

隐私文案要点：

- 数据存于用户自己的 iCloud，MeoBrowser **无自建同步服务器**。  
- 开启历史同步时二次确认。  
- 开启表单备忘同步时提示：字段值为明文工作文本（非密码），将写入私有 iCloud。  
- 与 Android 同步是局域网通道，需单独开关；Memo **不**走 Companion。

---

## 8. 安全与隐私

| 规则 | 定稿 |
|------|------|
| 传输与静态 | 依赖 CloudKit / iCloud 加密；应用层不对非敏感 payload 再套一层（简化） |
| 敏感 kind | 密码类永不进库；若未来可选「Recipe 元数据」，密文仍只在 Keychain |
| `form_memo` | 允许同步明文 value；**禁止**把 password 类型字段或 Keychain 内容写入 Memo；日志只打 `memoID` / `fieldID` / host，不打 value |
| 日志 | 不打 URL / Memo value 全文到控制台（历史与备忘同步开启时尤其注意） |
| 遥测 | 不同步、不上报同步内容到第三方 |
| 重置 | 「清除本机浏览数据」不自动清 iCloud；另提供「删除 iCloud 中的 Meo 同步数据」 |
| 多用户同一 Mac | 跟随 macOS 用户与 iCloud 账号隔离 |

**不做**：端到端自建加密信封（可作 P3，技术用户可选密码派生密钥）；首版信任 iCloud 私有库。

---

## 9. 冲突、删除与容量

| 项 | 策略 |
|----|------|
| 冲突 | LWW；不设 OT/CRDT |
| 删除 | tombstone 30 天；CloudKit 记录同步 `deleted=true`，到期本地与云端可硬删 |
| 历史上限 | 默认 500；超出按 `visitTime`/`updatedAt` 淘汰最旧（并写 tombstone 或仅本地裁剪策略需一致） |
| shortcut 体积 | 仅 URL/标题/folder；favicon 二进制不同步 |
| form_memo 体积 | 整份 JSON；单条建议软上限（如字段总 value < 64 KiB），超限仍可本地保存但提示「过大可能无法同步」 |
| 配额 | 个人私有库足够；异常时 UI 提示「iCloud 存储空间不足」 |

---

## 10. 跨 Android 的边界

| 需求 | 方案 |
|------|------|
| Mac ↔ Android 同 Wi‑Fi | **继续 Companion V3**（已有设计） |
| Mac ↔ Android 异地云同步 | **首版不做**；避免引入 Firebase 账号与第二套云 |
| 未来若要做 | 评估：① Android 端读同一套「用户自建中继」；② 或托管 BaaS + 端到端加密；单独专项，不阻塞 CloudKit |

叙事保持清晰：

> **iCloud**：多台 Apple 设备上的工作区。  
> **Companion**：手机与电脑的局域网互联（含同步、OTP、通知）。

---

## 11. 分阶段落地

| 阶段 | 内容 | 预估 |
|------|------|------|
| **CS-0** | 本文定稿；抽出 `SyncCore`（Record + Merger）；Companion 改为调用 Core（行为不变） | 1～2 日 |
| **CS-1** | Entitlement + CloudKit 容器；`CloudSyncSettings`；`shortcut` + `form_memo` 上下行；设置 UI | 4～6 日 |
| **CS-2** | `history` / `bookmark` / `prefs` 分项；上限与二次确认；错误态 | 2～3 日 |
| **CS-3** | 「立即同步」、上次同步时间、从 iCloud 删除、验收用例 | 1～2 日 |
| **CS-4（可选）** | `open_tabs` 投递箱；Recipe 元数据可选同步（仍无密码） | 按需 |

**MVP = CS-0 + CS-1 + CS-3 最小集**：开总开关后两台 Mac 的 Launchpad 快捷方式与站点表单备忘对齐。

---

## 12. 验收标准（MVP）

- [ ] 未登录 iCloud 时，浏览功能正常；设置显示原因  
- [ ] 总开关默认关；打开后 **shortcut + form_memo** 默认勾选  
- [ ] A 机改快捷方式 → B 机同 Apple ID 在合理时间内（秒～分钟级）对齐  
- [ ] A 机增改删站点备忘（含字段 value）→ B 机 `FormMemoStore` 对齐，侧栏/钥匙菜单可用  
- [ ] 两端同时改不同项：LWW 收敛，无崩溃  
- [ ] 删除 shortcut / form_memo：对端变为删除（tombstone），不「复活」旧记录（除非对端更新更晚——按 LWW）  
- [ ] 关闭总开关或关掉「站点表单备忘」分项后不再上传对应 kind；本地仍可编辑  
- [ ] Keychain / Cookie / 通知收件箱无任何 CloudKit 写入；关闭 `form_memo` 分项时备忘不上传  
- [ ] Companion 同步开关与 iCloud 开关互不影响（可同时开，靠 LWW）；Memo 不出现在 Companion sync 帧  
- [ ] `make browser` 在未配置 CloudKit 的开发机可编译；无容器时运行降级为「同步不可用」而非崩溃  

---

## 13. 不做清单

- 自建同步服务器 / 自运维 Postgres  
- 云端密码库、Cookie 漫游、完整标签会话镜像  
- 默认开启历史同步  
- 把 Companion 通知 / OTP 送到 iCloud  
- 首版 Mac↔Android 云中继  
- 为同步引入 Firebase / 强制注册 Meo 账号  

---

## 14. 风险与缓解

| 风险 | 缓解 |
|------|------|
| CloudKit 容器 / 签名配置门槛 | 文档写明 Developer 步骤；无容器时优雅降级 |
| 双通道（iCloud + Companion）重复推送 | 同一 SyncCore + LWW；接受短暂抖动 |
| 历史隐私 | 默认关 + 确认文案 + 条数上限 |
| 备忘明文进 iCloud | 默认随总开关开，但可单独关掉；设置页明示；日志禁打 value |
| 旧系统无 CKSyncEngine | 功能门控 macOS 14+，或延后兼容层 |
| Schema 变更 | `schemaVersion` + zone 名带版本；破坏性变更换 zone |

---

## 15. 与现有文档的交叉引用

落地时请同步更新：

| 文档 | 变更 |
|------|------|
| [docs/README.md](../README.md) | 增加本方案索引 |
| [companion-sync-design.md](companion-sync-design.md) | 注明「记录模型由 SyncCore 共享；云端见 cloud-sync-design」 |
| [professional-features-roadmap.md](professional-features-roadmap.md) | 「换机 / 多设备」条目指向 CloudKit，而非自建 |
| [auto-login-design.md](auto-login-design.md) | 保持「密码不云同步」；与本文 §4.2 一致 |
| [site-form-memo-design.md](site-form-memo-design.md) | Memo 支持可选 iCloud 同步（`form_memo`）；本地 JSON 仍为权威读写入口 |

---

## 16. 总结

| 问题 | 答案 |
|------|------|
| 同步什么？ | **默认同步快捷方式 + 站点表单备忘**；可选书签、历史（限量）、轻量偏好；不做密码/Cookie |
| 用什么方案？ | **CloudKit 私有库 + CKSyncEngine**（主流、零自建服务端） |
| 和手机怎么协同？ | **继续 Companion LAN**；云端不替代局域网互联；Memo 首版仅 iCloud |
| 怎么简化运维？ | 无服务器、无 Meo 账号后端；仅需 Apple 开发者 CloudKit 容器 |

下一步实现入口：**按 [cloud-sync-development-plan.md](cloud-sync-development-plan.md) / [.cursor/plans/cloud-sync.plan.md](../../.cursor/plans/cloud-sync.plan.md) 执行 CS-0 → CS-1 → CS-3。**
