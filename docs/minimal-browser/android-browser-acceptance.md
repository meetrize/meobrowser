# Meo Android 浏览器 — 验收清单

> 对应：[android-browser-feasibility-and-plan.md](android-browser-feasibility-and-plan.md) §7 · [android-browser-development-plan.md](android-browser-development-plan.md)  
> 状态：AB-0～AB-5 代码完成（2026-07-20）；下列手测项待真机勾选

---

## 基线测量

| 项 | 值 | 日期 |
|----|-----|------|
| debug APK（改造前） | 5.6 MB | 2026-07-20 |
| debug APK（AB-5 后） | **6.6 MB**（6014665 bytes） | 2026-07-20 |
| release APK（R8） | 已开启 minify/shrink；需本机签名配置后复测，目标 ≤ 8 MB | — |
| minSdk / targetSdk | 26 / 34 | — |
| 依赖 | appcompat, material, constraintlayout, recyclerview, fragment, coroutines | 无 Firebase/Play Services |
| Mac `make browser` | 通过（含 CompanionSyncSettings / CompanionShortcutSync） | 2026-07-20 |

### 测量步骤

```bash
cd companion/android/MeoCompanion
./gradlew assembleDebug
ls -la app/build/outputs/apk/debug/app-debug.apk
```

冷启动：logcat 过滤 `MeoBrowserColdStart`。

---

## 浏览

- [ ] 冷启动无需配对即可打开 URL / 搜索
- [ ] 后退、前进、刷新正常
- [ ] 多标签增删切；杀进程后会话恢复
- [ ] 新标签页快捷方式增删改排，重启仍在
- [ ] 下载文件可完成并打开
- [ ] 页内查找 / 桌面 UA / 分享可用
- [ ] 省内存模式可开关

## 互联

- [ ] 已存安全码时启动后自动连接
- [ ] 设置 → 互联（原 Companion 页）：检测、向导、配对码/安全码均可用
- [ ] 设置内通知镜像：仅验证码 / 全部通知 + 确认框
- [ ] OTP 填码与通知镜像与改造前一致
- [ ] 关「启动自动连接」后不再自动 hello

## 同步

- [ ] 默认同步总开关为关；打开后仅快捷方式默认勾选
- [ ] Android ↔ Mac 快捷方式双向收敛（LWW）
- [ ] 关同步后无 sync 帧；OTP 仍可用
- [ ] 历史 / 书签可独立开关（两端开启后）

## 轻量

- [x] debug APK ≈ 6.6 MB（≤ 8 MB）
- [ ] release APK ≤ 8 MB（签名后复测）
- [ ] 标签达上限有提示
