# MeoBrowser（Android）/ Meo Companion

> **演进中**：本应用正从纯 Companion 控制台改造为**极简 Android 浏览器**，配对 / 验证码 / 通知镜像下沉为设置中的互联功能。  
> 可行性：[android-browser-feasibility-and-plan.md](../../../docs/minimal-browser/android-browser-feasibility-and-plan.md)  
> 开发计划：[android-browser-development-plan.md](../../../docs/minimal-browser/android-browser-development-plan.md)  
> 验收：[android-browser-acceptance.md](../../../docs/minimal-browser/android-browser-acceptance.md)  
> 同步设计：[companion-sync-design.md](../../../docs/minimal-browser/companion-sync-design.md)  
> 协议：[companion-protocol.md](../../../docs/minimal-browser/companion-protocol.md)

与 macOS MeoBrowser 局域网配对，可浏览网页，并将验证码 / 通知镜像推送到 Mac；可选同步快捷方式等。

## 要求

- Android Studio Hedgehog+ / JDK 17
- 手机与 Mac **同一 Wi‑Fi**（Bonjour `_meologin._tcp`）时使用互联功能
- 互联需授予短信与通知权限（浏览本身不需要）

## 构建

```bash
cd companion/android/MeoCompanion
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

## 使用（改造后）

1. 打开 App → **浏览器主界面**（无需先配对即可上网）
2. 菜单 → **设置 → 互联**：配对 / 安全码 / 就绪检测 / 向导
3. **设置 → 通知**：仅验证码 / 全部通知镜像
4. **设置 → 同步**：快捷方式等（默认总开关关）
5. 已保存固定安全码时，启动后会**自动连接** Mac

### 临时配对码 / 固定安全码

见设置 → 互联；协议与 Mac「登录助手」一致。

## 隐私

默认**不上传短信全文**，只传验证码、时间戳与设备 token。开启全部通知镜像或历史同步前会有明文 LAN 风险提示。

## 手机通知镜像

设置 → 通知中切换模式。设计见 [companion-notification-mirror-design.md](../../../docs/minimal-browser/companion-notification-mirror-design.md)。
