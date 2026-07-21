# Companion 手机通知收件箱侧栏 — 可行性评估与技术方案

> 目标：评估「地址栏工具栏入口 → 浏览器右侧侧栏 → 展示/管理/分类手机通知」全链路；结合 MeoBrowser 现有 chrome 与 Companion 能力，给出更优交互与 UI，并落到可实施的分阶段方案。  
> 状态：**NI-MVP 已实现（NI-0～NI-2）**；开发计划见 [companion-notification-inbox-sidebar-development-plan.md](companion-notification-inbox-sidebar-development-plan.md)  
> 关联：[companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [companion-notification-mirror-development-plan.md](companion-notification-mirror-development-plan.md) · [companion-link-toolbar-mac-design.md](companion-link-toolbar-mac-design.md) · [companion-call-alert-feasibility-and-design.md](companion-call-alert-feasibility-and-design.md) · [download-design.md](download-design.md) · [find-in-page-design.md](find-in-page-design.md) · [companion-protocol.md](companion-protocol.md)

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| 工具栏增加「通知收件箱」按钮 | **可行**。复用 `BrowserAddressBarActionGroup`（与查找 / 下载 / 互联同构） |
| 浏览器内右侧侧栏展示历史通知 | **可行**。窗口内容区右侧插入可开关侧栏；本仓库尚无通用侧栏壳，需新建一次 |
| 完整管理（读/删/钉/静音 App / 搜索） | **可行**。前提是 Mac **本地持久化**（当前镜像 MVP **不落盘**，必须补齐） |
| 分类（验证码 / App / 时间 / 用户标签） | **可行**。推荐「智能分桶 + App 分组」，不做复杂文件夹树 |
| 与系统通知镜像并存 | **可行且应并存**。侧栏 = 历史与管理；系统横幅 = 即时感知 |
| 协议大改 | **不需要**。继续吃 `phone_notification` / `otp`；仅可选扩展 mute / icon 元数据 |

**产品路径建议**：先做 **Mac 收件箱侧栏 + 本地库 + 智能分类（NI-MVP）**；再做 App 静音回传 Android、图标缓存（NI-1）；断线补发仍属远期。

---

## 1. 方案定位

### 1.1 产品一句话

**手机通知有处可查、可管、可分类**：在电脑前用 MeoBrowser 右侧侧栏当「手机通知收件箱」——系统横幅负责扫一眼，侧栏负责回顾、检索与治理。

### 1.2 与现有能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| `phone_notification` 通道 | ✅ NM-0～NM-3 | **继续作为唯一推送源** |
| Mac 系统通知横幅 | ✅ `PhoneNotificationPresenter` | **保留**；点击横幅可打开侧栏并定位条目 |
| 镜像开关 / OTP 横幅开关 | ✅ `PhoneNotificationSettings` | 扩展：收件箱开关、保留天数、侧栏默认宽 |
| 地址栏 ActionGroup | ✅ 下载 / 查找 / 登录 / 互联 / 号码策略等 | **新增** `notificationInbox` 按钮 + 未读角标 |
| 应用内通知面板 | ❌ 原设计明确列为二期 | **本方案正式落地** |
| 断线补发 / 加密 | ❌ | 本期不做 |
| 窗口侧栏壳 | ❌ 无 `NSSplitView` 侧栏 | **新建**通用可复用壳（仅本功能先占用） |
| 下载面板 / 号码策略窗 | ✅ 浮层 / 独立窗 | **不混用**；通知需要历史与多分类，侧栏更合适 |

登录填码链路（`otp` → `OTPInbox`）**不变**；侧栏对验证码类条目提供「一键复制」增强，不替代自动填入。

### 1.3 做什么 / 不做什么

| 阶段 | 做 | 不做 |
|------|----|------|
| **NI-MVP** | 工具栏按钮 + 右侧侧栏；本地收件箱落盘；列表 / 搜索 / 已读未读 / 删除 / 钉选；智能分桶；系统通知点击跳转；空态与权限引导 | App 图标附件；断线补发；云同步；复杂用户自定义文件夹树 |
| **NI-1** | App 级静音（Mac → 可选回传 Android 过滤）；侧栏宽度记忆；按 App 折叠分组增强 | 伪造系统通知左侧第三方图标 |
| **NI-2（可选）** | 包名图标缓存 + `UNNotificationAttachment`；导出 JSON；快捷键命令面板入口 | 做成独立「通知中心 App」；替代 macOS 通知中心 |

### 1.4 相对「用户原始设想」的优化原则

用户设想：工具栏按钮 → 侧栏 → 全部消息 + 管理 + 分类。

结合 MeoBrowser 特点（轻量、专业、键盘可达、chrome 同构、Companion 隐私默认克制），优化为：

1. **双通道分工清晰**：横幅 = 即时；侧栏 = 收件箱。避免「关掉系统通知就丢历史」或「侧栏弹窗刷屏」。  
2. **分类以智能分桶为主**：验证码 / 未读 / 今日 / 按 App，而不是让用户先建文件夹再归档。  
3. **侧栏可开关、可记宽、不抢主浏览**：默认关闭；打开时挤压 WebView，不做半透明遮罩挡内容。  
4. **与下载浮层刻意区分**：下载是短暂任务流（锚点面板）；通知是持续信息流（侧栏）。  
5. **默认隐私姿态不变**：仅验证码模式下侧栏仍可展示 OTP 相关条目（可选）；「全部通知」才有丰富列表——并在空态说明如何开启。

---

## 2. 可行性分项评估

### 2.1 数据从哪来（Android → Mac）

**结论：已具备，风险低。**

- 现有 `phone_notification` JSON（`id` / `packageName` / `appLabel` / `title` / `body` / `ts` / `postTimeMs`）足够驱动列表行。  
- `otp` 可在 Mac 侧合成「验证码」类收件箱条目（当 `otp_only` 且用户开启「验证码写入收件箱」时），避免侧栏在默认模式下完全空白。  
- Android 噪音过滤、限流、去重已存在；侧栏消费同一 `id` 即可幂等 upsert。

**缺口**：当前 Mac **不落盘正文**（镜像设计 §7）。侧栏历史**必须**新增本地存储，否则断连 / 重启后空列表。

### 2.2 工具栏入口

**结论：可行，成熟范式。**

| 项 | 说明 |
|----|------|
| 载体 | `BrowserAddressBarActionGroup` 新 item id：`notificationInbox` |
| 尺寸 / 风格 | 28×28、Inline、SF Symbol，与现有键一致 |
| 角标 | 未读数（仿下载角标）；上限显示 `9+` |
| 排序 | 建议默认在「互联」之后（手机相关成组） |
| 点击 | Toggle 当前窗口侧栏；已开则关 |

### 2.3 右侧侧栏壳

**结论：可行；工程量中等（一次性基建）。**

当前窗口布局（简化）：

```text
rootStack (vertical)
  ├── toolbar（地址栏 + ActionGroup）
  └── contentContainer
        ├── WKWebView / Launchpad
        ├── 进度条 / 证书警告 / 查找条 / 来电条 …
```

改造建议：

```text
rootStack (vertical)
  ├── toolbar
  └── mainSplit (horizontal NSStackView 或 NSSplitView)
        ├── contentContainer（网页）   ← 权重 Fill
        └── notificationSidebar（可折叠）← 固定宽 280～420
```

| 方案 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| **A. 右侧 dock 侧栏（推荐）** | 符合用户设想；适合长列表与管理；不挡页面 | 需改窗口布局；多窗口各一份 UI | **NI-MVP 采用** |
| B. 下载式锚点 `NSPanel` | 改动小、与 chrome 一致 | 管理/分类空间不足；易被点外部关掉丢上下文 | 仅作「快速预览」备选，不做主路径 |
| C. 独立 `NSWindow`（如号码策略） | 实现快 | 与「浏览器侧边栏」心智不符；多窗管理差 | 不做主路径 |
| D. 覆盖在 WebView 上的抽屉 | 无布局改造 | 挡内容、难调整宽度、与专业阅读冲突 | 不采用 |

**多窗口**：每个 `BrowserWindowController` 各自侧栏开合状态；**数据**来自进程级单例 `PhoneNotificationInboxStore`。

### 2.4 完整管理功能

**结论：可行。**

| 能力 | 难度 | MVP |
|------|------|-----|
| 标记已读 / 全部已读 | 低 | ✅ |
| 删除单条 / 清空已读 / 清空全部（二次确认） | 低 | ✅ |
| 钉选置顶 | 低 | ✅ |
| 搜索 title/body/appLabel | 低 | ✅（`SBTextField`） |
| 复制正文 / 复制验证码 | 低 | ✅ |
| App 静音（本地不再入库 / 不弹横幅） | 中 | NI-MVP 本地；NI-1 回传 |
| 打开来源（深链到手机 App） | 高 | ❌ 桌面无法可靠唤起手机 App |
| 回复微信等 | 高 | ❌ 超出浏览器边界 |

### 2.5 分类功能

**结论：可行；推荐智能分桶，避免重型标签系统。**

| 分类维度 | 实现 | MVP |
|----------|------|-----|
| **智能分桶**：全部 / 未读 / 验证码 / 今日 / 已钉选 | 查询过滤 | ✅ |
| **按 App 分组**（同 `packageName`） | section header + 折叠 | ✅ |
| 用户自定义标签（多对多） | 额外表 | ❌ 延后；收益低于分桶 |
| 情感/重要性自动分类（AI） | 云或本地模型 | ❌ 不做 |

验证码判定（Mac 本地，优先级）：

1. 来源为合成的 `otp` 条目 → `kind=otp`  
2. 正文/标题匹配常见 OTP 正则（与 Android / 登录助手同族，可抽共享或轻量复用）  
3. 否则 `kind=general`

### 2.6 隐私与合规

**结论：可接受，但必须显式披露落盘。**

| 风险 | 缓解 |
|------|------|
| 通知全文落盘 | 本地 Application Support；可选「启动时清除」；设置页说明 |
| 与「全部模式明文 LAN」叠加 | 侧栏文案再次提示：仅本机存储、不上云 |
| 日志泄露 | 日志只打 package + id 哈希 + 长度，不打 body |
| 默认模式 | 不因侧栏功能把 Android 默认改成 `all` |

### 2.7 总体可行性矩阵

| 维度 | 评分 | 说明 |
|------|------|------|
| 产品价值 | 高 | 补齐镜像「只弹不存」的最大短板 |
| 技术风险 | 低～中 | 协议已有；侧栏壳与持久化为主要工作 |
| 与产品气质契合度 | 高 | 专业用户「工作中不掏手机」 |
| 工作量（NI-MVP） | 约 **4～6 人日** | 见 §11 |
| 依赖阻塞 | 无 | 不依赖加密 / 补发 / 图标 |

---

## 3. 交互设计（优化后）

### 3.1 核心心智模型

```text
系统通知横幅     →  「刚发生了什么」（瞬时）
工具栏铃铛+角标  →  「有没有还没处理的」
右侧侧栏收件箱   →  「回顾、检索、清理、静音」
```

三者同一数据源；用户不必在「通知中心 vs 浏览器」之间二选一。

### 3.2 工具栏按钮行为

| 操作 | 行为 |
|------|------|
| 单击 | Toggle 本窗口右侧侧栏 |
| 侧栏已开再点 | 关闭侧栏 |
| Tooltip | `手机通知` 或 `手机通知 · N 条未读` |
| 角标 | 未读数；打开侧栏且视口停留 >0.5s 后，对**可见行**自动标已读（可配置为「仅手动已读」） |
| 右键（可选 NI-1） | 全部已读 / 打开设置中的镜像区 |

**推荐 SF Symbol**：`bell` / `bell.badge`（有未读时用 badge 变体或自绘红点）。  
**不要**与「互联」`link` 圆点混用——互联表示通道；铃铛表示内容。

**默认排序建议**：

```text
查找 · 下载 · 登录助手 · 互联 · 【手机通知】 · 号码策略 · …
```

手机相关键成组，降低认知跳跃。

### 3.3 侧栏信息架构

```text
┌─ 手机通知 ───────────────────────────── [⚙] [⟩] ┐
│  [ 搜索通知…                              ]     │
│  全部  未读  验证码  今日  已钉选                 │  ← 分段 / 胶囊，单选
│ ─────────────────────────────────────────────── │
│  ▾ 微信                              今天 3     │  ← App section（可折叠）
│    ● 张三 · 下午见面            14:32  📌 …    │
│    ○ 文件传输助手 · 已保存      12:10       …    │
│  ▾ 短信                                         │
│    ● 验证码 128493              11:02  [复制]   │
│  …                                              │
│ ─────────────────────────────────────────────── │
│  底部：全部已读 · 清空已读 · 镜像：开/关提示      │
└─────────────────────────────────────────────────┘
```

### 3.4 单行交互

| 操作 | 行为 |
|------|------|
| 单击行 | 展开/选中；标记已读；详情区或行内展开完整 body |
| 双击 / 「复制」 | 复制 body；若 `kind=otp` 复制纯 code |
| 悬停 | 显示操作：钉选、删除、静音此 App、复制 |
| 滑动（可选） | macOS 列表可用右键菜单代替；不强制触控板手势 |
| 键盘 | ↑↓ 选择；⌘⌫ 删除；⌘C 复制；Esc 关闭侧栏 |

### 3.5 与系统通知的联动

| 事件 | 行为 |
|------|------|
| 收到 `phone_notification` | Store upsert → 可选横幅 → 角标 +1 → 若侧栏开则列表插入动画 |
| 用户点击系统通知 | 激活 MeoBrowser → 打开**当前 key 窗口**侧栏 → 滚动并高亮对应 `id` |
| `mirrorEnabled == NO` | 仍可配置「仅写入收件箱不弹横幅」（NI-MVP 建议拆成两开关，见 §4） |

### 3.6 空态与降级（关键）

| 状态 | 侧栏展示 |
|------|----------|
| 未配对 / 未连接 | 插画位 +「互联未连接」+ 按钮「打开互联设置」（复用 `revealCompanionSection`） |
| 已连接但 Android 为 `otp_only` 且未开「OTP 入收件箱」 | 说明：「当前手机为仅验证码模式；普通通知不会出现。可在 Companion 切换为全部通知，或开启下方选项。」 |
| 已连接、全部模式、暂无消息 | 「等待手机通知…」轻空态 |
| Mac 拒通知权限 | 不影响侧栏列表；顶部条提示「系统通知未授权，仍可在此查看」+ 打开设置 |
| 收件箱功能关闭 | 侧栏显示关闭说明；按钮仍可打开以便重新开启 |

### 3.7 快捷键与专业用户路径

| 快捷键 | 行为 | 说明 |
|--------|------|------|
| ⌘⇧N | Toggle 侧栏 | 避开 ⌘N 新窗口；若冲突可改为 ⌘⇧I（Inbox）——**建议拍板 D2** |
| Esc | 侧栏聚焦时关闭 | 与查找条一致 |
| 命令面板（远期） | 「打开手机通知」 | 与 roadmap 对齐 |

### 3.8 明确不采用的交互

- 每条通知都强制弹侧栏（刷屏）。  
- 用登录助手窗口塞通知列表（职责混乱）。  
- 左侧书签式永久侧栏（Meo 暂无左栏生态，右栏更贴「辅助信息」）。  
- 在地址栏内嵌通知下拉长列表（空间与管理能力都不够）。

---

## 4. 产品行为定稿（建议默认）

| 项 | 定稿 |
|----|------|
| 收件箱总开关 | 默认 **开**（与镜像接收一致）；关则不入库 |
| 系统横幅开关 | 保持现有 `mirrorEnabled` / `otpBannerEnabled` |
| **写入收件箱**与**弹横幅** | **拆成两个开关**（NI-MVP）：`inboxEnabled`（默认开）、`bannerEnabled`（= 现 mirror 语义） |
| OTP 是否入库 | 默认 **开**（便于仅验证码模式侧栏仍有价值） |
| 未读自动已读 | 侧栏可见 0.5s 后自动已读；设置可改为仅手动 |
| 保留策略 | 默认 **7 天**；可调 1 / 7 / 30 / 永久；超出按时间淘汰（钉选豁免） |
| 条数上限 | 硬顶 **2000**；超出删最旧非钉选 |
| App 静音 | 本地生效：不入库、不横幅；OTP 是否绕过静音：**绕过**（填码优先） |
| 侧栏默认宽度 | 320 pt；范围 280～420；记忆每窗口或全局（建议**全局**） |
| 侧栏默认开闭 | 默认 **关**；不随会话恢复强制打开 |

---

## 5. UI 视觉设计（贴合本应用）

### 5.1 设计语言对齐

与现有 Mac chrome / Companion 卡片 / 下载面板一致：

| 元素 | 规范 |
|------|------|
| 材质 | `NSVisualEffectView`（sidebar / headerView 材质）；Light 白透，Dark 跟随系统 |
| 分隔 | 1px `separatorColor`；圆角仅用于行悬停高亮（6～8pt），避免大卡片堆叠 |
| 字体 | 标题 13pt medium；正文 12pt regular secondary；时间 11pt tertiary |
| 颜色 | 未读圆点 `systemBlue`；钉选 `systemOrange` 或 SF `pin.fill`；验证码标签用柔和 tint pill（非高饱和） |
| 图标 | SF Symbol；App 无图标时用首字圆形 glyph（`appLabel` 首字） |
| 分段控件 | 紧凑 `NSSegmentedControl` 或等宽文字 tab；**禁止**紫色渐变胶囊群 |

禁止（与仓库其它设计稿一致）：

- 紫青渐变、大面积 glow、dashboard 式多统计卡堆在侧栏顶  
- Emoji 当图标  
- 把侧栏做成「第二个通知中心皮肤」而脱离 AppKit 质感  

### 5.2 视觉层次（一屏只做一件事）

侧栏顶部只保留：**标题 + 搜索 + 分桶**。  
统计（今日 N 条、静音 App 数）放到设置或底栏次要文案，避免首屏噪音。

### 5.3 验证码行强化（差异化）

验证码是 Meo 最高频 Companion 场景，侧栏应「一眼可抄」：

```text
┌────────────────────────────────────────┐
│ 验证码 · 短信              今天 11:02  │
│ 128493                     [ 复制码 ]  │
│ 来自 95007 · 5 分钟内有效（若可解析）   │
└────────────────────────────────────────┘
```

- code 用 **17～20pt semibold 等宽**（`SBKit` 不强制，可用 `NSTextField` label + monospacedDigit）  
- 「复制码」为主按钮；复制后短暂变成「已复制」  

### 5.4 动效（克制、有存在感）

| 动效 | 说明 |
|------|------|
| 侧栏开合 | 宽度约束动画 0.2s ease-out |
| 新消息插入 | 列表顶部轻推入；不整表闪烁 |
| 高亮定位 | 系统通知点入时行背景脉冲 1 次 |
| 角标变化 | 数字交叉淡入；避免弹跳夸张 |

### 5.5 Dark Mode

全部使用语义色（`labelColor` / `secondaryLabelColor` / `controlBackgroundColor`）；未读点与分隔线在深色下需自测对比度。

### 5.6 Accessibility

- 侧栏 `accessibilityLabel`：手机通知收件箱  
- 分桶为 tab 语义  
- 角标计入按钮 accessibility value：`未读 N`  
- 完整 body 可被 VoiceOver 读出  

---

## 6. 数据模型与存储

### 6.1 条目模型

```text
PhoneNotificationItem
  id            String   // 与协议 id 一致；otp 合成用 "otp:" + hash(code+ts桶)
  packageName   String
  appLabel      String
  title         String
  body          String
  kind          enum     // general | otp
  otpCode       String?  // kind=otp 时
  postTimeMs    Int64
  receivedAt    Date     // Mac 入库时间
  read          Bool
  pinned        Bool
  mutedSnapshot Bool     // 入库时是否来自已静音（一般直接不入库）
  source        enum     // mirror | otp_synthetic
```

### 6.2 App 元数据 / 偏好

```text
PhoneNotificationAppMeta
  packageName
  appLabel（最近一次）
  muted Bool
  lastActiveAt
```

### 6.3 存储选型

| 方案 | 评价 | 结论 |
|------|------|------|
| UserDefaults 大数组 | 简单但 2000 条正文易膨胀、无查询 | ❌ |
| JSON 文件整表读写 | 实现快；搜索需全载 | NI-MVP **可接受**（先做） |
| SQLite（FMDB / 自研薄封装） | 查询/淘汰干净 | NI-1 若 JSON 吃力再迁 |

**MVP 建议**：`~/Library/Application Support/MeoBrowser/PhoneNotificationInbox.json`（或目录下 `inbox.jsonl` append + 压缩重写）。  
写入：主线程投递到串行 queue；UI 经 notification 刷新。

### 6.4 Store API（示意）

```objc
@interface PhoneNotificationInboxStore : NSObject
+ (instancetype)sharedStore;
- (void)upsertMirrorPayload:(NSDictionary *)payload;
- (void)upsertOTPCode:(NSString *)code;
- (NSArray<PhoneNotificationItem *> *)itemsMatchingFilter:(PhoneNotificationFilter *)filter;
- (void)setRead:(BOOL)read forId:(NSString *)itemId;
- (void)setPinned:(BOOL)pinned forId:(NSString *)itemId;
- (void)deleteId:(NSString *)itemId;
- (void)markAllRead;
- (void)purgeRead;
- (void)purgeAllConfirming:(void(^)(BOOL ok))completion;
- (NSUInteger)unreadCount;
- (void)setMuted:(BOOL)muted forPackage:(NSString *)packageName;
@end
```

通知名建议：`PhoneNotificationInboxDidChangeNotification`（userInfo 可带 `reason`）。

### 6.5 与 Presenter 的关系

```text
CompanionChannel
  ├─ phone_notification ──► InboxStore.upsert ──► Presenter.banner（若 bannerEnabled）
  └─ otp ──► OTPInbox（填码）──► InboxStore.upsertOTP（若开启）──► Presenter.otpBanner（现有抑制逻辑）
```

**定稿**：先入库再决定是否横幅，保证「关横幅仍有历史」。

---

## 7. 协议与 Android

### 7.1 NI-MVP：无协议变更

完全消费现有 V2.1。旧 Android / 旧 Mac 兼容策略不变。

### 7.2 NI-1（可选）：App 静音同步

Mac → Android：

```json
{
  "v": 1,
  "type": "notification_mute_set",
  "deviceToken": "…",
  "packageName": "com.tencent.mm",
  "muted": true
}
```

Android 在 `NotificationNoiseFilter` 中跳过该包（OTP 解析路径是否跳过：**不跳过**）。

或复用 V3 sync：`kind=notification_app_pref`。优先走 sync 骨架，若 V3 未就绪则用专用 type。

### 7.3 图标（专项方案）

真 App 图标同步（Android 推小图 + Mac 缓存）见专项：  
[companion-notification-app-icon-design.md](companion-notification-app-icon-design.md)（IC-MVP / IC-1）。  

MVP 收件箱阶段可用首字/SF 占位；系统通知栏左侧第三方图标仍不可行。

---

## 8. Mac 模块设计

### 8.1 新增 / 修改清单

| 模块 | 职责 |
|------|------|
| `PhoneNotificationInboxStore` | 持久化、过滤、未读计数、静音表 |
| `PhoneNotificationInboxSettings` | inboxEnabled、otpToInbox、retentionDays、autoMarkRead、sidebarWidth |
| `PhoneNotificationSidebarController` | 侧栏 UI、分桶、列表、搜索、操作 |
| `PhoneNotificationSidebarHost` | 挂到 `BrowserWindowController` 的约束与开合动画 |
| `BrowserAddressBarActionGroup` | `notificationInbox` 按钮 + 角标 |
| `PhoneNotificationPresenter` | 点击通知 → 广播「reveal item」；横幅与入库解耦 |
| `CompanionChannel` | 收包后先 Store（或 Presenter 内统一入口） |
| `BrowserLoginAssistSettings…` | 镜像区增加收件箱相关开关与保留策略 |
| `Makefile` | 编译新 `.m` |

### 8.2 窗口布局改造要点

1. 将原 `contentContainer` 包进横向 stack：`contentContainer` + `sidebarContainer`。  
2. `sidebarContainer` 默认 `hidden` 且宽度约束 = 0；打开时设为记忆宽度。  
3. 查找条 / 来电条 / 证书警告仍挂在 `contentContainer` 上，**不要**被侧栏盖住。  
4. Launchpad 同样随 content 变窄——可接受。

### 8.3 多窗口角标

`unreadCount` 变化时：

- 通知所有 `BrowserWindowController` 刷新 ActionGroup 角标；或  
- ActionGroup 直接观察 `PhoneNotificationInboxDidChangeNotification`。

### 8.4 设置 UI 文案要点

- 「将手机通知保存到收件箱侧栏」  
- 「验证码写入收件箱」  
- 「保留期限」  
- 「打开侧栏时自动标为已读」  
- 隐私一句：内容仅存本机，可随时清空  

输入控件：搜索框与设置中的自定义项走 **SBTextField**。

---

## 9. 分类与过滤实现细节

### 9.1 Filter 模型

```text
PhoneNotificationFilter
  bucket: all | unread | otp | today | pinned
  query: String?          // 大小写不敏感，匹配 appLabel/title/body
  packageName: String?    // 点 section 或「仅看此 App」
```

### 9.2 分组算法

1. 先按 filter 得到扁平数组。  
2. 钉选条目置于「已钉选」虚拟组（当 bucket≠pinned 时仍可置顶显示）。  
3. 其余按 `packageName` 分组，组内按 `postTimeMs` 降序。  
4. 组顺序：最近有消息的 App 优先。

### 9.3 OTP 正则（Mac 侧轻量）

与现有登录助手兴趣规则对齐即可；侧栏 `kind` 仅影响 UI 与分桶，**不**再次触发自动填表（填表只走 `OTPInbox`）。

---

## 10. 失败与边界

| 情况 | 行为 |
|------|------|
| 同 `id` 更新类通知 | upsert 覆盖 title/body，保留用户 read/pinned |
| 洪水 | 沿用 Android 限流；Mac 入库同样可每秒 cap |
| 磁盘满 / 写入失败 | 横幅仍可工作；侧栏顶条错误提示 |
| 清空全部 | 确认 sheet；不可撤销（MVP）；NI-1 可回收站 |
| 侧栏开着时缩到极窄窗 | 最小窗宽钳制或自动关侧栏 |
| 仅验证码 + 关 otpToInbox | 空态引导，不假装有数据 |

---

## 11. 分阶段实施计划

| 阶段 | 名称 | 产出 | 预估 |
|------|------|------|------|
| **NI-0** | 存储与设置骨架 | Store + Settings + Channel/Presenter 双写；无 UI | 0.5～1 日 |
| **NI-1a** | 侧栏壳 + 工具栏 | ActionGroup 按钮、开合动画、空态 | 1～1.5 日 |
| **NI-1b** | 列表与管理 | 分桶、搜索、已读/删/钉/复制、角标 | 1.5～2 日 |
| **NI-2** | 联动与打磨 | 系统通知点击定位、设置页、保留淘汰、Dark Mode、多窗口 | 1 日 |
| **NI-3** | （可选）静音同步 / 图标 | 协议或 sync、Android filter | 1～2 日 |

**首版交付推荐：NI-0 + NI-1a + NI-1b + NI-2。**

### 验收清单（NI-MVP）

- [ ] 工具栏铃铛可开关右侧侧栏；宽度可拖（或固定档）并记忆  
- [ ] 全部模式下新通知出现在侧栏；重启后仍在（在保留期内）  
- [ ] 仅验证码模式：OTP 可出现在「验证码」分桶（默认开）  
- [ ] 未读角标正确；全部已读清零  
- [ ] 搜索、删除、钉选、复制码可用  
- [ ] 关横幅、开收件箱：只入库不弹  
- [ ] 点击系统通知能打开侧栏并高亮  
- [ ] 未连接空态可跳转互联设置  
- [ ] Dark Mode / 多窗口角标一致  
- [ ] 填码自动流程回归无回归  

---

## 12. 风险与决策待确认

| ID | 问题 | 建议默认 |
|----|------|----------|
| D1 | 主容器用 `NSSplitView` 还是双约束 `NSStackView` | **NSStackView + 宽度约束**（更轻，够用） |
| D2 | 快捷键 ⌘⇧N vs ⌘⇧I | **⌘⇧I**（Inbox；避免与「新」语义混淆） |
| D3 | 可见即已读 vs 纯手动 | **可见 0.5s 自动已读**（专业用户效率） |
| D4 | JSON vs SQLite | **MVP JSON**；超 2k 或卡顿再迁 |
| D5 | OTP 是否默认入库 | **是** |
| D6 | 侧栏是否做宽度拖拽 | **MVP 做右边内侧拖条**（体验明显） |
| D7 | App 静音是否进 MVP | **本地静音进 MVP**；回传 Android 放 NI-3 |

---

## 13. 架构示意

```text
┌──────────────────────────┐   phone_notification / otp    ┌─────────────────────────────────────────┐
│ Meo Companion (Android)  │ ────────────────────────────► │ MeoBrowser (macOS)                       │
│  Mirror mode + filter    │                               │  CompanionChannel                         │
└──────────────────────────┘                               │       │                                   │
                                                           │       ├─► OTPInbox → LoginAssist          │
                                                           │       ├─► PhoneNotificationInboxStore     │
                                                           │       │         │                         │
                                                           │       │         ├─► Sidebar (per window)  │
                                                           │       │         └─► Toolbar badge         │
                                                           │       └─► Presenter → UNUserNotification│
                                                           │                 │                         │
                                                           │                 └─ click → reveal in sidebar
                                                           └─────────────────────────────────────────┘
```

---

## 14. 文档与代码索引

| 资源 | 路径 |
|------|------|
| 镜像 MVP 设计 | `docs/minimal-browser/companion-notification-mirror-design.md` |
| 本方案 | `docs/minimal-browser/companion-notification-inbox-sidebar-design.md` |
| ActionGroup | `SimpleBrowser/AddressBar/BrowserAddressBarActionGroup.*` |
| 通道 | `SimpleBrowser/LoginAssist/Companion/CompanionChannel.*` |
| 现 Presenter / Settings | `PhoneNotificationPresenter.*` · `PhoneNotificationSettings.*` |
| 窗口布局 | `SimpleBrowser/BrowserWindowController.m` |
| 下载浮层对照 | `SimpleBrowser/Downloads/BrowserDownloadPanel.*` |
| 号码策略面板对照 | `PhonePolicyPanelController.*`（独立窗，非侧栏） |

---

## 15. 总结

从可行性看，**该设想完全可做**：推送与鉴权已通，缺口主要是「落盘收件箱 + 窗口右侧侧栏壳 + 管理/分类 UI」。  

从体验看，建议不要做成「第二个系统通知中心」，而是做成 Meo 特色的 **Companion 收件箱**：与系统横幅分工、验证码行强化、智能分桶代替重分类、工具栏角标做未读信标，并严格沿用现有 AppKit chrome 语言。  

D1～D7 已按建议默认写入开发计划；按 NI-0→NI-2 开工实现即可。
