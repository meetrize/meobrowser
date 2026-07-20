# Meo Android 浏览器改造 — 开发计划（任务级）

> 基于 [android-browser-feasibility-and-plan.md](android-browser-feasibility-and-plan.md) 的分阶段实施计划。  
> 前置条件：Companion V2 配对 / `otp` / 通知镜像 MVP、Mac MeoBrowser 多标签与 Launchpad 已就绪。  
> 状态：**AB-0～AB-5 代码已落地**（2026-07-20）；真机互联/同步手测见 [android-browser-acceptance.md](android-browser-acceptance.md)  
> 协议：现用 [companion-protocol.md](companion-protocol.md) V2.1 + V3 sync；设计 [companion-sync-design.md](companion-sync-design.md)  
> Companion 现状：[companion/android/MeoCompanion/README.md](../../companion/android/MeoCompanion/README.md)

---

## 行为定稿（相对可行性报告）

| 项 | 定稿 |
|----|------|
| 应用入口 | `BrowserActivity`；浏览不依赖配对 |
| 包名 | **AB-0～AB-5 保持** `com.meobrowser.companion`；改名单独立项 |
| 显示名 | 可改为「MeoBrowser」（`strings.xml` / 桌面标签）；不改 applicationId |
| UI 框架 | **View + ViewBinding**（不加 Compose，控体积） |
| 渲染 | 系统 `WebView` + 可选 `androidx.webkit` |
| 启动自动连接 | 安全码模式 + 已存凭据 → 默认开；失败静默退避，不挡浏览 |
| Companion UI | 全部迁入「设置 → 互联 / 通知 / 同步」；删除或降级 `MainActivity` 为入口转发 |
| 「同步浏览」 | **书签同步**；打开的标签不做全量同步，二期做「发送到对端」 |
| 默认同步范围 | 总开关默认关；若用户打开总开关，**仅快捷方式默认勾选**；历史/书签默认不勾 |
| 冲突策略 | 记录级 LWW（`updatedAt` + `deviceId` 决胜）；MVP 无冲突 UI |
| 标签上限 | 默认 8，设置可调至 12 |
| 省内存模式 | 设置项，中低端可默认开；销毁非当前 WebView 只留 URL |
| release 体积目标 | APK ≤ 8 MB（理想 ≤ 5 MB）；开 R8 + shrinkResources |
| 依赖禁令 | 无 Firebase / 无 Play Services / 无内嵌 Chromium |
| Mac 同步 | AB-4 起必须双边；无 Mac 时 Android 浏览+Companion 仍可交付 |

**首版对外演示目标：AB-0 + AB-1 + AB-2 + AB-3 + AB-4（快捷方式同步）。**  
**完整轻量浏览器 + 三项同步：再加 AB-5。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 | 约人周 |
|------|------|------|------|--------|
| Phase AB-0 | 立项与基线 | **完成** | 边界冻结、体积基线、V3 sync 草案、验收骨架 | 0.5～1 |
| Phase AB-1 | 浏览器壳 MVP | **完成** | 单 WebView 导航 + 设置入口占位 | 1～1.5 |
| Phase AB-2 | 多标签 + 新标签 + 下载 | **完成** | 多标签会话、快捷方式网格、下载列表 | 2～3 |
| Phase AB-3 | Companion 设置化 + 自动连接 | **完成** | 原能力进设置；启动即连；OTP/镜像回归 | 1～1.5 |
| Phase AB-4 | 快捷方式同步 | **完成** | 协议 V3 子集 + 双端 merge | 2～3 |
| Phase AB-5 | 历史/书签同步与打磨 | **完成** | 分项同步、省内存、指标与真机验收 | 2～3 |
| Phase AB-6 | 二期互联增强 | 不做（本计划） | Send Tab、帧加密等 | — |

---

## Phase AB-0：立项与基线

**目标**：指标与边界可验收；后续阶段不争论「做不做」。

### 任务清单

#### 0A — 文档与决策

- [x] **0.1** 确认可行性报告与本计划已入库；在可行性报告头部链到本文件
- [x] **0.2** 拍板 §「行为定稿」表（包名保留、同步默认、书签定义）——结果写回本文件「定稿」列若有变更
- [x] **0.3** 新建 `docs/minimal-browser/companion-sync-design.md` 骨架：数据模型（shortcut/history/bookmark）、LWW、tombstone、分片、`sync_*` 消息表（可先只写 shortcut）
- [x] **0.4** 新建 `docs/minimal-browser/android-browser-acceptance.md`：复制可行性报告 §7 为可勾选清单 + 体积/启动测量步骤
- [x] **0.5** 更新 Companion README：注明「将演进为 Android MeoBrowser」，链到可行性报告与本计划

#### 0B — 工程基线

- [x] **0.6** 记录当前 debug/release APK 大小（开启 minify 前后各测一次更佳）
- [x] **0.7** 确认 `minSdk` / `targetSdk` / JDK；依赖清单评审（现有 Material 是否保留——**定稿：AB-1 可暂留，AB-2 体积门禁时再评估降级**）
- [x] **0.8** `app/build.gradle.kts`：为 release 预备 `isMinifyEnabled = true`、`isShrinkResources = true`（可先不强制 CI，AB-2 起作为门禁）
- [x] **0.9** 规划包目录：`browser/`、`settings/`、`sync/`（空包或 README 占位即可）

**完成标准**：定稿表无未决项；基线数字写入 acceptance；sync 设计骨架可评审。

---

## Phase AB-1：浏览器壳 MVP

**目标**：打开 App 即能上网；设置入口存在但不要求迁完 Companion。

### 任务清单

#### 1A — 入口与布局

- [ ] **1.1** 新增 `BrowserActivity` + `activity_browser.xml`：顶栏（后退/前进/刷新/地址栏/菜单）+ `WebView` 容器
- [ ] **1.2** `AndroidManifest`：`BrowserActivity` 设为 `MAIN`/`LAUNCHER`；`MainActivity` 暂保留（AB-3 再删或改为 alias）
- [ ] **1.3** 应用显示名改为「MeoBrowser」（或「Meo」——按 0.2 定稿）
- [ ] **1.4** 主题：浅色/跟随系统；避免重型 Material 动态色依赖新增

#### 1B — 导航核心

- [ ] **1.5** `BrowserAddressBar` 逻辑：回车加载；裸域名补 `https://`；非 URL 走默认搜索引擎（设置常量即可，完整设置页 AB-3）
- [ ] **1.6** `WebViewClient`：更新标题、URL、加载错误页（简单 HTML 或 Toast）
- [ ] **1.7** `WebChromeClient`：进度条（可选细条）；`onReceivedTitle`
- [ ] **1.8** 后退/前进/刷新按钮与 `canGoBack`/`canGoForward` 同步
- [ ] **1.9** **延迟创建 WebView**：`onCreate` 先 inflate 壳，首帧后再 `addView(WebView)`（利于冷启动）

#### 1C — 设置占位

- [ ] **1.10** 菜单 →「设置」打开 `SettingsActivity`（或 Preference 风格 Fragment 宿主）
- [ ] **1.11** 设置首页分组占位：通用 / 互联 / 通知 / 同步 / 关于（互联等可显示「即将迁移」）
- [ ] **1.12** 「关于」页链到隐私说明短文（LAN 明文、默认不传短信全文）

#### 1D — 回归与门禁

- [ ] **1.13** 未配对、无短信权限时仍可浏览
- [ ] **1.14** 冷启动日志：记录 `Application.onCreate` → 首屏可点击地址栏耗时（手工即可）

**完成标准**：安装后直接打开网页；不进入旧 Companion 首页也能用；Companion 旧入口暂仍可从设置或保留的 Activity 打开（过渡期允许双入口）。

**关键文件（预期）**

| 路径 | 动作 |
|------|------|
| `.../browser/BrowserActivity.kt` | 新增 |
| `.../res/layout/activity_browser.xml` | 新增 |
| `.../settings/SettingsActivity.kt` | 新增 |
| `.../AndroidManifest.xml` | 改 launcher |
| `.../res/values/strings.xml` | 显示名等 |

---

## Phase AB-2：多标签 + 新标签页 + 下载

**目标**：对齐 Mac 核心浏览体验子集；本地快捷方式模型为同步预留字段。

### 任务清单

#### 2A — 多标签

- [ ] **2.1** 模型 `BrowserTab`：`id`、`title`、`url`、`isLoading`、`isNewTabPage`、可选 `webView`
- [ ] **2.2** `TabManager`：增/关/切；默认上限 8；超限 Toast/Snackbar
- [ ] **2.3** 标签栏 UI：横滑 `RecyclerView` 或 `TabLayout` 轻量实现；「+」新建
- [ ] **2.4** 显示策略：仅当前标签 WebView `VISIBLE`，其余 `GONE` + `onPause`
- [ ] **2.5** 会话恢复：进程重启后恢复 URL/title/isNewTab 列表（SharedPreferences 或 JSON 文件）
- [ ] **2.6** 菜单：关闭当前标签、关闭其他（可选）

#### 2B — 新标签页快捷方式

- [ ] **2.7** `ShortcutItem` 模型：`id`（UUID）、`title`、`url`、`order`、`updatedAt`、`deviceId`（可空）、`deleted`（tombstone 预留）
- [ ] **2.8** `ShortcutStore`：CRUD + 默认站点列表 + JSON 持久化
- [ ] **2.9** `NewTabFragment`/`NewTabView`：网格展示；点击在当前标签打开 URL
- [ ] **2.10** 长按/编辑模式：增删改、拖拽排序（可用简化：上下移动按钮，拖拽可 AB-5 再补）
- [ ] **2.11** 新标签时隐藏 WebView、显示网格；加载 URL 后反过来
- [ ] **2.12** 字段与 Mac `BrowserShortcutStore` 对齐表写入 `companion-sync-design.md`（即使尚未接线）

#### 2C — 下载

- [ ] **2.13** `DownloadHub`：`WebView.setDownloadListener` → 委托系统 `DownloadManager`（或自管流）
- [ ] **2.14** 下载列表 UI（设置或菜单入口）：进行中 / 完成；点击用系统打开
- [ ] **2.15** 通知栏进度（DownloadManager 自带即可）；权限：Android 10+ 分区存储按官方写法
- [ ] **2.16** 不做断点续传 UI（与 Mac V1 对齐）

#### 2D — 轻量门禁

- [ ] **2.17** release 构建开启 R8；APK Analyzer 对照 ≤ 8 MB；超标则砍 Material 组件或换轻量控件
- [ ] **2.18** 文档记录：1 标签 about:blank / 新标签页 RSS 基线（中端机一次即可）
- [ ] **2.19** 更新 acceptance：多标签、快捷方式、下载勾选项

**完成标准**：三功能可手测；release APK 在目标带或有明确超标原因与削减计划。

**关键文件（预期）**

| 路径 | 动作 |
|------|------|
| `.../browser/tab/TabManager.kt` 等 | 新增 |
| `.../browser/newtab/ShortcutStore.kt` | 新增 |
| `.../browser/download/DownloadHub.kt` | 新增 |
| `.../res/layout/*tab*`, `*new_tab*` | 新增 |

---

## Phase AB-3：Companion 设置化 + 启动自动连接

**目标**：主界面是浏览器；原检测/配对/镜像/调试全部在设置中；启动自动连。

### 任务清单

#### 3A — 设置 IA 迁移

- [ ] **3.1** `settings/LinkSettingsFragment`：连接状态、鉴权模式、安全码/配对码、主机、连接按钮（从 `MainActivity` 抽逻辑）
- [ ] **3.2** 就绪检测五行 +「打开设置向导」迁入互联设置（复用 `SetupChecker` / `SetupWizardActivity`）
- [ ] **3.3** `settings/NotificationSettingsFragment`：镜像模式分段、隐私确认、通知使用权状态
- [ ] **3.4** `settings/DebugToolsFragment`（或「高级」折叠）：读最近验证码短信、手动推测试码——默认折叠或仅 `BuildConfig.DEBUG` 显示（定稿：**release 也保留但默认折叠**，便于真机排障）
- [ ] **3.5** 删除 launcher 上的 `MainActivity`；若需兼容旧快捷方式，用 `activity-alias` 指到 `BrowserActivity`
- [ ] **3.6** 前台服务通知文案：「Meo 互联已连接」等（替换纯 Companion 用语）

#### 3B — 启动自动连接

- [ ] **3.7** `PairingPrefs`：确认 `canAutoConnect`；新增 `autoConnectOnLaunch`（默认 true）
- [ ] **3.8** `BrowserActivity.onStart`（或 `Application`）：满足条件则 `CompanionConnectionService` 自动连接（复用现有安全码路径）
- [ ] **3.9** 失败指数退避；设置页展示 `lastError`；**禁止**自动弹全屏向导
- [ ] **3.10** 工具栏/菜单互联状态点：已连接 / 连接中 / 未连接；点击进互联设置

#### 3C — 回归

- [ ] **3.11** OTP：短信 + 通知栏验证码 → Mac 填码（与现网一致）
- [ ] **3.12** 通知镜像：`otp_only` / `all` 行为与 NM MVP 一致
- [ ] **3.13** 临时配对码路径仍可用
- [ ] **3.14** 更新 Companion README 使用说明为「浏览器设置内操作」
- [ ] **3.15** 更新 notification-mirror 设计/计划中「首页 UI」描述为「设置 → 通知」（状态说明即可，避免文档漂移）

**完成标准**：冷启动浏览 + 后台自动连上 Mac；设置内可完成配对与镜像；旧首页不再作为主入口。

**关键文件（预期）**

| 路径 | 动作 |
|------|------|
| `.../ui/MainActivity.kt` | 删或改为转发 |
| `.../settings/*Fragment.kt` | 新增 |
| `.../channel/CompanionConnectionService.kt` | 小改文案/触发 |
| `.../pairing/PairingPrefs.kt` | 自动连接开关 |
| `activity_main.xml` | 可删或仅向导复用 |

---

## Phase AB-4：快捷方式同步（V3 子集）

**目标**：连接且开启同步后，Mac ↔ Android 快捷方式 LWW 一致。

### 任务清单

#### 4A — 协议与文档

- [ ] **4.1** 完成 `companion-sync-design.md` 中 **shortcut** 专章（字段、tombstone、version/epoch）
- [ ] **4.2** 更新 `companion-protocol.md` 增加 **V3** 节：`sync_hello` / `sync_pull` / `sync_push` / `sync_chunk` / `sync_ack` / `sync_error`；未知 type 仍安全忽略
- [ ] **4.3** 约定：单帧 ≤ 64 KiB；shortcut 全量通常不分片，但 chunk 管线先打通（历史复用）

#### 4B — Android SyncEngine

- [ ] **4.4** `sync/SyncPrefs`：总开关、shortcut 开关、lastSyncAt、localEpoch
- [ ] **4.5** `sync/SyncEngine`：连接成功回调触发；本地 `ShortcutStore` 变更 debounce 后 `sync_push`
- [ ] **4.6** `CompanionSession` / Client：收发 sync_*；鉴权失败走 `sync_error`/`error`
- [ ] **4.7** Merge：按 `id` LWW；tombstone 优先于复活（按设计稿）
- [ ] **4.8** 设置 → 同步：总开关、快捷方式勾选、隐私文案、立即同步、最近同步时间

#### 4C — Mac 侧（必须）

- [ ] **4.9** `CompanionChannel` 识别 sync_*；校验 `deviceToken`
- [ ] **4.10** `BrowserShortcutStore`（或旁路 `ShortcutSyncMerger`）实现 merge API
- [ ] **4.11** Mac 登录助手/设置：与 Android 对称的同步开关（至少 shortcut）
- [ ] **4.12** Makefile 纳入新 `.m`；未知旧 Android 无 sync 时行为不变

#### 4D — 联调

- [ ] **4.13** 用例：仅 Android 增删 → 连上后 Mac 一致
- [ ] **4.14** 用例：仅 Mac 修改 → Android 一致
- [ ] **4.15** 用例：两端改同一 `id` → 新 `updatedAt` 胜出
- [ ] **4.16** 用例：总开关关 → 无 sync 帧；OTP/镜像不受影响
- [ ] **4.17** 用例：断线期间本地改，重连后收敛
- [ ] **4.18** acceptance 勾选快捷方式同步项

**完成标准**：设计 §验收中快捷方式同步条目通过；协议文档与实现一致。

**关键文件（预期）**

| 端 | 路径 | 动作 |
|----|------|------|
| Android | `.../sync/SyncEngine.kt` 等 | 新增 |
| Android | `.../channel/CompanionConnectionService.kt` | 扩展收发 |
| Mac | `SimpleBrowser/LoginAssist/Companion/*Sync*` | 新增 |
| Mac | `CompanionChannel.m` | 分支 |
| 文档 | `companion-protocol.md`、`companion-sync-design.md` | 更新 |

---

## Phase AB-5：历史 + 书签同步与打磨

**目标**：三项同步可独立开关；内存/体积达标；真机清单通过。

### 任务清单

#### 5A — 本地历史与书签

- [ ] **5.1** `HistoryStore`：访问写入（防抖）；列表 UI（按日分组简化版）；上限 500～1000 可配
- [ ] **5.2** `BookmarkStore`：星标当前页、书签列表；与快捷方式数据分离
- [ ] **5.3** 工具栏星标按钮（可选）；菜单入口「书签」「历史」

#### 5B — 同步扩展

- [ ] **5.4** 协议补 history / bookmark 记录类型（仍用 sync_push 载荷 `kind` 字段）
- [ ] **5.5** Android / Mac merge 与开关分项
- [ ] **5.6** 历史默认同步关；开启时强提示明文风险
- [ ] **5.7** 大数据分片：`sync_chunk` 端到端测（故意造超限载荷）

#### 5C — 性能与省内存

- [ ] **5.8** 设置「省内存模式」：非当前标签销毁 WebView，只保留 URL/title
- [ ] **5.9** 标签上限设置 8～12
- [ ] **5.10** favicon 磁盘缓存限容（若已做拉取）
- [ ] **5.11** 复测 release APK 与冷启动；写入 acceptance 实测值

#### 5D — 小而必要体验（可选纳入本阶段，超时则顺延 AB-6）

- [ ] **5.12** 页内查找（`WebView.findAllAsync`）
- [ ] **5.13** 桌面版网站 UA 切换
- [ ] **5.14** 分享当前链接（系统 Share）；预留「发送到 Mac」入口 disabled 或进 AB-6

#### 5E — 收尾

- [ ] **5.15** 多厂商手测：小米/原生连接保活 + 同步（至少 2 台）
- [ ] **5.16** 全文更新 README、可行性报告状态、acceptance 全部勾选
- [ ] **5.17** 评估是否立项改 `applicationId` / 应用商店（结论记文档，本阶段不执行除非拍板）

**完成标准**：可行性报告 §7 全部可勾；指标有记录；无严重同步环或刷屏。

---

## Phase AB-6：二期（本计划不实施）

- 发送标签到 Mac / 到手机（`open_url` / Send Tab）
- 帧级 AES-GCM
- 阅读列表 / 待读队列双向同步
- 通知镜像白名单、应用内通知面板
- Compose 迁移或包名正式更换
- 应用商店上架材料

---

## 建议实现顺序（单人）

```text
AB-0 文档与基线
  → AB-1 浏览器壳（可先合并进现有 module）
  → AB-2 多标签 + 新标签 + 下载 + 体积门禁
  → AB-3 设置化 Companion + 自动连接（OTP/镜像回归）
  → AB-4 冻结 shortcut 协议 → Android SyncEngine ∥ Mac merge
  → AB-5 历史/书签 + 打磨
```

**可并行**：

| 时段 | 人 A | 人 B |
|------|------|------|
| AB-1～2 | Android 浏览壳与标签 | （无 Mac 任务） |
| AB-3 | Android 设置迁移 | Mac 仅回归现有 Companion（可选） |
| AB-4 | Android SyncEngine | Mac Sync + Channel（**先冻结 JSON schema**） |
| AB-5 | Android 历史书签 | Mac 历史书签 store + 设置 |

---

## 风险与缓解（执行层）

| 风险 | 缓解 | 落在阶段 |
|------|------|----------|
| Material 导致 APK 超标 | AB-2.17 门禁；必要时换 AppCompat 控件 | AB-2 |
| 多标签 OOM | 上限 + 省内存模式 | AB-2 / AB-5 |
| 设置迁移回归破坏 OTP | AB-3 专项回归清单；先抽逻辑再拆 UI | AB-3 |
| 同步环（两端互相推） | epoch / ack；同 version 不回推 | AB-4 |
| Mac 排期滞后 | Android AB-1～3 可独立交付；AB-4 明确依赖 Mac | AB-4 |
| 厂商杀 FGS | 复用向导；文案引导电池白名单 | AB-3 / AB-5 |

---

## 附录 A：手动验收清单（MVP = AB-4 结束）

复制到测试时使用：

### 浏览

- [ ] 冷启动无需配对即可打开 URL / 搜索
- [ ] 后退、前进、刷新正常
- [ ] 多标签增删切；杀进程后会话恢复
- [ ] 新标签页快捷方式增删改排，重启仍在
- [ ] 下载文件可完成并打开

### 互联

- [ ] 已存安全码时启动后自动连接
- [ ] 设置 → 互联：检测、向导、配对码/安全码均可用
- [ ] 设置 → 通知：仅验证码 / 全部通知 + 确认框
- [ ] OTP 填码与通知镜像与改造前一致
- [ ] 关「启动自动连接」后不再自动 hello

### 同步（快捷方式）

- [ ] 默认同步总开关为关；打开后仅快捷方式默认勾选（若按定稿实现）
- [ ] Android ↔ Mac 快捷方式双向收敛（LWW）
- [ ] 关同步后无 sync 帧；OTP 仍可用
- [ ] 隐私文案可见

### 轻量

- [ ] release APK ≤ 8 MB（或记录例外）
- [ ] 标签达上限有提示

---

## 附录 B：关键路径速查

### Android（`companion/android/MeoCompanion/`）

```text
app/src/main/java/com/meobrowser/companion/
  browser/          # AB-1+
  settings/         # AB-3
  sync/             # AB-4+
  channel/          # 扩展
  pairing/
  sms/
  setup/
  ui/               # MainActivity 过渡后清理
```

### Mac

```text
SimpleBrowser/LoginAssist/Companion/   # Channel + Sync*
SimpleBrowser/NewTab/ 或 Shortcut store # merge
Makefile
docs/minimal-browser/companion-protocol.md
docs/minimal-browser/companion-sync-design.md
```

---

## 附录 C：与可行性报告阶段映射

| 可行性报告 | 本计划 |
|------------|--------|
| §4 Phase AB-0 | 本文件 Phase AB-0 |
| §4 Phase AB-1 | Phase AB-1 |
| §4 Phase AB-2 | Phase AB-2 |
| §4 Phase AB-3 | Phase AB-3 |
| §4 Phase AB-4 | Phase AB-4 |
| §4 Phase AB-5 | Phase AB-5 |
| §5 / AB-6 建议 | Phase AB-6（不实施） |
```
