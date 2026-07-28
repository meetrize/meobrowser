# iCloud 云端同步 — 开发计划（Cursor 可执行）

> 基于 [cloud-sync-design.md](cloud-sync-design.md) 的分阶段实施计划。  
> **首版范围（MVP）= CS-0 + CS-1 + CS-3**：`shortcut` + `form_memo` 经 CloudKit 私有库双向同步。  
> **不做（本计划）**：`history` / `bookmark` / `prefs`（CS-2）、`open_tabs`、Recipe/密码、Companion 传 Memo、自建服务端。  
> 状态：**MVP 已实现（2026-07-28）** — `make browser` 通过；真机双向需正式签名 + CloudKit 容器。  
> Cursor 计划：[.cursor/plans/cloud-sync.plan.md](../../.cursor/plans/cloud-sync.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 传输 | CloudKit Private DB；按 Index+RecordID 拉取/写入（避免 Query 索引门槛）；macOS 14+ |
| 默认同步物 | 总开关打开后：`shortcut` + `form_memo` 默认勾选 |
| 总开关默认 | **关** |
| 冲突 | 记录级 LWW：`updatedAt` → `deviceId` 字典序 |
| 删除 | tombstone `deleted=true`，保留 30 天 |
| Zone | 默认 zone；record type `MeoSyncRecord` + `MeoSyncIndex` |
| 未登录 / 无容器 / &lt;14 | 本地功能正常；设置显示原因；**禁止崩溃** |
| Companion | **不改协议**；Memo **不**进 LAN sync |
| 密码 / Cookie | 永不写入 CloudKit |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase CS-0 | SyncCore 内核 | **完成** | SyncRecord / SyncMerger / SyncDevice / SyncKind |
| Phase CS-1 | CloudKit + 双 kind + 设置 UI | **完成** | Transport、Engine、桥接、设置分区 |
| Phase CS-3 | 打磨与验收 | **完成** | 立即同步、上次时间、删除云端、文档 |
| Phase CS-2 | （后续）历史/书签/偏好 | 不做 | — |

**首版交付目标：CS-0 + CS-1 + CS-3（已完成）。**

---

## Phase CS-0：SyncCore

### 任务清单

- [x] **0.1** 创建 `SimpleBrowser/SyncCore/`
- [x] **0.2** `SyncKind.h`
- [x] **0.3** `SyncRecord.h/.m`
- [x] **0.4** `SyncDevice.h/.m`
- [x] **0.5** `SyncMerger.h/.m`
- [x] **0.6** Makefile SyncCore
- [x] **0.7** `make browser` 通过

---

## Phase CS-1：CloudKit 传输 + shortcut / form_memo + 设置

### 任务清单

- [x] **1.1** Entitlements 追加 CloudKit
- [x] **1.2** Makefile 链接 CloudKit
- [x] **1.3** 设置页说明签名/容器要求
- [x] **1.4** `SimpleBrowser/CloudSync/`
- [x] **1.5** `CloudSyncSettings`
- [x] **1.6** `CloudSyncRecordCoder`
- [x] **1.7** `CloudSyncAccountObserver`
- [x] **1.8** `CloudSyncTransport`（Index + fetch by ID）
- [x] **1.9** `CloudSyncEngine`
- [x] **1.10–1.11** `CloudSyncShortcutBridge`
- [x] **1.12–1.13** `CloudSyncFormMemoBridge`（禁打 value）
- [x] **1.14–1.16** 设置「iCloud 同步」分区
- [x] **1.17** AppDelegate 启停
- [x] **1.18** `make browser` 通过

---

## Phase CS-3：打磨与验收

- [x] **3.1** 「立即同步」
- [x] **3.2** 「上次同步」时间
- [x] **3.3** 「从 iCloud 删除同步数据」二次确认
- [x] **3.4** 关闭总开关/分项停传
- [x] **3.5** 对照 design §12（代码路径覆盖；双机手测依赖签名环境）
- [x] **3.6** 更新文档状态
- [x] **3.7** `make browser` 通过（`make verify` 含 SimpleWindow ibtool，与本功能无关）

---

## 实现说明

- Transport 使用 `MeoSyncIndex`（recordNamesJSON）+ 按 ID `CKFetchRecordsOperation`，避免私有库 TRUEPREDICATE 查询需 Dashboard 索引。
- 真机双向：Developer Portal 创建 `iCloud.com.example.MeoBrowser`，`CODESIGN_IDENTITY=… make browser`。
