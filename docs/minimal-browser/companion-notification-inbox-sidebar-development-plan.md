# Companion 手机通知收件箱侧栏 — 开发计划（Cursor 可执行）

> 基于 [companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md)。  
> **范围锁定（NI-MVP）**：工具栏铃铛 + 右侧 dock 侧栏 + JSON 本地收件箱 + 智能分桶/管理 + 系统通知点击定位 + 设置开关。  
> **不做（本计划）**：静音回传 Android、图标附件、断线补发、用户自定义标签树、SQLite 迁移。  
> 状态：**NI-0～NI-2 已完成（MVP）**；NI-3（静音同步/图标）不做   
> 前置：通知镜像 NM-0～NM-3（`phone_notification` / Presenter / Settings）已就绪  
> 关联：[companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [companion-link-toolbar-mac-design.md](companion-link-toolbar-mac-design.md)

---

## 行为定稿（相对设计稿 §4 / §12）

| 项 | 定稿 |
|----|------|
| D1 布局 | `NSStackView` 横向 + 宽度约束（不用 `NSSplitView`） |
| D2 快捷键 | **⌘⇧I** Toggle 侧栏 |
| D3 已读 | 侧栏可见行停留 **0.5s** 自动已读（可设置关掉） |
| D4 存储 | Application Support 下 **JSON**；硬顶 2000 条 |
| D5 OTP 入库 | 默认 **开**（`otpToInbox`） |
| D6 宽度拖拽 | MVP **做**内侧拖条；默认宽 320，范围 280～420，全局记忆 |
| D7 App 静音 | **本地静音进 MVP**；回传 Android → NI-3（本计划不做） |
| 入库 vs 横幅 | 拆开关：`inboxEnabled`（默认开）、横幅沿用/映射现有 `mirrorEnabled` |
| 保留期 | 默认 **7 天**；钉选豁免淘汰 |
| 侧栏默认 | 默认 **关** |
| 协议 | **无变更**；继续消费 V2.1 |
| 填码 | `OTPInbox` 语义不变；侧栏不触发自动填表 |

**首版交付目标：NI-0 + NI-1a + NI-1b + NI-2。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 | 预估 |
|------|------|------|------|------|
| Phase NI-0 | 存储与双写骨架 | **完成** | Store / InboxSettings；Channel·Presenter 先入库再横幅 | 0.5～1 日 |
| Phase NI-1a | 侧栏壳 + 工具栏 | **完成** | 窗口横向布局；ActionGroup 铃铛；开合 / ⌘⇧I；空态 | 1～1.5 日 |
| Phase NI-1b | 列表与管理 | **完成** | 分桶、搜索、CRUD、角标、验证码行、本地静音 | 1.5～2 日 |
| Phase NI-2 | 联动与打磨 | **完成** | 通知点击定位、设置页、保留淘汰、Dark Mode、多窗口、验收 | 1 日 |
| Phase NI-3 | 静音同步 / 图标 | 不做 | 见设计稿 §7.2～7.3 | — |

---

## Cursor 执行约定

1. **严格按阶段顺序**：完成 NI-0 再开 NI-1a；NI-1a 可开合空侧栏后再做 NI-1b 列表。  
2. **每阶段结束**：`make`（或仓库惯用浏览器 target）编译通过；不引入无关重构。  
3. **输入框**：侧栏搜索、设置相关输入一律 `SBTextField`（见 `.cursor/rules/appkit-text-input.mdc`）。  
4. **新源文件**：放入 `SimpleBrowser/LoginAssist/Companion/`（或同级 `NotificationInbox/` 子目录），并写入 `Makefile`。  
5. **ActionGroup**：新 id `notificationInbox`；缺省顺序插入在 `companionLink` **之后**（与 `phonePolicy` 同组手机能力）；用户已有顺序数组缺失该 id 时按此规则追加，勿整体重置。  
6. **不要**改 Android 工程（MVP 无协议变更）。  
7. 日志不打印完整 `body` / OTP 明文（可打 package、id 前缀、长度）。

---

## Phase NI-0：存储与双写骨架

**目标**：无 UI 也能把 `phone_notification` / `otp` 落入本地库；横幅与入库解耦；编译通过。

### 任务清单

#### 0A — Settings

- [x] **0.1** 新增 `PhoneNotificationInboxSettings.h/.m`（UserDefaults）  
  - `inboxEnabled` 默认 YES  
  - `otpToInbox` 默认 YES  
  - `retentionDays` 默认 7（`0` = 永久，若采用枚举则文档写清）  
  - `autoMarkReadOnVisible` 默认 YES  
  - `sidebarWidth` 默认 320  
- [x] **0.2** 与现有 `PhoneNotificationSettings` 关系：  
  - `mirrorEnabled` 继续表示**系统横幅**  
  - 收件箱独立；关横幅不影响入库（当 `inboxEnabled`）

#### 0B — Store

- [x] **0.3** 新增模型 `PhoneNotificationItem`（或字典约定 + 薄包装类）字段对齐设计 §6.1  
- [x] **0.4** 新增 `PhoneNotificationInboxStore` 单例：  
  - 路径：`Application Support/MeoBrowser/PhoneNotificationInbox.json`（或项目既有 App Support 根）  
  - 串行 queue 读写；主线程 API 或 completion 回主线程  
  - `upsertMirrorPayload:` / `upsertOTPCode:`（合成 id：`otp:` + 稳定哈希）  
  - `itemsMatchingFilter:`（可先返回全量，过滤逻辑 NI-1b 补全亦可在此阶段写好）  
  - `setRead:forId:` / `setPinned:forId:` / `deleteId:` / `markAllRead` / `purgeRead` / `purgeAll`  
  - `unreadCount`  
  - `setMuted:forPackage:` + `isMutedPackage:`  
  - 静音包：`upsertMirrorPayload` **直接跳过**；OTP upsert **绕过静音**  
- [x] **0.5** 启动或 upsert 后执行保留策略：超期非钉选删除；总数 >2000 删最旧非钉选  
- [x] **0.6** 广播 `PhoneNotificationInboxDidChangeNotification`

#### 0C — 接入通道

- [x] **0.7** `CompanionChannel`（或 Presenter 统一入口）：收到 `phone_notification` 鉴权通过后  
  1. 若 `inboxEnabled` 且未静音 → `InboxStore upsert`  
  2. 若 `mirrorEnabled` → 现有横幅逻辑  
  3. 仍回 `phone_notification_ok`  
- [x] **0.8** `otp` 入 `OTPInbox` 成功后：若 `otpToInbox` → `upsertOTPCode`；横幅抑制逻辑保持 NM-2.8  
- [x] **0.9** Makefile 加入新 `.m`；编译通过  
- [x] **0.10** 可选：临时调试日志「inbox count=N」（不含正文）验证双写

**完成标准**：真机或模拟推一条镜像后，JSON 文件有记录；关 `mirrorEnabled` 仍入库；填码回归不变。

---

## Phase NI-1a：侧栏壳 + 工具栏入口

**目标**：每窗口可 Toggle 右侧空侧栏；工具栏有铃铛；快捷键可用。

### 任务清单

#### 1A — 窗口布局

- [ ] **1.1** `BrowserWindowController`：将原 `contentContainer` 包入横向 `NSStackView`（`mainSplit`）  
  - leading：`contentContainer`（Fill）  
  - trailing：`sidebarContainer`（初始 hidden，宽 0）  
- [ ] **1.2** 查找条 / 来电条 / 证书警告 / Launchpad / WebView **仍只挂在** `contentContainer`  
- [ ] **1.3** 新增 `PhoneNotificationSidebarHost`（或 Controller 内方法）：  
  - `setSidebarVisible:animated:`  
  - 打开时宽度 = `InboxSettings.sidebarWidth`  
  - 关闭时宽 0 + hidden

#### 1B — 侧栏壳 UI

- [ ] **1.4** `PhoneNotificationSidebarController`：标题「手机通知」、关闭按钮、占位空态  
- [ ] **1.5** 空态分支（可先静态文案，NI-2 接互联跳转）：未连接 / 无消息 / 功能关闭  
- [ ] **1.6** `NSVisualEffectView` 背景；右边内侧拖条改宽并写回 `sidebarWidth`（钳制 280～420）

#### 1C — ActionGroup

- [ ] **1.7** `BrowserAddressBarActionGroup`：`notificationInbox` + SF Symbol `bell`；暴露 `notificationInboxButton`  
- [ ] **1.8** 顺序迁移：prefs 无该 id 时插入 `companionLink` 之后  
- [ ] **1.9** `BrowserWindowController`：按钮 target → Toggle 本窗侧栏  
- [ ] **1.10** 菜单或 `keyEquivalent`：**⌘⇧I**（注意与现有快捷键冲突时改文档并避开）  
- [ ] **1.11** 侧栏开时按钮可用 `contentTintColor` 或等价「按下态」提示（可选，轻量）

**完成标准**：点铃铛 / ⌘⇧I 开合侧栏；拖宽记忆；网页区变窄且查找条仍正常；多窗口互不影响开合。

---

## Phase NI-1b：列表与管理

**目标**：完整收件箱体验（分桶、搜索、管理、角标、验证码强化）。

### 任务清单

#### 2A — 过滤与列表

- [ ] **2.1** 实现 `PhoneNotificationFilter`：bucket `all|unread|otp|today|pinned` + `query` + 可选 `packageName`  
- [ ] **2.2** 列表：`NSTableView` / `NSOutlineView` / 自定义 stack+scroll（择一；优先好做 section 的方案）  
- [ ] **2.3** 按 `packageName` 分组；组头可折叠（MVP 可先始终展开，折叠为加分项）  
- [ ] **2.4** 钉选组置顶（设计 §9.2）  
- [ ] **2.5** 顶部分段控件切换 bucket；`SBTextField` 搜索防抖  
- [ ] **2.6** 监听 `PhoneNotificationInboxDidChangeNotification` 刷新；新消息插入不整表乱跳（尽力）

#### 2B — 行与操作

- [ ] **2.7** 行 UI：未读点、app/title、时间、钉选标识；`kind=otp` 大号等宽 code +「复制码」  
- [ ] **2.8** 单击选中 / 标记已读；右键或悬停按钮：钉选、删除、复制正文、静音此 App  
- [ ] **2.9** `autoMarkReadOnVisible`：可见 0.5s 后 `setRead:YES`  
- [ ] **2.10** 底栏：全部已读、清空已读（确认）、（可选）清空全部确认 sheet  
- [ ] **2.11** Esc：侧栏为第一响应时关闭侧栏

#### 2C — 角标

- [ ] **2.12** ActionGroup 或 WindowController 观察 Inbox 变更，更新未读角标（`9+` 封顶）  
- [ ] **2.13** 多窗口角标同步  
- [ ] **2.14** Tooltip：`手机通知` / `手机通知 · N 条未读`

**完成标准**：分桶与搜索可用；删/钉/静音/复制码正确持久化；角标随未读变化。

---

## Phase NI-2：联动与打磨

**目标**：达到设计稿验收清单；设置可配；Dark Mode / 边界打磨。

### 任务清单

#### 3A — 系统通知联动

- [ ] **3.1** `PhoneNotificationPresenter`（或 `UNUserNotificationCenter` delegate）：用户点击通知 → 发 `PhoneNotificationInboxRevealItemNotification`（userInfo 含 `id`）  
- [ ] **3.2** key 窗口打开侧栏、选中分桶「全部」、滚动并高亮对应行（脉冲 1 次）  
- [ ] **3.3** 无匹配 id 时仍打开侧栏

#### 3B — 设置页

- [ ] **3.4** `BrowserLoginAssistSettingsWindowController` 通知镜像卡片下增加：  
  - 保存到收件箱、验证码写入收件箱、保留期限、可见即已读  
  - 隐私一句 +「清空收件箱」按钮  
- [ ] **3.5** 侧栏空态「打开互联设置」→ 现有 `revealCompanionSection`  
- [ ] **3.6** Mac 通知权限未授：侧栏顶条提示 + 打开系统设置（复用现有 URL）

#### 3C — 质量

- [ ] **3.7** Dark Mode 对比度 / 分隔线 / 未读点  
- [ ] **3.8** 极窄窗口：自动关侧栏或钳制最小宽  
- [ ] **3.9** 写入失败：侧栏非阻断错误条；横幅仍可用  
- [ ] **3.10** 更新设计稿状态行；本计划阶段勾选；必要时 `acceptance.md` 追加手测项  
- [ ] **3.11** 回归：配对、otp 填码、镜像横幅、双弹抑制、来电条、查找条

**完成标准**：§验收清单全部可勾；无严重刷屏或布局回归。

---

## 建议实现顺序（单人 / Agent）

```text
NI-0.1～0.6 Store+Settings
  → NI-0.7～0.9 Channel/Presenter 双写 + Makefile
  → NI-1.1～1.6 窗口壳 + SidebarController 空态
  → NI-1.7～1.11 ActionGroup + ⌘⇧I
  → NI-1b 全阶段列表管理与角标
  → NI-2 联动、设置、打磨、验收
```

可并行（若两人）：NI-0 与 NI-1a 布局骨架在 API 稳定后并行，但 **列表依赖 Store**，NI-1b 不得早于 NI-0 完成。

---

## 关键文件（预期）

### 新增

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationInboxSettings.h/.m` | 收件箱偏好 |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationInboxStore.h/.m` | JSON 存储 |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationItem.h/.m` | 模型（可与 Store 合并） |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationSidebarController.h/.m` | 侧栏 UI |
| （可选）`PhoneNotificationSidebarHost.h/.m` | 开合/拖宽封装 |

### 修改

| 路径 | 变更 |
|------|------|
| `SimpleBrowser/LoginAssist/Companion/CompanionChannel.m` | 入库入口 |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationPresenter.m` | 横幅与点击 reveal |
| `SimpleBrowser/LoginAssist/Companion/PhoneNotificationSettings.*` | 仅文档/注释厘清与 inbox 分工（尽量少改 API） |
| `SimpleBrowser/AddressBar/BrowserAddressBarActionGroup.h/.m` | `notificationInbox` |
| `SimpleBrowser/BrowserWindowController.m` | 横向布局、Toggle、快捷键、角标 |
| `SimpleBrowser/LoginAssist/BrowserLoginAssistSettingsWindowController.m` | 设置项 |
| `Makefile` | 编译新文件 |
| `docs/minimal-browser/companion-notification-inbox-sidebar-design.md` | 状态 → 实现中/完成 |

### 不修改（MVP）

| 路径 | 原因 |
|------|------|
| `companion/android/**` | 无协议变更 |
| `companion-protocol.md` | 无 V2.x 字段增加 |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 改 `contentContainer` 打断查找条/来电条约束 | NI-1a 先只做壳；约束仍相对 contentContainer；每步编译手点 ⌘F |
| JSON 大文件主线程卡顿 | 串行 queue；列表只持过滤后数组；NI-3 再评估 SQLite |
| 角标与下载角标绘制冲突 | 不同按钮；复用 download badge 尺寸与 layer 写法 |
| ⌘⇧I 系统/菜单冲突 | 实现前搜现有 `keyEquivalent`；冲突则改 ⌘⇧\\` 或菜单「显示 → 手机通知」 |
| 自动已读误伤 | 设置可关；仅「侧栏可见」行，非仅开侧栏 |

---

## 附录：手动验收清单（NI-MVP）

复制到测试时使用：

- [ ] 铃铛 Toggle 右侧侧栏；⌘⇧I 同样有效  
- [ ] 拖宽后重启宽度保持  
- [ ] Android「全部通知」：新通知进侧栏；重启后仍在（7 天内）  
- [ ] 关系统横幅、开收件箱：只入库不弹  
- [ ] 仅验证码 + otpToInbox：验证码分桶可见；复制码正确  
- [ ] 未读角标；全部已读后清零；多窗口一致  
- [ ] 搜索 / 钉选 / 删除 / 静音 App（该 App 不再入库；OTP 仍入库）  
- [ ] 点击系统通知 → 侧栏打开并高亮  
- [ ] 未连接空态可打开互联设置  
- [ ] Dark Mode 可读；查找条 / 来电条 / 填码无回归  
- [ ] 日志无完整通知正文  

---

## 一句话给 Agent

按 NI-0 → NI-1a → NI-1b → NI-2 顺序实现 Mac 侧「手机通知收件箱侧栏」：先 JSON 双写，再窗口右侧壳与工具栏铃铛，再列表管理与角标，最后通知点击联动与设置打磨；不改 Android / 协议；输入用 SBTextField；Makefile 纳入新文件。
