# Meo Companion（Android）

与 MeoBrowser 局域网配对，读取短信中的验证码并推送到 Mac 自动填入。

协议详见：[companion-protocol.md](../../../docs/minimal-browser/companion-protocol.md)

## 要求

- Android Studio Hedgehog+ / JDK 17
- 手机与 Mac **同一 Wi‑Fi**（Bonjour `_meologin._tcp`）
- 授予短信与通知权限

## 构建

```bash
cd companion/android/MeoCompanion
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

若无 wrapper，用 Android Studio 打开本目录同步后生成。

## 权限检测与设置向导

- **首页「就绪检测」**：实时显示短信 / 通知 / 电池优化 / Wi‑Fi / Mac 连接五项状态（✓/✗），点某一行也可打开向导。
- **设置向导**（首次未就绪自动弹出，或点「打开设置向导」）：
  1. 欢迎与总览  
  2. 授予短信权限  
  3. 授予通知权限（Android 13+）  
  4. 加入电池优化白名单  
  5. 确认 Wi‑Fi  
  6. 输入配对码连接 MeoBrowser  

完成后首页摘要应变为「就绪 …：可自动拦截短信并推码」。

## 使用

### 临时配对码

1. Mac「登录助手」底部查看 6 位配对码  
2. App 选「临时配对码」，输入后连接  

### 固定安全码（推荐日常）

1. Mac「登录助手」切换「固定安全码」并保存 4～12 位安全码  
2. App 选「固定安全码」，填入相同码与主机 `IP:端口`，连接一次  
3. 之后打开 App 会默认自动连接（端口在 Mac 侧固定，勿轻易更换）

### 其它

1. 状态「已配对 / 连接保持中」后，含 4～8 位数字的短信会自动推码  
2. 联调：
   - **读取最近验证码短信（测试）**：主动扫收件箱并解析（验证 READ_SMS，不依赖实时广播）
   - **手动发送测试码**：手输码推到 Mac
   - Bonjour 失败时可填 `MacIP:端口`（与 Mac 显示的固定端口一致）

## 隐私

默认**不上传短信全文**，只传验证码、时间戳与设备 token。

## 手机通知镜像（MVP）

Companion 可选择「仅验证码 / 全部通知」；全部模式下过滤噪音后推送到 MeoBrowser，在 Mac 系统通知栏以标题前缀展示来源（图标仍为 MeoBrowser）。

1. 手机与 Mac 已配对且连接保持中  
2. Companion 首页切到「全部通知」并确认隐私提示  
3. Mac「登录助手」确认已勾选「接收手机通知镜像」，并允许系统通知  
4. 手机收到普通通知后，Mac 通知中心应出现「App名 · 标题」横幅  

- 设计：[companion-notification-mirror-design.md](../../../docs/minimal-browser/companion-notification-mirror-design.md)
- 开发计划：[companion-notification-mirror-development-plan.md](../../../docs/minimal-browser/companion-notification-mirror-development-plan.md)
- 协议 V2.1：[companion-protocol.md](../../../docs/minimal-browser/companion-protocol.md)
