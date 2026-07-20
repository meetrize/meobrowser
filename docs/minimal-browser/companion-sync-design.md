# Companion 局域网同步（V3）— 设计方案

> 目标：MeoBrowser（macOS）↔ MeoBrowser（Android）在已配对 LAN 通道上同步快捷方式 / 历史 / 书签。  
> 状态：骨架 + shortcut 专章（AB-0 / AB-4）  
> 关联：[companion-protocol.md](companion-protocol.md) · [android-browser-feasibility-and-plan.md](android-browser-feasibility-and-plan.md) · [android-browser-development-plan.md](android-browser-development-plan.md)

---

## 1. 原则

| 项 | 定稿 |
|----|------|
| 传输 | 复用 Companion 长度前缀 JSON；鉴权 `deviceToken` |
| 冲突 | 记录级 LWW：`updatedAt` 大者胜；相等则 `deviceId` 字典序大者胜 |
| 删除 | tombstone：`deleted=true`，保留至过期（默认 30 天）后再物理删 |
| 默认同步 | 总开关默认关；打开后仅 shortcut 默认勾选 |
| 单帧 | ≤ 64 KiB；超出用 `sync_chunk` |

---

## 2. 消息类型（V3）

| type | 方向 | 说明 |
|------|------|------|
| `sync_hello` | 双向 | 交换 `deviceId`、`supportedKinds`、`epoch` |
| `sync_pull` | →对端 | `kind` + `sinceEpoch` |
| `sync_push` | →对端 | `kind` + `records[]` + `epoch` |
| `sync_chunk` | →对端 | `transferId`、`index`、`total`、`payload`（base64 或内嵌 JSON 片段） |
| `sync_ack` | ←对端 | `kind` + `appliedEpoch` |
| `sync_error` | ←对端 | `message` |

所有消息必填：`v`、`type`、`deviceToken`（hello 后）。

### 2.1 sync_push 示例（shortcut）

```json
{
  "v": 1,
  "type": "sync_push",
  "deviceToken": "…",
  "kind": "shortcut",
  "epoch": 42,
  "records": [
    {
      "id": "uuid",
      "title": "GitHub",
      "url": "https://github.com",
      "order": 0,
      "kind": "link",
      "folderId": "",
      "iconURL": "",
      "updatedAt": 1710000000,
      "deviceId": "android-uuid",
      "deleted": false
    }
  ]
}
```

---

## 3. Shortcut 数据模型（对齐双端）

| 字段 | Android | Mac `BrowserShortcutItem` |
|------|---------|---------------------------|
| id | `id` | `itemID` |
| title | `title` | `title` |
| url | `url` | `urlString` |
| order | `order` | `sortOrder` |
| kind | `link`/`folder` | `BrowserShortcutItemKind` |
| folderId | `folderId` | `folderID` |
| iconURL | `iconURL` | `iconURLString` |
| updatedAt | Unix 秒 | 同步层扩展（UserDefaults 旁路或 item 扩展） |
| deviceId | 本机 deviceId | Mac 固定 `mac-<host>` |
| deleted | bool | 同步层 tombstone 表 |

**Merge 伪代码**：

```text
for each incoming record:
  local = find(id)
  if local == null: insert (unless deleted && no prior)
  else if incoming.updatedAt > local.updatedAt: replace
  else if equal && incoming.deviceId > local.deviceId: replace
  else: keep local
purge tombstones older than 30d
bump local epoch; ack
```

---

## 4. History / Bookmark（AB-5）

| kind | 关键字段 |
|------|----------|
| `history` | id, url, title, visitTime, visitCount, updatedAt, deviceId, deleted |
| `bookmark` | id, title, url, order, updatedAt, deviceId, deleted |

历史默认同步关；条数上限默认 500～1000。

---

## 5. 触发

1. 连接成功且总开关开 → `sync_hello` → 对各 enabled kind `sync_pull`  
2. 本地变更 debounce 2～5s → `sync_push`  
3. 设置「立即同步」→ 全量 pull+push  

OTP / `phone_notification` 与 sync 独立；关同步总开关不得发 sync_*。
