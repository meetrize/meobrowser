# Companion 通知侧栏 App 图标同步 — 完整技术方案

> 目标：在 Mac 手机通知收件箱侧栏中，为每条（或每个来源 App）显示与手机端一致的应用图标。  
> 路径：**Android 推送小图标 + Mac 按包名磁盘缓存**（非 SF 占位、非系统通知栏换图标）。  
> 状态：**方案已定稿；IC-0 + IC-MVP 已落地**；开发计划见 [companion-notification-app-icon-development-plan.md](companion-notification-app-icon-development-plan.md)  
> 关联：[companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md) · [companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [companion-protocol.md](companion-protocol.md) · `NotificationPayloadBuilder.kt`

---

## 0. 一句话结论

| 问题 | 结论 |
|------|------|
| 侧栏显示真 App 图标 | **可行** |
| 与手机图标一致 | **可行**：`PackageManager.getApplicationIcon` → 缩略 PNG → LAN 推送 → Mac 缓存 |
| 塞进每条 `phone_notification` | **不推荐**（体积、刷屏） |
| 推荐形态 | **独立 `app_icon` 消息 + 按 package 缓存 + 通知只带「是否需要图标」协商** |
| 系统通知栏左侧第三方图标 | **仍不可行**（系统限制，本方案不解决） |
| 工作量（含双端） | 约 **2.5～4 人日** |

---

## 1. 方案定位

### 1.1 产品一句话

**侧栏一眼认出是哪个 App**：微信、短信、银行 App 等显示手机上的同一套图标；验证码条目用专用 SF Symbol；无缓存时退回首字圆标。

### 1.2 与现有能力关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| `phone_notification` | ✅ 有 packageName / appLabel | **不改核心字段**；可选加轻量协商字段 |
| 收件箱侧栏列表 | ✅ 白底 + 分隔线 + 未读点 | 行首增加 **28×28** 圆角图标 |
| 图标协议 | ❌ | 新增 `app_icon` / `app_icon_ok` + Mac→Android `app_icon_need` |
| 系统横幅左侧图标 | 永远 MeoBrowser | **本期不做** `UNNotificationAttachment`（可作二期） |
| 帧上限 64 KiB | ✅ | 单图标严格限幅，禁止整图塞正文帧 |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| Android 提取应用图标并缩放、压缩 | 推送通知大图 / BigPicture 内容图 |
| 按 `packageName` 在 Mac 落盘缓存 | 每条通知重复传完整图标 |
| 侧栏行显示缓存图标 | 伪造系统通知中心第三方 App 图标 |
| 验证码 / 未知包名占位图标 | 云端图标 CDN、Play 商店抓取 |
| 图标版本哈希，App 升级后可更新 | 像素级还原自适应图标全部图层特效（尽力位图即可） |

---

## 2. 关键设计决策

### 2.1 为何不「每条通知带 base64」

| 问题 | 影响 |
|------|------|
| 同一微信连发 20 条 | 重复传同一图标，浪费带宽与电量 |
| base64 膨胀约 4/3 | 易逼近 64 KiB，挤压 title/body |
| JSON 解析成本 | 主线程/队列压力上升 |

### 2.2 定稿：缓存优先 + 按需推送

```text
连接建立
  → Mac 发送 app_icon_need { packages: [...缺失或过期的包名], known: [{package, iconHash}...] }
  → 或更简：Mac 只发 missingPackages[]（首版）

手机收到 phone_notification 待发
  → 若 Mac 已知该 package 的 iconHash 且未变 → 通知帧不带图标
  → 若未知 / 哈希变了 → 另发（或紧跟）一帧 app_icon

侧栏渲染
  → 查 Mac 本地 IconCache[packageName]
  → 命中：显示 PNG
  → 未命中：首字圆标；后台可记「待拉取」等下次 need
```

**首版可再简化（推荐落地顺序）**：

1. **IC-MVP**：每个 `packageName` 在**当前 TCP 会话内第一次**发通知时，附带或紧跟 `app_icon`；Mac 落盘后本会话不再要。  
2. **IC-1**：增加 `iconHash` + `app_icon_need`，跨会话增量、支持图标更新。  
3. **IC-2（可选）**：系统通知 `UNNotificationAttachment`。

本文 **IC-MVP + IC-1 一并设计**；实现可先交 IC-MVP。

### 2.3 图标规格（双端统一）

| 项 | 定稿 |
|----|------|
| 逻辑像素 | **72×72**（侧栏 28pt @2x/~3x 够用；也便于横幅附件二期） |
| 格式 | **PNG**（保留透明，适配 Android Adaptive 栅格化结果） |
| 编码 | JSON 内 **标准 Base64**（无 data-URL 前缀） |
| 原始字节上限 | **≤ 12 KiB**（压缩后）；超则降到 48×48 再压 |
| Base64 后约 | ≤ 16 KiB 字符 |
| 圆角 | **Mac 侧绘制**（`cornerRadius ≈ 6`）；Android 传方图，避免双端圆角不一致 |
| 色空间 | sRGB；不做广色域 |

Android 缩放建议：`Bitmap.createScaledBitmap` + `PNG` `compress(quality=取无损或 90)`；若仍超 12KiB → 边长 48 再压。

### 2.4 占位策略（无真图标时）

| 场景 | 展示 |
|------|------|
| 有缓存 | 真图标 |
| 无缓存、有 appLabel | 首字（或前两字）圆底 + 系统灰/色相哈希底色 |
| `kind=otp` / package=`otp` | SF Symbol `lock.shield` 或 `message.badge` |
| package 空 | SF Symbol `app.badge` |

占位与真图标**同尺寸槽位**（28×28），避免列表跳动。

---

## 3. 协议扩展（建议 V2.3）

传输、Bonjour、鉴权、64 KiB 帧格式不变。权威表同步维护于 [companion-protocol.md](companion-protocol.md)。

### 3.1 `app_icon`（Android → Mac）

```json
{
  "v": 1,
  "type": "app_icon",
  "deviceToken": "long-token",
  "packageName": "com.tencent.mm",
  "appLabel": "微信",
  "iconHash": "a1b2c3d4e5f67890",
  "mime": "image/png",
  "width": 72,
  "height": 72,
  "pngBase64": "<base64…>",
  "ts": 1710000000
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `deviceToken` | ✅ | 同 otp |
| `packageName` | ✅ | 缓存主键 |
| `appLabel` | 推荐 | 可刷新 Mac 侧展示名 |
| `iconHash` | ✅ | 见 §3.4；用于去重与更新 |
| `mime` | ✅ | 固定 `image/png`（首版） |
| `width` / `height` | ✅ | 像素边长 |
| `pngBase64` | ✅ | 无前缀；解码后 ≤ 12 KiB |
| `ts` | ✅ | Unix 秒 |

### 3.2 `app_icon_ok`（Mac → Android）

```json
{ "v": 1, "type": "app_icon_ok", "packageName": "com.tencent.mm", "iconHash": "a1b2c3d4e5f67890" }
```

失败：`error`（unauthorized / payload too large / decode failed）。  
Mac **解码失败仍应 ok 或明确 error** 并打日志，避免 Android 重试风暴——定稿：**decode 失败回 `error` 且 Android 对该 package 本会话不再重试**。

### 3.3 `app_icon_need`（Mac → Android，IC-1）

连接成功且镜像/收件箱开启后，Mac 可推送：

```json
{
  "v": 1,
  "type": "app_icon_need",
  "deviceToken": "long-token",
  "missing": ["com.tencent.mm", "com.android.mms"],
  "stale": [
    { "packageName": "com.eg.android.AlipayGphone", "iconHash": "oldhash" }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `missing` | Mac 无文件的包名（可来自近期收件箱 top N） |
| `stale` | 有文件但 hash 可能过期（可选；首版可只做 missing） |

Android 收到后对列表中每个 package **异步**生成并 `app_icon`（限流：每秒最多 2 个）。

**IC-MVP 可不实现本消息**：仅靠「会话内首次通知捎带」。

### 3.4 `iconHash` 算法

Android：

```text
iconHash = hex( SHA-256( pngBytes ).前 8 字节 )   // 16 个 hex 字符
```

不要用「包名+versionCode」代替内容哈希：OEM 改资源但 version 不变时会脏缓存；内容哈希更稳。

### 3.5 与 `phone_notification` 的关系

**推荐：通知帧保持干净，图标独立。**

可选轻量字段（IC-1，非必须）：

```json
"icon": { "hash": "a1b2c3d4e5f67890", "attached": false }
```

- `attached: true` 表示本连接上刚发过 / 即将发 `app_icon`（调试用）  
- Mac **不要**依赖通知帧内嵌大图

### 3.6 OTP 与仅验证码模式

| 模式 | 行为 |
|------|------|
| `otp_only` | 一般无 `phone_notification`；OTP 行用 SF 占位，**不**强求短信 App 图标 |
| `all` | 对出现过的 package 拉图标 |
| 合成 OTP 条目 (`package=otp`) | 永不请求 `app_icon` |

---

## 4. Android 设计

### 4.1 模块

| 组件 | 职责 |
|------|------|
| `AppIconExporter` | Drawable→Bitmap→缩放→PNG→hash |
| `AppIconPushStore` | 本会话已成功推送的 `packageName→iconHash`；内存即可 |
| `CompanionSession` | `pushAppIcon(...)`；处理 `app_icon_ok` / `app_icon_need` |
| `OtpNotificationListener` / 推送路径 | 发 `phone_notification` 前调用「确保图标」 |

### 4.2 提取伪代码

```text
drawable = pm.getApplicationIcon(packageName)
bitmap = drawable.toBitmap(max(intrinsic, 72))  // 注意 AdaptiveIconDrawable
scaled = scaleToFit(bitmap, 72, 72)             // 居中，透明底
png = compressPNG(scaled)
if png.size > 12KiB: scaled = scaleToFit(..., 48, 48); png = compress again
if still too big: skip push, log
hash = sha256(png).hex.take(16)
```

**AdaptiveIcon**：用 `AdaptiveIconDrawable` 时按系统方式栅格化到 Canvas（前景+背景），不要只取前景导致透明碎图。

### 4.3 何时推送（IC-MVP）

```text
onPhoneNotificationAboutToSend(packageName):
  if packageName blank or self-package: return
  if sessionAlreadyPushed[packageName] == currentHash: return
  build icon; if fail: return
  push app_icon
  on app_icon_ok: sessionAlreadyPushed[packageName] = hash
```

顺序建议：

```text
1) app_icon（若需要）
2) phone_notification
```

若图标异步稍慢：允许通知先到、图标后到；Mac 侧栏收到 `app_icon` 后 `reload` / 刷新可见行。

### 4.4 限流与失败

| 规则 | 值 |
|------|-----|
| 全局图标推送 | ≤ 2 个/秒 |
| 同 package 会话内 | 成功一次后不重发（除非 hash 变且 IC-1 need） |
| 导出失败 | 跳过，不影响通知 |
| 未连接 | 不推图标（同通知丢弃） |

### 4.5 权限

读取已安装应用图标：**不需要**额外 dangerous 权限（已有通知监听场景下 `getApplicationIcon` 可用）。注意 Android 11+ 包可见性：Companion 作为通知监听者通常能解析发通知的包；若个别包 `NameNotFound`，跳过即可。

---

## 5. Mac 设计

### 5.1 模块

| 组件 | 职责 |
|------|------|
| `PhoneAppIconCache` | 路径、读写 PNG、内存 NSCache、hash 索引 |
| `CompanionChannel` | 解析 `app_icon` / 发 `app_icon_ok`；（IC-1）发 `app_icon_need` |
| `PhoneNotificationSidebarController` | 行首 `NSImageView`；监听 Icon 变更刷新 |
| （可选）`PhoneNotificationPresenter` | IC-2 横幅附件 |

### 5.2 磁盘布局

```text
~/Library/Application Support/MeoBrowser/PhoneAppIcons/
  index.json          # { "com.tencent.mm": { "hash": "...", "file": "com.tencent.mm.png", "updatedAt": ... }, ... }
  com.tencent.mm.png
  com.android.mms.png
  ...
```

- 文件名：package 中非 `[A-Za-z0-9._-]` 替换为 `_`，避免路径问题  
- 淘汰：超过 **200** 个包删最久未用；或与收件箱 package 集合取交定期 GC  

### 5.3 `PhoneAppIconCache` API（示意）

```objc
@interface PhoneAppIconCache : NSObject
+ (instancetype)sharedCache;
- (nullable NSImage *)imageForPackage:(NSString *)packageName;
- (nullable NSString *)hashForPackage:(NSString *)packageName;
- (BOOL)storePNGData:(NSData *)data
             package:(NSString *)packageName
            iconHash:(NSString *)iconHash
            appLabel:(nullable NSString *)appLabel
               error:(NSError **)error;
- (NSArray<NSString *> *)packagesMissingFrom:(NSArray<NSString *> *)packages;
@end

extern NSNotificationName const PhoneAppIconCacheDidChangeNotification;
// userInfo[@"packageName"]
```

解码校验：

1. Base64 解码  
2. 字节 ≤ 12 KiB  
3. `NSBitmapImageRep` / ImageIO 确认为 PNG  
4. 宽高 ≤ 128（防恶意超大图；正常为 48/72）  

### 5.4 Channel 处理

```text
app_icon 到达
  → 校验 deviceToken
  → IconCache.store
  → app_icon_ok
  → post PhoneAppIconCacheDidChangeNotification

（IC-1）hello_ok / Connected 后短延迟：
  → 从 InboxStore 收集最近出现的 packageName（如 50 个）
  → missing = packagesMissingFrom(...)
  → 若非空发 app_icon_need
```

旧版 Android 忽略 `app_icon_need`；旧版 Mac 忽略 `app_icon`（已有未知 type 安全忽略）。

### 5.5 侧栏 UI

行布局（示意）：

```text
[ 未读点 ] [ 28×28 图标 ]  标题………………  时间
                         正文 / 验证码
─────────────────────────────────────
```

| 细节 | 定稿 |
|------|------|
| 图标大小 | 28×28 pt |
| 圆角 | 6 pt；`masksToBounds=YES` |
| 内容模式 | `ScaleProportionallyUpOrDown` |
| 与未读点 | 点仍在最左，或改为图标右下角小蓝点（**首版保持最左未读点**，改动小） |
| Section 头 | 可在标题左侧显示该组图标（可选加分） |
| 刷新 | 观察 `PhoneAppIconCacheDidChangeNotification`，仅 `reloadData` 或更新可见 cell |

### 5.6 占位绘制

```objc
+ (NSImage *)placeholderImageWithLabel:(NSString *)label package:(NSString *)package;
// 底色：hash(package) → 固定 HSL；文字：label 首字符 uppercase
```

OTP：模板 SF Symbol，tint `secondaryLabelColor`。

---

## 6. 时序图

### 6.1 IC-MVP（会话内首次）

```text
Android                         Mac
   |                              |
   |-- app_icon (wechat) -------->|  store png
   |<- app_icon_ok ---------------|
   |-- phone_notification ------->|  inbox + banner
   |                              |  sidebar shows icon
   |-- phone_notification ------->|  (no icon frame)
```

### 6.2 IC-1（重连补齐）

```text
   |<- hello_ok ------------------|
   |<- app_icon_need [mm, sms] ---|
   |-- app_icon (mm) ------------>|
   |-- app_icon (sms) ----------->|
```

---

## 7. 隐私、安全与体积

| 项 | 策略 |
|----|------|
| 内容 | 仅应用图标，不含通知正文增量隐私 |
| 传输 | 仍为 LAN 明文；图标也可能含品牌资产——仅已配对设备 |
| 校验 | 大小、类型、尺寸上限，防畸形图 |
| 存储 | 仅本机 Application Support |
| 日志 | 打 package + hash + byteLength，不打 base64 |
| 用户开关 | 可跟随「收件箱」；另设「同步 App 图标」默认 **开**（体积可控） |

---

## 8. 失败与边界

| 情况 | 行为 |
|------|------|
| 图标导出失败 | 通知照常；侧栏占位 |
| Mac 磁盘满 | store 失败打日志；占位 |
| 包名变更 / 应用卸载 | 旧缓存残留至 GC；无害 |
| 双端版本不对齐 | 忽略未知 type；功能降级为占位 |
| Adaptive 图标异常 | try/catch 跳过 |
| 同一包多用户图标（工作资料） | MVP 不区分；用当前用户可见的 ApplicationInfo |

---

## 9. 分阶段实施计划

| 阶段 | 内容 | 预估 |
|------|------|------|
| **IC-0** | 协议文档写入 companion-protocol；Mac IconCache 空壳 + 占位图接入侧栏 | 0.5～1 日 |
| **IC-MVP** | Android Exporter + 会话内首次 `app_icon`；Mac 收包落盘；侧栏显示真图标 | 1～1.5 日 |
| **IC-1** | `iconHash` 索引、`app_icon_need`、跨会话补齐与更新 | 0.5～1 日 |
| **IC-2** | （可选）系统通知 Attachment；设置开关 | 0.5 日 |

**建议首版交付：IC-0 + IC-MVP。**

### 验收清单（IC-MVP）

- [ ] 全部通知模式下，微信等 App 首次推送后侧栏出现与手机一致的图标  
- [ ] 同会话后续通知不再重复传图标（日志可证）  
- [ ] 重启 Mac 后图标仍在（磁盘缓存）  
- [ ] 无图标包名显示首字占位；OTP 显示 SF 占位  
- [ ] 超大/坏图被拒绝且通知链路不中断  
- [ ] 旧 Android / 旧 Mac 互连不崩溃  
- [ ] 日志无 base64 全文  

---

## 10. 关键文件（预期）

### Android

| 路径 | 变更 |
|------|------|
| `.../sms/AppIconExporter.kt` | 新增 |
| `.../channel/CompanionSession`（或等价） | `pushAppIcon` / need 处理 |
| `OtpNotificationListener` / 推送前钩子 | ensureIcon |
| 协议注释 / README | 一小节 |

### Mac

| 路径 | 变更 |
|------|------|
| `PhoneAppIconCache.h/.m` | 新增 |
| `CompanionChannel.m` | `app_icon` / need |
| `PhoneNotificationSidebarController.m` | 行内 NSImageView |
| `Makefile` | 新源文件 |
| `companion-protocol.md` | V2.3 |

### 文档

| 路径 | 变更 |
|------|------|
| 本文件 | 设计权威 |
| `companion-notification-inbox-sidebar-design.md` §7.3 | 链到本方案并标「已出专项」 |

---

## 11. 风险与拍板

| ID | 问题 | 建议默认 |
|----|------|----------|
| I1 | IC-MVP 是否等 IC-1 再上 | **先 MVP 会话内首次推送** |
| I2 | 边长 72 还是 48 | **优先 72，超 12KiB 降 48** |
| I3 | 是否改通知帧 | **不改**；独立 `app_icon` |
| I4 | 侧栏未读点位置 | **保持最左**；图标在点右侧 |
| I5 | 系统通知附件 | **IC-2 可选** |

---

## 12. 架构示意

```text
┌─────────────────────────────┐                      ┌──────────────────────────────────┐
│ Meo Companion (Android)     │                      │ MeoBrowser (macOS)                 │
│  PackageManager icons       │   app_icon           │  CompanionChannel                  │
│  AppIconExporter            │ ───────────────────► │    └─► PhoneAppIconCache (disk)    │
│  push throttle              │   app_icon_ok        │           │                        │
│                             │ ◄─────────────────── │           ▼                        │
│  NotificationPayloadBuilder │   phone_notification │  Sidebar cell NSImageView          │
│                             │ ───────────────────► │  (+ placeholder / SF for OTP)      │
└─────────────────────────────┘                      └──────────────────────────────────┘
```

---

## 13. 总结

用 **独立小图标帧 + Mac 包名缓存**，可以在通知侧栏稳定显示与手机一致的 App 图标，且不污染现有 `phone_notification`、不触碰系统通知栏图标限制。  
推荐先做 **会话内首次推送（IC-MVP）**，再补 **hash / need 增量（IC-1）**。  

确认 §11 默认后即可按 IC-0 → IC-MVP 开工。
