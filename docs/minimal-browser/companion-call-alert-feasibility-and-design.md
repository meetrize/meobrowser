# Companion 来电提醒与号码策略库 — 可行性评估与技术方案

> 目标：评估「手机来电状态 → Mac 系统通知 + 浏览器跨标签提醒 + 轻量号码类型判断 + 用户备注策略库 +（可选）通讯录同步」全链路；给出可落地的分阶段方案与权限路径。  
> 状态：**方案已按轻量规则收紧（黑名单本期不做）**  
> 关联：[companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [companion-protocol.md](companion-protocol.md) · [companion-sync-design.md](companion-sync-design.md) · [companion-link-toolbar-mac-design.md](companion-link-toolbar-mac-design.md) · [companion/android/MeoCompanion/README.md](../../companion/android/MeoCompanion/README.md)

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| 获取来电状态（响铃 / 接通 / 挂断） | **可行**。`READ_PHONE_STATE` + `TelephonyCallback` |
| 获取来电号码 | **有条件可行**。推荐 `ROLE_CALL_SCREENING`（`CallScreeningService`）；不要走 `READ_CALL_LOG`（Play 严限） |
| Mac 系统通知栏展示 | **可行**。复用现有 `UNUserNotificationCenter` 镜像管线 |
| 浏览器跨标签页来电横幅（含号码） | **可行**。窗口级 / App 级浮层，不绑单标签 |
| 号段省市区归属地 | **本期不做**。开源 `phone.dat` 体积大，收益不值；不内置大型号段库 |
| 自动判断「广告 / 个人 / 机构」等 | **用最简规则 + 用户策略库**。规则表几十行即可；无完整开源黄页库 |
| 与手机通讯录同步备注名 | **可行（后期）**。`READ_CONTACTS` / `WRITE_CONTACTS`，写入 Meo 自有账户 |
| 黑名单 / 拒接同步 | **本期不做**（见 §2.7 仅作远期备注） |

**本期产品路径**：Call Screening 取号 → Mac 通知 + 跨窗来电条 → 轻量规则猜类型 → 工具栏管理备注/类型；不同步黑名单、不嵌 phone.dat。

---

## 1. 方案定位

### 1.1 产品一句话

**在电脑前也能看见谁在打手机**：来电时 Mac 弹系统通知，MeoBrowser 所有标签页顶部出现来电条（号码 + 简单类型提示 + 用户备注）；用户可在工具栏管理号码备注与类型。

### 1.2 与现有 Companion 能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| OTP / 通知镜像 | ✅ V2.1 | **并列新通道**，互不替代 |
| 局域网通道 / `deviceToken` | ✅ | 复用；新增 `call_event` |
| Mac 系统通知 Presenter | ✅ `PhoneNotificationPresenter` | 扩展或并列 `CallAlertPresenter` |
| 地址栏「互联」入口 | ✅ ML | 策略库管理用**新工具栏图标**，不混用互联圆点 |
| V3 书签/快捷方式同步 | 骨架 | 号码备注可后期用 `kind=phone_policy`（见 §5.3） |

### 1.3 做什么 / 不做什么（按阶段）

| 阶段 | 做 | 不做 |
|------|----|------|
| **CA-MVP** | 来电状态 + 号码 → Mac 系统通知 + 跨窗横幅；**轻量规则**猜类型；本地备注策略库 CRUD；工具栏管理入口 | **phone.dat / 省市区库**；**黑名单 / 拒接**；云端垃圾号；iOS |
| **CA-1** | 策略备注经 LAN 同步到手机 Companion（仅展示用） | 写系统拦截列表 |
| **CA-2（可选）** | 通讯录只读匹配姓名；Mac 备注 → 写手机 Meo 账户 | 覆盖用户 Google/厂商主账户（默认不抢写） |
| **远期（本文不排期）** | 黑名单、Call Screening 拒接、可选归属地库 | — |

---

## 2. 可行性分项评估

### 2.1 来电状态（Android）

**结论：可行，成熟。**

| 项 | 说明 |
|----|------|
| API | Android 12+：`TelephonyManager.registerTelephonyCallback` + `CallStateListener`；低版本：`PhoneStateListener`（已弃用但仍可用） |
| 状态 | `IDLE` / `RINGING` / `OFFHOOK` |
| 权限 | Manifest + 运行时：`READ_PHONE_STATE`（dangerous） |
| 保活 | 必须在已运行的 `CompanionConnectionService`（前台服务）内注册监听；仅 Activity 内注册会随进程冻结漏事件 |
| OEM | 小米 / 华为需额外「自启动 / 后台运行」引导（复用现有 Setup 向导模式） |

**用户设置步骤（App 内向导应覆盖）：**

1. 打开 Meo Companion →「来电提醒」开关  
2. 授权「电话」权限（`READ_PHONE_STATE`）  
3. 授权「来电筛选」角色（见下节）以获得号码  
4. 确认与 Mac 已配对且绿点已连接  
5. 部分机型：设置 → 应用启动管理 → 允许自启动 / 后台活动  

### 2.2 来电号码（Android）— 关键难点

**结论：有条件可行；路径必须选对。**

| 路径 | 能否拿号码 | Play 友好度 | 推荐 |
|------|------------|-------------|------|
| A. `READ_PHONE_STATE` alone | 仅状态，**无号码**（API 29+） | 高 | 不够 |
| B. `READ_CALL_LOG` + 广播 `EXTRA_INCOMING_NUMBER` | 能 | **极低** | 仅侧载可考虑 |
| C. `CallScreeningService` + `ROLE_CALL_SCREENING` | 能 | **较高** | **主推** |
| D. 解析电话 App 通知文案 | 不稳定 | 中 | 兜底，不可靠 |

**主推架构：C**

```text
用户授予 ROLE_CALL_SCREENING
  → 系统在响铃前 bind CallScreeningService
  → onScreenCall(details) 取号码
  → respondToCall（一律允许响铃；本期不做拒接）
  → TelephonyCallback 跟踪 RINGING → OFFHOOK → IDLE
  → 经 Companion 推送 call_event 到 Mac
```

**注意：**

- 挂断靠 `TelephonyCallback` 的 `IDLE` 补齐「结束」事件。  
- Call Screening 与用户已装的骚扰拦截 App **可能互斥**，产品文案须说明。  
- `onScreenCall` 须在约 **5 秒内** `respondToCall`；本期逻辑仅为「放行」，无策略查询压力。

### 2.3 Mac 系统通知栏

**结论：可行。**

- 权限：`UNUserNotificationCenter` alert + sound（已有申请路径）  
- 标题：`来电 · {备注名或号码}`  
- 正文：`{规则类型提示}`（如「可能是服务热线」）；响铃中更新同一 `request.identifier`；挂断后移除或改为「未接」  
- 左侧图标仍是 MeoBrowser（系统限制）  
- 点击：激活浏览器并显示来电条（可选）

### 2.4 浏览器内跨标签页提醒

**结论：可行。**

| 设计点 | 定稿 |
|--------|------|
| 作用域 | **跨标签、跨窗口**；挂在窗口内容区顶部；**不要**塞进 WKWebView |
| 展示 | 号码、用户备注、规则类型标签；快捷「备注」 |
| 生命周期 | `ringing` → `active`（通话中）→ `ended`/`missed` 后 3～5s 收起 |
| 多窗口 | 单例状态驱动所有主窗口 |
| 浮层优先级 | 高于页面查找条 |

### 2.5 号码类型判断 — 定稿：最简规则（不用大型号段库）

#### 2.5.1 明确砍掉的内容

| 不做 | 原因 |
|------|------|
| 内置 `phone.dat` / 省市区归属地 | 约 4～5 MB，维护成本高，本期不需要精确归属 |
| 商业/众包垃圾号库、第三方 API | 体积、隐私、过期问题 |
| 根据手机号前三位猜「北京/上海」等 | 属归属地范畴，本期不做 |

#### 2.5.2 最简规则引擎（`PhoneRuleClassifier`）

纯代码 / 小 JSON 表（建议 **&lt; 2 KB**），在 Mac 收到 `call_event` 后同步执行；Android 可选同样跑一份仅用于本地 UI。

**归一化（L0）**

```text
去空格、去横线；若以 +86 / 0086 / 86 开头则去掉国家码
保留数字；过短（&lt; 3）→ unknown
```

**规则表（L1，按匹配优先级从高到低，命中即停）**

| 优先级 | 条件（示意） | category | UI 文案 |
|--------|--------------|----------|---------|
| 1 | `presentation == restricted` 或号码空 | `private` | 私人号码 / 未知号码 |
| 2 | 长度 3～6 且以 `95`/`96`/`10`/`11`/`12` 等短号常见头 | `hotline` | 可能是服务短号 |
| 3 | 去国家码后以 `400` / `800` 开头 | `institution` | 可能是企业热线 |
| 4 | 以 `95` 开头且总长约 5～10 | `institution` | 可能是机构/客服 |
| 5 | 国内 11 位且以 `1` 开头（`1[3-9]\d{9}`） | `mobile` | 手机号码 |
| 6 | 以 `0` 开头且长度 10～12（固话形态） | `landline` | 可能是固话 |
| 7 | 其它 | `unknown` | 未知类型 |

**类型枚举（本期）：**

```text
unknown | private | mobile | landline | hotline | institution | personal | business | marketing
```

说明：

- `personal` / `business` / `marketing` **只来自用户策略库标注**，规则引擎不自动猜「广告」。  
- 规则只给出弱提示（「可能是…」），避免假装精确归属地。  
- 规则表放在仓库内一份共享 JSON（如 `Resources/PhoneRules/simple_rules.json`），双端可读；改规则发版即可，**无大数据文件**。

#### 2.5.3 用户策略库（L2，最强）

用户在 Mac 工具栏为某号码设置：

- `displayName`（备注）  
- `category`（上表枚举，含 personal / business / marketing 等）  

展示优先级：

```text
1. 用户策略库备注 + category
2. call_event.contactName（若有通讯录权限，后期）
3. 规则引擎 category + 文案
4. 仅显示号码
```

### 2.6 与手机通讯录同步（后期，CA-2）

**结论：可行；本期可不实现。**

| 方向 | 可行性 | 说明 |
|------|--------|------|
| 手机 → Mac 显示名 | ✅ | `READ_CONTACTS` + `PhoneLookup` |
| Mac 备注 → 手机 | ✅ | `WRITE_CONTACTS`，写入 Meo 自有 Account |

首次写入前二次确认。拒绝权限则仅用本地策略库。

### 2.7 黑名单（本期明确不做）

**本期：不设计、不实现、不出现在 UI / 协议字段。**

远期若做，再评估：

- Meo 策略库标记 vs Call Screening 拒接 vs 系统 `BlockedNumberContract`（后两者受限更大）  
- 与现有骚扰拦截 App 的互斥问题会更突出  

当前 Call Screening **仅用于取号并一律放行**。

---

## 3. 用户场景

### 3.1 工作中来电

```
手机响铃（已配对 + 已授 Call Screening）
  → Companion 推送 call_event { state: ringing, number, … }
  → Mac 规则引擎：138… →「手机号码」
  → 系统通知：「来电 · 13812345678」正文「手机号码」
  → 若策略库有备注「张三」→ 标题用「来电 · 张三」
  → MeoBrowser 所有窗口顶部出现来电条
  → 用户可点「备注」写入策略库
  → 挂断 → 「未接/结束」后自动消失
```

### 3.2 管理策略库

```
点工具栏「电话策略」图标
  → 面板：号码 / 备注 / 类型 + 搜索
  → 编辑后本地保存；（CA-1）经 LAN 同步到手机 Companion
```

### 3.3 未授权降级

| 缺失 | 行为 |
|------|------|
| 无 READ_PHONE_STATE | 功能关闭；设置页引导 |
| 无 Call Screening | 强制引导；不推送无号码来电（见 D1） |
| 无 Mac 通知权限 | 仅浏览器内横幅 |
| 无通讯录权限 | 不影响 MVP（通讯录为后期） |
| 未连接 | 事件丢弃（同通知镜像） |

---

## 4. 产品行为定稿

| 项 | 定稿 |
|----|------|
| 总开关 | Android / Mac 默认 **关** |
| 获取号码 | **仅 Call Screening** |
| 未接提醒 | 开；同 id 更新通知 |
| 浏览器横幅 | 开；可关 |
| 系统通知 | 开；可关 |
| 类型判断 | **最简规则表**，默认开 |
| 省市区归属地 | **不做** |
| 通讯录同步 | 后期；默认关 |
| 黑名单 / 拒接 | **不做** |
| 日志 | 不打印完整号码 |

---

## 5. 协议扩展（建议 V2.2）

传输、发现、鉴权、帧格式不变。落地时同步 [companion-protocol.md](companion-protocol.md)。

### 5.1 `call_event`（Android → Mac）

```json
{
  "v": 1,
  "type": "call_event",
  "deviceToken": "long-token",
  "id": "call-uuid-or-stable-key",
  "state": "ringing",
  "number": "+8613812345678",
  "numberRaw": "13812345678",
  "presentation": "allowed",
  "contactName": "张三",
  "ts": 1710000000,
  "eventMs": 1710000000123
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | ✅ | 同一次通话稳定 id |
| `state` | ✅ | `ringing` \| `active` \| `ended` \| `missed` |
| `number` | 推荐 | E.164；未知可空 |
| `numberRaw` | 可选 | 原始显示串 |
| `presentation` | 可选 | `allowed` \| `restricted` \| `unknown` \| `payphone` |
| `contactName` | 可选 | 后期通讯录匹配；MVP 可空 |
| `ts` / `eventMs` | ✅ / 可选 | 龄期与排序 |

> 无 `rejected` / 黑名单相关字段。类型判断在 **Mac 本地**用规则引擎计算，不强制 Android 上传 category。

### 5.2 `call_event_ok`（Mac → Android）

```json
{ "v": 1, "type": "call_event_ok", "id": "call-uuid-or-stable-key" }
```

### 5.3 号码备注同步（CA-1）

推荐复用 V3：`kind = phone_policy`。

```json
{
  "id": "uuid",
  "numberE164": "+8613812345678",
  "displayName": "快递驿站",
  "category": "business",
  "notes": "",
  "updatedAt": 1710000000,
  "deviceId": "mac-host",
  "deleted": false,
  "syncToContacts": false
}
```

> **无 `blacklisted` 字段。** MVP 可先只做 Mac 本地策略库，CA-1 再开同步。

### 5.4 与通知镜像并存

来电走 `call_event`，不依赖「全部通知」模式；独立开关。

---

## 6. Android 设计

### 6.1 模块职责

| 组件 | 职责 |
|------|------|
| `CallAlertPrefs` | 总开关 |
| `CallStateMonitor` | 通话状态机 |
| `MeoCallScreeningService` | 取号；**一律放行** |
| `CallEventPusher` | 发送 `call_event` |
| `PhonePolicyStore` | （CA-1）接收 Mac 备注同步 |
| `NumberNormalizer` | 号码归一 |
| Setup 向导 | 电话权限 + Call Screening 引导 |

### 6.2 权限清单

| 权限 / 角色 | 用途 | MVP |
|-------------|------|-----|
| `READ_PHONE_STATE` | 通话状态 | ✅ |
| `ROLE_CALL_SCREENING` | 来电号码 | ✅ |
| `READ_CONTACTS` / `WRITE_CONTACTS` | 通讯录 | 后期 |
| `READ_CALL_LOG` | — | ❌ 避免 |
| 前台服务（已有） | 保活 | ✅ |

### 6.3 通话状态机

```text
         screen/ring
  idle ─────────────► ringing ──接听──► active
    ▲                    │               │
    │                    │未接            │挂断
    └────── ended / missed ◄─────────────┘
```

### 6.4 Call Screening 响应

本期固定：允许响铃，不静音、不拒接。

---

## 7. Mac 设计

### 7.1 模块职责

| 组件 | 职责 |
|------|------|
| `CompanionChannel` | 解析 `call_event` |
| `CallAlertPresenter` | 系统通知 |
| `CallAlertBannerController` | 跨窗口来电条 |
| `PhonePolicyStore` | 备注 / 类型持久化 |
| `PhoneRuleClassifier` | **最简规则表**（取代 GeoLookup） |
| 工具栏 `phonePolicy` | 打开管理面板 |

### 7.2 跨标签来电条 UI（草图）

```
┌──────────────────────────────────────────────────────────────┐
│ 📞 来电  张三  13812345678  · 手机号码          [备注]  [✕]   │
└──────────────────────────────────────────────────────────────┘
```

- AppKit 自绘；备注输入用 `SBTextField`  
- 无「拉黑」按钮  

### 7.3 工具栏入口

- Action id：`phonePolicy`  
- SF Symbol：`phone.badge.waveform`（或同类）  
- 点击打开管理面板；不占用互联圆点  

### 7.4 管理面板能力（MVP）

- 列表 / 搜索  
- 新增、编辑备注与类型  
- 删除条目  
- （可选）导入导出 JSON  
- **无**黑名单筛选、**无**归属地版本号  

---

## 8. 轻量规则与策略库

### 8.1 存储

| 端 | MVP |
|----|-----|
| Mac | JSON / UserDefaults 旁路或小 SQLite |
| Android | CA-1 再落 Room；MVP 可无 |
| 规则表 | 仓库内 `simple_rules.json`，双端共享或仅 Mac |

### 8.2 查询优先级

```text
1. 策略库 displayName / category
2. contactName（后期）
3. PhoneRuleClassifier
4. 仅号码
```

### 8.3 规则表示例（可直接落地）

```json
{
  "version": 1,
  "rules": [
    { "id": "private", "when": "empty_or_restricted", "category": "private", "label": "私人号码" },
    { "id": "400", "when": "prefix", "prefix": ["400", "800"], "category": "institution", "label": "可能是企业热线" },
    { "id": "95", "when": "prefix", "prefix": ["95"], "minLen": 5, "maxLen": 10, "category": "institution", "label": "可能是机构/客服" },
    { "id": "short", "when": "length_in", "minLen": 3, "maxLen": 6, "category": "hotline", "label": "可能是服务短号" },
    { "id": "mobile", "when": "regex", "pattern": "^1[3-9]\\d{9}$", "category": "mobile", "label": "手机号码" },
    { "id": "landline", "when": "regex", "pattern": "^0\\d{9,11}$", "category": "landline", "label": "可能是固话" }
  ],
  "fallback": { "category": "unknown", "label": "未知类型" }
}
```

实现注意：先归一化再匹配；`prefix` 在去掉 `+86` 之后判断。

---

## 9. 隐私、安全与合规

| 项 | 策略 |
|----|------|
| 默认关 | 总开关默认关 |
| 传输 | LAN + deviceToken；号码为 PII，日志打码 |
| 存储 | 策略库本地；不上云 |
| Play | Call Screening；不声明 Call Log |
| Screening 互斥 | UI 说明可能替换原有骚扰拦截 App |

---

## 10. 失败与边界

| 情况 | 行为 |
|------|------|
| 双卡 / 第二路来电 | MVP：最新一路；新 `id` |
| VoIP（微信电话） | 不在本方案（通知镜像） |
| 无主叫号码 | 「未知/私人号码」+ 仍提示来电 |
| 旧版 Mac | 忽略 `call_event` |
| 撤消 Screening | 停用取号并提示重新授权 |

---

## 11. 里程碑与工作量（粗估）

| 阶段 | 内容 | 人日（估） |
|------|------|------------|
| **CA-0** | 协议 + 开关骨架 | 0.5～1 |
| **CA-1** | Android 状态 + Call Screening + `call_event` | 2～3 |
| **CA-2** | Mac 系统通知 + 跨窗来电条 | 2 |
| **CA-3** | 最简规则引擎 + 策略库 CRUD + 工具栏面板 | 2～3 |
| **CA-4** | （可选）策略同步到手机 | 1～2 |
| **CA-5** | （可选）通讯录读写 | 2～3 |
| **CA-6** | 真机验收 | 1～2 |

合计 MVP（CA-0～CA-3 + 验收）约 **8～11 人日**（相对原含 phone.dat/黑名单方案明显缩短）。

**首版交付：CA-0～CA-3。**

---

## 12. 验收标准（首版）

1. 授权后来电出现在 Mac 系统通知，标题含号码或备注。  
2. 任意标签/多窗口顶部同步来电条；挂断后收起。  
3. 未授 Call Screening 时设置页有引导。  
4. 工具栏可管理备注与类型；重启仍在。  
5. `400` / 11 位手机号等能显示对应**规则文案**（非省市区）。  
6. UI / 协议中**无**黑名单、拉黑、拒接入口。  
7. 工程中**无** `phone.dat` 或等价大型号段资源。  
8. 关闭总开关后不再推送；日志无完整号码。

---

## 13. 待拍板决策

| ID | 问题 | 建议默认 |
|----|------|----------|
| D1 | 无 Call Screening 是否仍推「无号码来电」 | **否** |
| D2 | 策略同步何时做 | **MVP 仅 Mac 本地；CA-4 再同步** |
| D3 | 规则表仅 Mac 还是双端 | **MVP 仅 Mac**（展示在电脑侧） |
| D4 | 黑名单 | **本期不做**（已定） |
| D5 | 省市区归属地 / phone.dat | **本期不做**（已定） |
| D6 | iOS Companion | **不做** |
| D7 | Play 上架 | 先侧载跑通；Play 则坚持 Screening、禁 Call Log |

---

## 14. 架构示意

```text
┌──────────────────────────────────┐          LAN JSON         ┌────────────────────────────────────┐
│  Meo Companion (Android)         │  ───────────────────────► │  MeoBrowser (macOS)                │
│                                  │                           │                                    │
│  MeoCallScreeningService         │   call_event              │  CompanionChannel                  │
│    └─ number；一律放行            │ ────────────────────────► │    ├─ CallAlertPresenter           │
│  CallStateMonitor                │                           │    └─ CallAlertBannerController    │
│  CompanionConnectionService      │                           │  PhoneRuleClassifier（小规则表）   │
│                                  │                           │  PhonePolicyStore（备注/类型）      │
│                                  │                           │  工具栏 phonePolicy 管理面板         │
└──────────────────────────────────┘                           └────────────────────────────────────┘
```

---

## 15. 文档与代码索引（落地时）

| 资源 | 预期路径 |
|------|----------|
| 本方案 | `docs/minimal-browser/companion-call-alert-feasibility-and-design.md` |
| 协议 | `docs/minimal-browser/companion-protocol.md`（增 V2.2） |
| Android Screening / Monitor | `companion/android/.../call/` |
| Mac Presenter / Banner | `SimpleBrowser/LoginAssist/Companion/CallAlert*.m` |
| 规则表 | `Resources/PhoneRules/simple_rules.json`（或仅 Mac bundle） |
| 策略库 UI | ActionGroup `phonePolicy` + 管理窗 |

---

## 16. 总结

1. 来电状态 → Mac 通知 + 跨标签横幅：**可行**，复用 Companion。  
2. 取号：**Call Screening**；本期只放行、不拒接。  
3. 类型判断：**几十行规则表**，不引入大型号段开源库。  
4. 用户备注策略库 + 工具栏管理：**MVP 核心**。  
5. **黑名单、系统拒接、phone.dat 归属地：本期全部不做。**  

确认后可拆 `companion-call-alert-development-plan.md` 并开工 CA-0。
