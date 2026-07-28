---
name: Meo PocketBase 云同步
overview: 按 SS-0→SS-3 落地 PocketBase 自建同步：服务端建表部署 + MeoBrowser ServerSync（shortcut/form_memo）。依据 docs/minimal-browser/server-sync-design.md。
todos:
  - id: ss-0-server
    content: SS-0：本机 PocketBase + sync_records 集合/Rules + curl 冒烟
    status: completed
  - id: ss-1-deploy
    content: SS-1（可选）：Tunnel/VPS HTTPS + 备份脚本
    status: completed
  - id: ss-2-client-core
    content: SS-2：ServerSync Settings/Auth/API/Transport/Engine + Makefile
    status: completed
  - id: ss-2-ui-lifecycle
    content: SS-2：设置页「Meo 云同步」+ AppDelegate 启停；复用 Shortcut/FormMemo 桥
    status: completed
  - id: ss-2-build
    content: SS-2：make browser；无服务器时不崩溃
    status: completed
  - id: ss-3-verify
    content: SS-3：双机/双端同步验收；更新文档状态
    status: completed
isProject: true
---

# Meo PocketBase 云同步 — Cursor 自动开发计划

> **依据**：[server-sync-design.md](docs/minimal-browser/server-sync-design.md) · [server-sync-development-plan.md](docs/minimal-browser/server-sync-development-plan.md)  
> **脚手架**：[server/pocketbase/](server/pocketbase/)  
> **范围**：SS-0 服务端本机 + SS-2 客户端 + SS-3 验收；SS-1 公网可选。  
> **构建**：客户端阶段结束执行 `make browser`。  
> **提交**：仅当用户要求；message 简体中文。

## Goal

1. 跑通 PocketBase，`sync_records` 可按用户隔离存取。  
2. MeoBrowser 通过 HTTPS 同步 **shortcut** + **form_memo**。  
3. 不依赖 Apple CloudKit 签名。

## Scope

| 做 | 不做 |
|----|------|
| PocketBase 配置 + 脚本 | 自研 Node/Go API |
| ServerSync 客户端模块 | 密码/Cookie/历史首版 |
| 设置页登录同步 | 端到端加密 |
| 复用 SyncCore + Bridge（CloudKit 已移除） | |

## 服务端（SS-0）执行要点

```bash
cd server/pocketbase && ./scripts/download.sh && ./scripts/serve-dev.sh
```

Admin 建集合字段与 Rules：严格按 design §3.3 / §3.4。  
curl 验证双用户隔离。

## 客户端（SS-2）模块

```
SimpleBrowser/ServerSync/
  ServerSyncSettings.*
  ServerSyncAuth.*
  ServerSyncAPIClient.*
  ServerSyncTransport.*
  ServerSyncEngine.*
  (+ Keychain 辅助)
```

- `app_id` = `meobrowser`  
- Engine：pull → SyncMerger → Bridge.apply → upsert  
- UI：`BrowserSettingsWindowController` 新分区；SBKit 输入框  
- 无 URL / 未登录：优雅降级  

## 验收

- 注册登录成功  
- A↔B 快捷方式与备忘对齐  
- tombstone、关开关、不崩溃、`make browser`  
