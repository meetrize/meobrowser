# Companion 通知侧栏 App 图标同步 — 开发计划（Cursor 可执行）

> 基于 [companion-notification-app-icon-design.md](companion-notification-app-icon-design.md)。  
> **本计划交付范围：IC-0 + IC-MVP**（会话内首次推送小图标 + Mac 缓存 + 侧栏显示）。  
> **本计划不做：IC-1（`app_icon_need` / 跨会话 hash 协商）、IC-2（系统通知 Attachment）。**  
> 状态：**IC-0 + IC-MVP 已实现**（待真机联调验收）  
> 前置：通知收件箱侧栏 NI-MVP 已就绪；`phone_notification` 通道可用。

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| I1 交付 | **IC-0 + IC-MVP**（先不做 need） |
| I2 尺寸 | 优先 **72×72** PNG；超 **12 KiB** 降 **48×48** |
| I3 协议 | 独立 `app_icon` / `app_icon_ok`；**不改** `phone_notification` 正文结构 |
| I4 未读点 | 保持最左；图标在点右侧 28×28 |
| I5 横幅附件 | 不做 |
| 推送时机 | 某 `packageName` 在**当前 TCP 会话**第一次发镜像通知前/时推图标 |
| 占位 | 无缓存 → 首字圆标；`otp` → SF Symbol |
| 圆角 | **仅 Mac 绘制**（6pt） |
| 未知 type | Mac 已安全忽略；Android 忽略未知下行 |

**首版交付目标：IC-0 + IC-MVP。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 | 预估 |
|------|------|------|------|------|
| Phase IC-0 | Mac 缓存壳 + 侧栏占位 | ✅ | `PhoneAppIconCache`；侧栏 28×28 槽位；占位/OTP 符号 | 0.5～1 日 |
| Phase IC-MVP-A | Android 导出与推送 | ✅ | `AppIconExporter`；会话去重；`pushAppIcon` | 0.5～1 日 |
| Phase IC-MVP-B | Mac 收包与真图 | ✅ | Channel 处理 `app_icon`；落盘；侧栏刷新 | 0.5 日 |
| Phase IC-1 | need / hash 协商 | 不做 | 见设计稿 | — |
| Phase IC-2 | 通知附件 | 不做 | 见设计稿 | — |

---

## Cursor 执行约定

1. **顺序**：IC-0 → IC-MVP-A 与 IC-MVP-B 可并行，但侧栏真图依赖 B；建议先 IC-0，再 A+B。  
2. 每阶段结束：Mac `make browser` 通过；Android 模块可编译（有 Android SDK 时）。  
3. 日志：只打 `packageName`、`iconHash`、字节长度；**禁止**打印 base64。  
4. 新 Mac 源文件进 `SimpleBrowser/LoginAssist/Companion/`，写入 `Makefile`。  
5. 协议同步更新 `docs/minimal-browser/companion-protocol.md`（V2.3）。  
6. 输入框规范与本功能无关；侧栏图标用 `NSImageView`，勿引入 Web。

---

## Phase IC-0：Mac 缓存壳 + 侧栏占位

**目标**：列表行已有图标槽位；无真图时占位正确；Cache API 就绪但可无网络数据。

### 任务清单

- [x] **0.1** 新增 `PhoneAppIconCache.h/.m`  
  - 目录：`Application Support/MeoBrowser/PhoneAppIcons/`  
  - `index.json` + `{sanitizedPackage}.png`  
  - API：`imageForPackage:` / `hashForPackage:` / `storePNGData:package:iconHash:appLabel:error:` / `packagesMissingFrom:`  
  - 通知：`PhoneAppIconCacheDidChangeNotification`（userInfo `packageName`）  
  - 校验：字节 ≤ 12KiB、可解码为位图、边长 ≤ 128  
- [x] **0.2** 占位图工具（可放 Cache 类方法）：  
  - `placeholderImageWithLabel:package:`（首字 + hash 底色，28pt）  
  - `otpPlaceholderImage`（SF Symbol）  
- [x] **0.3** `PhoneNotificationSidebarController` 行 UI：  
  - 未读点右侧加 `NSImageView` 28×28，圆角 6，`masksToBounds`  
  - 绑定：`[PhoneAppIconCache imageForPackage:]` ?: 占位  
  - OTP / `package=otp` → OTP 占位  
- [x] **0.4** 观察 `PhoneAppIconCacheDidChangeNotification` → `reloadData`（可见时）  
- [x] **0.5** Makefile 加入新 `.m`；`make browser` 通过  

**完成标准**：侧栏每行有圆形/圆角图标槽；无缓存时首字或 OTP 符号；不依赖 Android。

---

## Phase IC-MVP-A：Android 导出与推送

**目标**：发 `phone_notification` 时，会话内该包首次附带 `app_icon`。

### 任务清单

- [x] **1.1** 新增 `AppIconExporter.kt`：Drawable→Bitmap→72/48 PNG→`iconHash`（SHA-256 前 8 字节 hex）  
  - 处理 `AdaptiveIconDrawable`  
  - 失败返回 null  
- [x] **1.2** `CompanionSession`（或 Client）：  
  - 内存 `sessionIconPushed: MutableMap<String, String>`（package→hash）  
  - `ensureAppIconPushed`  
  - `pushAppIcon(...)` 组 JSON `type=app_icon`  
  - 处理 `app_icon_ok`：写入 session map  
  - 处理 `error` 且与 icon 相关：本会话对该 package 不再重试  
- [x] **1.3** 在 `pushPhoneNotification` 路径上：发送通知前调用 `ensureAppIconPushed`（已连接时）  
- [x] **1.4** 限流：全局约 ≤2 icons/秒（简单时间戳节流即可）  
- [x] **1.5** 未连接：跳过图标（与通知一致）  

**完成标准**：日志可见 `app_icon` 发送与 ok；同包第二条通知不再发图标。

---

## Phase IC-MVP-B：Mac 收包与真图

**目标**：鉴权后落盘；侧栏显示真图标。

### 任务清单

- [x] **2.1** `CompanionChannel`：识别 `app_icon`  
  - 校验 `deviceToken`、`packageName`、`pngBase64`、`iconHash`  
  - 非法 → `error`  
  - 成功 → Cache.store → `app_icon_ok`  
- [x] **2.2** 确认未知 type 仍安全忽略（含旧逻辑回归）  
- [x] **2.3** 侧栏自动刷新（依赖 0.4）  
- [x] **2.4** 更新 `companion-protocol.md` V2.3：`app_icon` / `app_icon_ok`  
- [x] **2.5** 设计稿 / 本计划状态勾选；Companion README 一句话  

**完成标准**：真机全部通知 → 侧栏出现微信等图标；重启 Mac 图标仍在。

---

## 建议实现顺序（Agent）

```text
IC-0.1～0.5  Mac Cache + 侧栏占位
  → IC-MVP-B.1～2.2  Channel 收 app_icon（可先用本地测试 JSON）
  → IC-MVP-A 全阶段 Android 推送
  → IC-MVP-B.3～2.5 联调与文档
```

---

## 关键文件（预期）

### 新增

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/LoginAssist/Companion/PhoneAppIconCache.h/.m` | 缓存 |
| `companion/.../sms/AppIconExporter.kt` | 导出 |
| （可选）`companion/.../sms/AppIconPushTracker.kt` | 会话去重（已内嵌 `CompanionSession`） |

### 修改

| 路径 | 变更 |
|------|------|
| `CompanionChannel.m` | `app_icon` |
| `PhoneNotificationSidebarController.m` | 行图标 |
| `CompanionSession` / push 路径 | ensure + push |
| `Makefile` | 新文件 |
| `docs/minimal-browser/companion-protocol.md` | V2.3 |
| 设计 / 本计划 | 状态 |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 帧过大 | 12 KiB 硬顶；超限降 48 |
| 图标晚于通知 | 侧栏占位 → 收包后刷新 |
| 重试风暴 | decode/store 失败 Android 本会话不再重试 |
| 系统通知栏图标 | **明确不做**（Attachment 属 IC-2） |

---

## 验收（IC-MVP）

- [ ] 侧栏每行有 28×28 图标槽；无缓存时首字 / OTP 占位  
- [ ] 真机「全部通知」：某 App 首次通知后侧栏出现真图标  
- [ ] 同会话同包第二条通知不再传 `app_icon`  
- [ ] 重启 Mac 后缓存仍在  
- [ ] 坏图 / 过大图拒收不影响后续通知  
- [ ] 日志无 base64 正文  
