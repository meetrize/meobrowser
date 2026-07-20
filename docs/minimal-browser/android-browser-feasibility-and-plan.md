# Meo Android 浏览器改造 — 可行性报告与详细方案

> 目标：将现有 **Meo Companion** 改造为 **极简 Android 浏览器（MeoBrowser for Android）**，把配对 / 验证码 / 通知镜像等能力下沉为「设置中的互联功能」；突出与 macOS MeoBrowser 的局域网互联互通。  
> 状态：**AB-0～AB-5 代码已落地**（2026-07-20）；真机手测见 [android-browser-acceptance.md](android-browser-acceptance.md)  
> 开发计划（任务级）：[android-browser-development-plan.md](android-browser-development-plan.md)  
> 同步设计：[companion-sync-design.md](companion-sync-design.md)  
> 关联：[companion-protocol.md](companion-protocol.md) · [companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [design.md](design.md) · [multi-tab-design.md](multi-tab-design.md) · [new-tab-launchpad-design.md](new-tab-launchpad-design.md) · [download-design.md](download-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [companion/android/MeoCompanion/README.md](../../companion/android/MeoCompanion/README.md)

---

## 0. 一句话结论

**可行，且建议分阶段落地。**  
现有 Companion 的 Bonjour + 固定安全码 + `deviceToken` 通道已具备「打开即连」基础；通知镜像、OTP 推送可原样迁入设置页。浏览器本体用系统 **Android System WebView（Chromium）** 即可在「小体积、低内存、快启动」上成立。  
**最大风险不在「能不能做浏览器」，而在：WebView 进程内存、同步冲突模型、以及产品边界（不要做成第二个 Chrome）。** 建议以 **「手机上的 Meo 轻量端 + Mac 互联」** 定位，用局域网同步拉开差异化。

---

## 1. 产品愿景与定位

### 1.1 愿景

| 维度 | 定义 |
|------|------|
| 产品名（建议） | **MeoBrowser**（Android）；包名可演进为 `com.meobrowser.app`，保留 Companion 能力模块 |
| 一句话 | 手机上的极简 MeoBrowser：浏览轻、启动快，连上 Mac 后快捷方式 / 历史 / 书签自动同步，验证码与通知镜像继续服务电脑端 |
| 不是什么 | 不是 Chrome 替代品；不做扩展商店、不做独立密码管理器、不做云账号强制登录 |
| 差异化 | **同 Wi‑Fi 与 Mac MeoBrowser 深度互联**（同步 + OTP + 通知镜像 + 后续 Send Tab / 接力） |

### 1.2 与现网能力的关系

```text
今日：Companion App（配对控制台）──LAN──► Mac MeoBrowser（主浏览器）
未来：Android MeoBrowser（主界面=浏览）
         ├─ 设置 → 互联 / 配对 / 通知镜像 / 同步（原 Companion UI）
         └─ 前台服务 + Listener ──LAN──► Mac MeoBrowser
```

| 现有能力 | 改造后位置 | 行为变化 |
|----------|------------|----------|
| 固定安全码自动连接 | 启动后台 / 设置「互联」 | **启动浏览器即尝试自动连接**（用户已确认的设想） |
| 就绪检测 / 设置向导 | 设置 → 互联 → 检测与向导 | 首页不再堆检测项 |
| 临时配对码 / 安全码 | 设置 → 互联 → 配对 | 逻辑复用 `PairingPrefs` + `CompanionConnectionService` |
| 仅验证码 / 全部通知 | 设置 → 通知镜像 | 逻辑复用现有 MVP |
| 手动读短信 / 推测试码 | 设置 → 调试（可折叠或仅 Debug） | 日常用户可藏深 |
| OTP / `phone_notification` | 后台通道（无变化） | 与浏览进程解耦，前台服务保活 |

### 1.3 设计原则（硬约束）

1. **轻量优先**：APK 体积、冷启动、常驻 RSS 作为验收指标，功能冲突时砍功能不砍指标。  
2. **WebView 系统引擎**：不内嵌完整 Chromium / GeckoView（体积与内存不可接受）。  
3. **互联是卖点**：同步与 Companion 通道同属一等公民，但不阻塞离线浏览。  
4. **隐私默认保守**：同步默认关或「仅快捷方式」；通知镜像默认 `otp_only`；明文 LAN 风险在设置中披露。  
5. **与 Mac 行为对齐但不照搬 UI**：多标签、新标签快捷方式、下载语义对齐；Android 用 Material 极简壳。

---

## 2. 可行性分析

### 2.1 需求拆解与可行性矩阵

| # | 需求 | 可行性 | 依据 / 条件 |
|---|------|--------|-------------|
| 1 | 启动后用上次安全码自动连接 | ✅ 高 | 协议已支持固定安全码；`PairingPrefs.canAutoConnect` + `CompanionConnectionService` 已有自动重连；需改为 **Application / 浏览主界面 onCreate 即触发**，不依赖旧首页 |
| 2 | 检测 / 配对 / 通知 / 手动推送迁入设置 | ✅ 高 | 纯 UI 重构；业务模块（`SetupChecker`、`Otp*`、`NotificationMirror*`）可原样迁移 |
| 3 | 极简多标签浏览器 | ✅ 高 | `WebView` / `AndroidX WebKit`；业界成熟；内存需 **限制同时存活 WebView 数** |
| 4 | 新标签页快捷方式（类 Launchpad） | ✅ 高 | RecyclerView 网格；数据模型对齐 Mac `BrowserShortcutStore` 字段 |
| 5 | 下载 | ✅ 高 | `DownloadListener` + `DownloadManager` 或自管文件流；语义对齐 Mac「静默落盘 + 列表」 |
| 6 | 连接后可配置自动同步（快捷方式 / 历史 / 书签） | ⚠️ 中高 | **协议需 V3 扩展**；冲突策略、增量、体积限制要设计；首版可先做快捷方式单向/双向 |
| 7 | 体积小、内存小、启动快 | ⚠️ 中 | 依赖依赖裁剪、单 Activity、延迟初始化 WebView、限制标签数；**WebView 本身是大头**，需设硬指标并验收 |

### 2.2 技术选型结论

| 项目 | 推荐 | 不推荐 | 理由 |
|------|------|--------|------|
| 渲染 | **系统 WebView**（`android.webkit` + `androidx.webkit`） | 内嵌 Chromium、GeckoView、Crosswalk | 包体 +30～80MB+；与「极简」冲突 |
| UI | **单 Activity + Fragments / Compose 二选一** | 多 Activity 栈过深 | 启动快、状态清晰；建议 **View 系统 + 极少依赖** 更易控体积 |
| 语言 | 继续 **Kotlin** | 重写 Java | 现有 Companion 已是 Kotlin |
| 网络发现 | 保留 **Bonjour `_meologin._tcp` + sticky 端口缓存** | 仅手动 IP | 已验证 |
| 同步传输 | **扩展现有长度前缀 JSON 帧**（可分片） | 另起 HTTP 服务 | 复用鉴权与连接生命周期 |
| 本地存储 | Room 或轻量 SQLite / DataStore | 过重 ORM 全家桶 | 历史/书签需查询；首版可用 SQLiteOpenHelper 控体积 |
| 依赖策略 | 仅 `appcompat` / `core-ktx` / `recyclerview` / `webkit` / coroutines | Material 全量、Firebase、Play Services | 每加一个库都要过体积评审 |

**Compose vs View**：Compose 开发快但 Runtime 增体积；若「体积第一」优先 **传统 View + ViewBinding**（与现工程一致）。若团队更熟 Compose，可用但必须测 release APK 增量。

### 2.3 关键约束与风险

| 风险 | 等级 | 说明 | 缓解 |
|------|------|------|------|
| WebView 多标签内存暴涨 | 高 | 每标签一 WebView，与 Mac 同构问题 | 默认上限 8～12 标签；后台标签可 `onPause` + 可选「冻结」策略；超出提示关闭 |
| 厂商杀后台导致断连 / 丢 OTP | 高 | 小米等已是 Companion 痛点 | 保留电池优化白名单向导；前台服务通知「Meo 互联已连接」 |
| 同步冲突（两端同时改快捷方式） | 中 | 无中心时钟权威 | 首版：**LWW（按字段 `updatedAt`）+ 设备 id**；冲突记日志；不做 OT |
| 明文 LAN 同步敏感历史 | 中 | 与通知镜像同类 | 默认同步范围最小；设置强提示；二期帧加密 |
| 协议帧 64 KiB 上限 | 中 | 历史批量易超限 | 分片消息 `sync_chunk`；或按页拉取 |
| System WebView 版本碎片 | 中 | 旧机 WebView 过旧 | `minSdk 26` 可接受；关键站点问题文档化 |
| 包名 / 应用身份变更 | 低 | 升级路径 | 首版可保持 `com.meobrowser.companion` 或提供迁移说明；正式版再改名 |
| 与「专业用户 Mac 路线图」功能不对齐 | 低 | Android 不做 Inspector 等 | 明确 Android 子集；Mac 仍是主工作台 |

### 2.4 工作量粗估（单人等效）

| 阶段 | 内容 | 人周（约） |
|------|------|------------|
| A0 | 信息架构、协议草案、指标基线 | 0.5～1 |
| A1 | 壳：单 Activity 浏览器 MVP（地址栏 + 单 WebView + 设置入口） | 1～1.5 |
| A2 | 多标签 + 新标签快捷方式 + 下载 | 2～3 |
| A3 | Companion UI 迁入设置 + 启动自动连接 | 1～1.5 |
| A4 | 同步协议 V3 + 快捷方式同步 | 2～3 |
| A5 | 历史 / 书签同步 + 打磨指标 | 2～3 |
| 联调与真机（多厂商） | 贯穿 | +1～2 |

**MVP（可对外演示）建议范围 = A1 + A2 核心 + A3 + A4 快捷方式同步。** 约 **6～9 人周**。  
完整「浏览 + 三项同步 + 指标达标」约 **10～14 人周**。

### 2.5 可行性总结

| 判断 | 说明 |
|------|------|
| **产品可行** | 定位清晰，与 Mac 形成「主机 + 轻量端」组合，避免与 Chrome 正面竞争 |
| **技术可行** | 浏览用系统 WebView；互联复用现有通道；同步需协议升级但路径明确 |
| **需警惕** | 内存与同步是两大工程难点；必须用阶段门禁与量化指标约束范围 |
| **建议决策** | **立项做**；按下文 §4 分阶段交付，首期不承诺「完整 Chrome 功能集」 |

---

## 3. 详细方案

### 3.1 信息架构（IA）

```text
主界面（浏览器）
├── 标签栏（可横滑）+「+」
├── 工具栏：后退 / 前进 / 刷新 / 地址栏 / 菜单
├── 内容区：WebView 或「新标签页」快捷方式网格
└── 菜单
      ├── 新标签 / 关闭标签
      ├── 书签 / 历史（本地，可同步）
      ├── 下载
      ├── 分享 / 桌面快捷方式（系统）
      ├── 设置
      └── 互联状态角标（已连接 / 未连接，点进设置）

设置
├── 通用（搜索引擎、主页=新标签、默认下载目录说明）
├── 外观（主题跟随系统；少选项）
├── 互联与配对          ← 原 Companion 核心
│     ├── 连接状态 / 一键重连
│     ├── 鉴权：临时配对码 | 固定安全码
│     ├── 主机 IP:端口 / Bonjour
│     ├── 就绪检测（五项）与设置向导
│     └── 注销设备 / 清除 token
├── 通知与验证码
│     ├── 镜像模式：仅验证码 | 全部通知
│     ├── 通知使用权引导
│     └── （高级）手动读短信 / 推测试码
├── 自动同步             ← 新
│     ├── 总开关 + 仅 Wi‑Fi / 仅已连接时
│     ├── ☑ 新标签快捷方式
│     ├── ☑ 历史记录
│     ├── ☑ 书签（「同步浏览」建议落地为书签；见 §3.5）
│     └── 最近同步时间 / 立即同步 / 冲突说明
└── 关于 / 隐私说明
```

**启动路径**：

```text
冷启动
  → 恢复标签会话（轻量：仅 URL/title，WebView 懒创建）
  → 若 prefs.canAutoConnect → startForegroundService 自动 hello
  → 首屏优先展示「新标签页」或上次标签（可配置）
  → 同步：连接成功且开关开 → 后台 pull/push（不挡首屏）
```

### 3.2 架构分层

```text
┌──────────────────────────────────────────────────────────┐
│  UI：BrowserActivity / TabStrip / Toolbar / NewTabGrid   │
│       Settings* Fragments                                │
├──────────────────────────────────────────────────────────┤
│  Browser Core：TabManager / Navigation / DownloadHub     │
│  Store：ShortcutStore / HistoryStore / BookmarkStore     │
├──────────────────────────────────────────────────────────┤
│  Sync Engine：SyncScheduler / Merge / ChunkCodec         │
├──────────────────────────────────────────────────────────┤
│  Companion Channel（现有）：Discovery / Session / OTP /   │
│  NotificationMirror / （新）Sync messages                │
├──────────────────────────────────────────────────────────┤
│  Android：WebView · NotificationListener · FGS           │
└──────────────────────────────────────────────────────────┘
                              │ LAN JSON
                              ▼
                    macOS MeoBrowser
              CompanionChannel + SyncStore
```

**原则**：浏览核心不依赖「已连接」；互联与同步失败只影响对应设置状态，不导致无法上网。

### 3.3 浏览器功能范围（与 Mac 对齐）

#### 3.3.1 MVP 必做（与用户设想对齐）

| 功能 | Android 实现要点 | 对齐 Mac |
|------|------------------|----------|
| 地址栏导航 | URL 规范化、http(s) 默认、搜索引擎回退 | 同 L1 |
| 前进 / 后退 / 刷新 | `WebView` 历史栈；工具栏按钮 | 同 |
| 多标签 | `TabManager`；每标签一个 WebView；切换 hide/show | 同 multi-tab 语义，UI 用 Android 标签条 |
| 新标签快捷方式 | 网格 + 增删改排 + 持久化 JSON | 字段对齐 Launchpad shortcut 模型 |
| 下载 | 系统 DownloadManager 或自管；简易列表 | 静默下载 + 可打开文件 |
| 会话恢复 | 进程被杀后恢复 URL 列表 | 对齐「恢复标签」轻量版 |
| 设置中的互联全家桶 | 见 §3.1 | 保留现有 Companion 能力 |

#### 3.3.2 建议同步做的「小而必要」

| 功能 | 理由 |
|------|------|
| 找页内文字 | 用户刚在 Mac 做了 find-in-page；Android WebView 有 `findAllAsync` |
| 桌面模式 UA 切换 | 手机站/桌面站调试；与专业路线图 UA 思路一致但更轻 |
| 分享链接到系统 | 零成本；互联场景下也可二期「发送到 Mac」 |
| 安全连接指示（锁标） | 基础可信度 |
| 外部链接 Intent | 成为默认浏览器可选（不强制） |

#### 3.3.3 明确首期不做

| 不做 | 原因 |
|------|------|
| 扩展 / 广告拦截完整引擎 | 体积与维护成本 |
| 内嵌完整开发者工具 | Mac 侧才是工作台 |
| 云账号、跨网中继 | 与现隐私模型冲突；外出场景另案 |
| 密码同步 / 自动填充全站 | 安全与合规面大；可二期评估 |
| 阅读模式 / 翻译 | 非差异化 |
| Chromium 级下载断点 UI | 可后续 |

### 3.4 启动自动连接（需求 1）详设

**触发条件**（全部满足）：

1. `authMode == SECURITY_CODE`  
2. 已保存 `securityCode` 或有效 `deviceToken`  
3. 已保存 `lastHost` + `lastPort`（或 Bonjour 可发现）  
4. 用户未关闭「启动时自动连接」（默认 **开**）

**行为**：

- `BrowserActivity.onStart` / `Application`：调用现有 `CompanionConnectionService` 连接逻辑（与今日 `MainActivity` 自动连接同源）。  
- 连接中：菜单互联图标动画或状态点。  
- 失败：静默退避重试（指数退避，上限如 5 分钟）；设置页显示上次错误。  
- **不**在自动连接失败时弹全屏向导（避免打断浏览）；仅首次安装走向导。

### 3.5 自动同步（需求 6）详设

用户原文「同步浏览」建议产品化定义为：

| 用户说法 | 建议产品名 | 内容 |
|----------|------------|------|
| 新标签页快捷方式 | 快捷方式同步 | title、url、order、folderId（若有）、favicon URL 可选、updatedAt |
| 同步历史 | 历史同步 | url、title、visitTime、visitCount（可截断条数） |
| 同步浏览 | **书签同步**（推荐命名） | 书签树或扁平列表；若暂无书签模块则 Phase 内先做「星标=快捷方式」避免双模型 |

> 若希望「同步浏览」= 打开的标签列表，可单列 **「打开的标签（Send Tabs / 接力）」**，与书签分开，避免概念混淆。建议二期做「发送标签到另一端」。

#### 3.5.1 同步策略（推荐）

| 项 | 定稿建议 |
|----|----------|
| 触发 | 连接成功后；设置变更后；本地数据变更 debounce 2～5s；手动「立即同步」 |
| 方向 | **双向**；以记录级 `updatedAt` + `id` 做 LWW |
| 删除 | 墓碑（tombstone）保留 N 天，避免一端删一端又复活 |
| 历史条数 | 默认最近 **500～1000** 条；可设置更少 |
| 快捷方式 | 全量通常很小，可整表版本号 + 全量替换或按 id merge |
| 传输 | 新消息类型；超限分片；压缩可选（二期） |
| 未连接 | 只写本地；连上再同步 |
| 冲突 UI | MVP 不弹冲突对话框；设置页「以哪端为准」高级选项可二期 |

#### 3.5.2 协议扩展草案（V3，需另文冻结）

在现有帧格式不变前提下新增，例如：

```text
sync_hello          Mac↔Android  交换 syncEpoch、支持的数据类型、设备名
sync_pull           请求某类数据 since=version
sync_push           推送变更集（records[]）
sync_chunk          分片（index/total/payload）
sync_ack            确认 applied version
sync_error          可读错误
```

鉴权：所有 sync_* 必须带有效 `deviceToken`（同 `otp`）。

**单帧仍 ≤ 64 KiB**；分片在应用层组装。

Mac 侧需新增 `SyncStore` / `CompanionChannel` 分支，并与 `BrowserShortcutStore`、历史、书签存储对接——**工作量与 Android 对等，必须双边排期**。

#### 3.5.3 设置项文案要点

- 总开关关闭时：不传任何浏览数据（OTP / 通知镜像按各自开关，独立）。  
- 开启历史同步：提示「历史 URL 将经局域网明文发送至已配对 Mac」。  
- 默认建议：**仅快捷方式 = 开**；历史 / 书签 = 用户手动开。

### 3.6 体积 / 内存 / 启动 — 工程指标（建议写入验收）

| 指标 | 目标（release，中端机参考） | 测量方式 |
|------|------------------------------|----------|
| APK 下载大小 | **≤ 8 MB**（理想 ≤ 5 MB） | `bundletool` / APK Analyzer |
| 冷启动至可交互 | **≤ 1.5 s**（新标签页网格，尚无 WebView 重页） | Macrobenchmark / 简单 log |
| 空闲（1 标签 about:blank）RSS | 尽量 **≤ 150～200 MB**（含 WebView 基线，机型差异大） | Android Profiler；记基线对比 |
| 标签上限默认 | **8**（设置可调至 12） | 产品配置 |
| 依赖数 | 无 Play Services / 无 Firebase | 依赖锁定评审 |

**工程手段清单**：

1. R8 / minify / shrinkResources 默认开（当前 `isMinifyEnabled = false` 需改为 release 开启）。  
2. 延迟创建第一个 WebView（先画壳与新标签页）。  
3. 非当前标签 `onPause`；可选销毁不可见标签的 WebView 只留 URL（激进省内存，切换变慢——做成设置「省内存模式」）。  
4. 图片 / favicon 磁盘缓存限容。  
5. Companion 发现与同步协程在连接后启动，不堵主线程。  
6. 避免每标签独立进程（Android WebView 默认多进程策略需查文档；优先单进程可控）。

### 3.7 包结构建议（演进）

```text
com.meobrowser.companion/          # 或逐步改为 com.meobrowser.app
├── browser/
│   ├── BrowserActivity
│   ├── tab/
│   ├── toolbar/
│   ├── newtab/
│   ├── download/
│   └── store/          # Shortcut / History / Bookmark
├── sync/
├── channel/            # 现有 Companion*
├── pairing/
├── sms/                # OTP + NotificationMirror
├── setup/
└── settings/           # 原 MainActivity UI 迁入
```

`MainActivity` 降级为可选别名或删除，入口改为 `BrowserActivity`。

### 3.8 Mac 侧必改清单（同步互联成立的前提）

| 模块 | 变更 |
|------|------|
| `companion-protocol.md` | 升 V3：sync_* 消息、字段表、分片、冲突语义 |
| `CompanionChannel` | 解析 sync；背压与未知 type 继续安全忽略 |
| Shortcut / History / Bookmark Store | 暴露 merge API、version、tombstone |
| 设置 UI | 「与 Android 同步」开关（与手机侧对称） |
| 文档 | 隐私说明、仅 LAN、默认范围 |

无 Mac 侧同步实现时，Android 浏览器仍可独立交付；**互联卖点不完整**。

---

## 4. 分阶段落地计划

### Phase AB-0：立项与基线（约 0.5～1 周）

- [ ] 冻结产品边界（本文 §1 / §3.3）  
- [ ] 量测当前 Companion APK 体积与连接链路作为基线  
- [ ] 起草 `companion-protocol` V3 sync 草案（可另文件）  
- [ ] 确定包名策略（保留 / 迁移）

**门禁**：指标与不做清单签字。

### Phase AB-1：浏览器壳 MVP（约 1～1.5 周）

- [ ] `BrowserActivity`：地址栏 + 单 WebView + 基础导航  
- [ ] 菜单进入「设置」占位  
- [ ] 启动不依赖配对即可浏览  

**门禁**：可打开网页；冷启动可感知快于「先连 Companion 再浏览」。

### Phase AB-2：多标签 + 新标签页 + 下载（约 2～3 周）

- [ ] 多标签管理与会话恢复  
- [ ] 新标签快捷方式网格（本地 JSON，字段预留 sync id）  
- [ ] 下载列表 MVP  
- [ ] release 体积第一次对照指标  

**门禁**：三功能可用；APK 仍在目标带内。

### Phase AB-3：Companion 设置化 + 自动连接（约 1～1.5 周）

- [ ] 原首页能力迁入设置 IA  
- [ ] 启动自动连接（安全码）  
- [ ] OTP / 通知镜像回归（与现 NM MVP 行为一致）  
- [ ] 前台服务文案改为「Meo 互联」  

**门禁**：不打开设置也能连上；设置内可完成配对与镜像配置。

### Phase AB-4：快捷方式同步（约 2～3 周）

- [ ] 协议 V3 快捷方式子集  
- [ ] Android SyncEngine + Mac merge  
- [ ] 设置项与隐私文案  
- [ ] 断线 / 分片 / 鉴权失败用例  

**门禁**：两端改快捷方式，重连后一致（LWW 可接受）。

### Phase AB-5：历史 + 书签同步与打磨（约 2～3 周）

- [ ] 历史 / 书签本地模块（若书签未建则本阶段补齐）  
- [ ] 同步开关分项  
- [ ] 内存「省内存模式」、标签上限  
- [ ] 多厂商保活与 acceptance 清单  

**门禁**：三项同步可独立开关；指标复测通过。

### Phase AB-6（可选二期）：互联增强

见 §5。

---

## 5. 其它 Android 浏览器功能建议（突出 Mac 互联）

以下按与「互联互通」相关度排序，供产品取舍。

### 5.1 强烈建议（差异化高 / 成本可控）

| 功能 | 说明 | 为何突出 Meo |
|------|------|--------------|
| **发送标签到 Mac / 到手机** | 一键把当前 URL 推到对端打开或进「待读」 | 比纯同步更有「接力」感；协议可复用 sync 或独立 `open_url` |
| **剪贴板验证码互认** | 已有 OTP 链路；手机浏览登录时可选「等待 Mac 已开页」等提示 | 强化双端登录助手故事 |
| **通知镜像入口常驻设置摘要** | 「已连接 · 仅验证码」一行 | 用户感知 Companion 未消失 |
| **互联状态与电池白名单健康度** | 设置顶栏 | 减少「连不上」支持成本 |
| **快捷方式为默认同步物** | 个人工作区跨设备一致 | 与 Mac Launchpad 战略一致 |

### 5.2 建议做（体验完整）

| 功能 | 说明 |
|------|------|
| 书签栏或星标 | 与同步模型统一；避免只有快捷方式没有书签 |
| 历史页（按日分组） | 本地先有，再同步 |
| 桌面网站切换 | UA |
| 页内查找 | 对齐 Mac |
| 下载进度通知 | 系统通知点击回 App |
| 深色模式跟随系统 | WebView force dark 谨慎，可仅壳深色 |
| 「用 Mac 打开」分享目标 | 系统分享 sheet 增加 Meo 动作（需已连接） |

### 5.3 可以后做

| 功能 | 说明 |
|------|------|
| 标签分组 / 固定标签 | Mac 路线图有 Pin；Android 空间紧，可后置 |
| 阅读列表（与书签分离） | 可和 Send Tab 合并为「待读队列」双向同步 |
| 帧级 AES-GCM | 同步与通知全文的安全升级 |
| 自建中继（外出） | 已有「不做公有云」原则；模板级即可 |
| 密码 / 信用卡同步 | 安全模型另立专项 |
| 广告拦截（简易 host 列表） | 体积与误杀风险 |

### 5.4 不建议作为卖点宣传

- 「比 Chrome 更省电更全功能」——难兑现。  
- 「云同步多端实时」——与 LAN 定位不符。  
- 「完整桌面网站兼容率第一」——应宣传「轻量 + 与 Mac Meo 成套」。

### 5.5 产品叙事（对外一句话）

> **MeoBrowser（Android）是 Mac 上 MeoBrowser 的轻量伴侣：平时是一个启动快、占内存少的极简浏览器；连上电脑后，快捷方式与浏览数据可同步，验证码自动到 Mac，手机通知也可镜像到桌面。**

---

## 6. 隐私、安全与合规要点

| 项 | 策略 |
|----|------|
| 默认同步 | 建议仅快捷方式可选默认开；历史/书签默认关 |
| 通知镜像 | 保持 `otp_only` 默认；全部模式确认框保留 |
| 传输 | V2/V3 阶段仍为 LAN 明文 + token；设置页持续披露 |
| 日志 | 不同步/不打印历史与通知全文 |
| 权限 | 浏览本身：网络；互联：短信/通知监听/前台服务——**按需在设置中申请**，打开浏览器不要一次性要全权限 |
| 应用商店 | 若上架，需说明通知监听与短信用途（验证码助手），避免被判为滥用 |

---

## 7. 验收标准（MVP 建议）

### 7.1 浏览

1. 冷启动后可直接搜索/打开 URL，无需先配对。  
2. 多标签开关、恢复；新标签页快捷方式增删改排持久化。  
3. 下载文件可在列表中打开。  

### 7.2 互联

4. 已保存安全码时，启动后自动连接成功（同 Wi‑Fi）。  
5. 设置中可完成检测、配对、镜像模式、手动测试推码。  
6. OTP 填码与通知镜像行为与现网 Companion MVP 一致。  

### 7.3 同步（若纳入同一 MVP）

7. 开启快捷方式同步后，Mac ↔ Android 修改能在重连后对齐。  
8. 关闭同步总开关后，不再传输快捷方式/历史/书签数据。  

### 7.4 轻量

9. release APK ≤ 约定阈值；主路径无明显卡顿。  
10. 标签数达上限有提示，而非无声 OOM。  

---

## 8. 决策清单（需产品拍板）

| # | 问题 | 建议默认 |
|---|------|----------|
| 1 | 应用显示名是否改为 MeoBrowser？ | 是（副标题可保留 Companion） |
| 2 | 「同步浏览」= 书签还是打开的标签？ | **书签**；打开标签做「发送到对端」 |
| 3 | 同步默认范围？ | 仅快捷方式可选默认开；其余默认关 |
| 4 | 是否上架应用商店？ | 内测 APK 先；上架单独立项 |
| 5 | 书签与快捷方式是否合并为一种数据？ | **分开**：快捷方式=新标签网格；书签=星标库（同步字段可相似） |
| 6 | 省内存模式是否默认开？ | 中低端默认开；高端默认关 |

---

## 9. 附录

### 9.1 与现有文档的关系

| 文档 | 关系 |
|------|------|
| companion-protocol V2.1 | OTP + 通知镜像；本方案要求演进 V3 sync |
| companion-notification-mirror-* | 能力保留，UI 迁设置 |
| multi-tab / new-tab-launchpad / download | Android 语义对齐的参考实现 |
| professional-features-roadmap | Mac 专业向功能；Android 只取子集 + 互联 |

### 9.2 建议后续产出的专项文档

1. `companion-sync-design.md` — 同步数据模型、冲突、分片、Mac/Android API（AB-0 起草）  
2. ~~`android-browser-development-plan.md`~~ — **已产出**：[android-browser-development-plan.md](android-browser-development-plan.md)  
3. `android-browser-acceptance.md` — 真机与指标勾选表（AB-0 起草）  

### 9.3 架构示意（目标态）

```text
┌─────────────────────────────┐       LAN JSON        ┌──────────────────────────────┐
│  MeoBrowser (Android)       │ ◄──────────────────► │  MeoBrowser (macOS)           │
│                             │   hello / otp /      │                              │
│  Browser shell + Tabs       │   phone_notification │  Tabs + Launchpad + Download │
│  New-tab shortcuts          │   sync_* (V3)        │  Shortcut/History/Bookmark   │
│  Settings → 互联/同步/镜像   │                      │  CompanionChannel + Sync     │
│  FGS + NotificationListener │                      │  LoginAssist + Notif mirror  │
└─────────────────────────────┘                      └──────────────────────────────┘
```

---

## 10. 总结

将 Meo Companion **改造为极简 Android 浏览器、并把现有检测/配对/通知能力收进设置、启动后用安全码自动连接**，在工程上 **完全可行**，且与当前代码资产高度契合。  

真正决定产品成败的是三点：

1. **守住轻量指标**（系统 WebView + 依赖纪律 + 标签/内存策略）；  
2. **把同步做成可配置、默认可信的协议能力**（先快捷方式，再历史/书签）；  
3. **叙事上坚持「Mac 互联伴侣」**，用 Send Tab、同步工作区、OTP/通知镜像组成差异化，而不是功能堆叠。  

建议按 **AB-0 → AB-5** 推进；对外可演示的第一里程碑为：**能浏览 + 设置里能配对镜像 + 启动自动连接 + 快捷方式双向同步**。
```
