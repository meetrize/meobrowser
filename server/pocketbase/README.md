# Meo PocketBase 服务端脚手架

完整方案见：[docs/minimal-browser/server-sync-design.md](../../docs/minimal-browser/server-sync-design.md)

## 快速开始（本机）

```bash
cd server/pocketbase
chmod +x scripts/*.sh
./scripts/download.sh
./scripts/serve-dev.sh
```

浏览器打开终端提示的 Admin 地址（通常 `http://127.0.0.1:8090/_/`），创建管理员后按下面建表。

## 创建集合 `sync_records`

类型：**Base collection**。字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| user | Relation → users | ✓ | |
| app_id | Text | ✓ | 例 `meobrowser` |
| record_id | Text | ✓ | 业务 UUID |
| kind | Text | ✓ | `shortcut` / `form_memo` |
| updated_at | Number | ✓ | Unix 秒 |
| device_id | Text | ✓ | |
| deleted | Bool | ✓ | 默认 false |
| schema_version | Number | ✓ | 默认 1 |
| payload | JSON | ✓ | |

**Indexes**：添加 Unique：`user`, `app_id`, `record_id`。

## API Rules

List / View / Create / Update / Delete 均设为：

```
@request.auth.id != "" && user = @request.auth.id
```

## 冒烟

见 `scripts/smoke-test.sh`（需先 `serve-dev.sh`）。

## 备份

```bash
./scripts/backup.sh
```

## 生产

- Tunnel：`config/cloudflared.example.yml`  
- VPS：`config/Caddyfile.example` + `config/meo-pocketbase.service.example`  
- 远程安装：`scripts/install-remote.sh`（本机下载二进制后 scp 更稳；下载可用 `HTTPS_PROXY=http://127.0.0.1:7890`）
- Admin 登录失效自动回登录页：nginx `sub_filter` 注入 `static/meo-auth-guard.js`（对外 8090 → 本机 PocketBase；勿再用 Python 反代）

**公网实例的地址、Admin 口令、验收记录**写在本地私密文档（已 ignore，不进远程）：

[`docs/local/pocketbase-deploy.local.md`](../../docs/local/pocketbase-deploy.local.md)

勿将 `pb_data/`、管理员密码与备份中的真实密钥提交到 Git。
