# 侧栏微信快捷回复（WR）可行性评测与方案

> 状态：**WR-0 + WR-1 已实现** · 日期：2026-07-22  
> 关联：[companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md) · [companion-protocol.md](companion-protocol.md) · [companion-notification-mirror-design.md](companion-notification-mirror-design.md)

## 1. 目标

在 Mac MeoBrowser **手机通知侧栏**中，对微信类通知提供「直接回复」：

1. 用户在侧栏选中一条微信消息（`packageName == com.tencent.mm`，`title` ≈ 联系人/会话名）
2. 输入回复文案，点发送
3. Mac 经 Companion 通道把 `{ contact: title, text }` 发到 Android
4. 手机自动：打开微信 → 进入对应用户会话 → 粘贴文案 → 点「发送」

## 2. 真机评测结论（2026-07-22）

**设备**：小米 2304FPN6DC（ishtar）· **微信**：8.0.76（`versionCode=3141`）· **Companion**：debug + 探测用 AccessibilityService


| 步骤                                        | 方法                                       | 结果                          |
| ----------------------------------------- | ---------------------------------------- | --------------------------- |
| A. 通知 Reply API                           | `Notification.Action` / `RemoteInput`    | **不可用**（微信未暴露）              |
| B1. 第三方 Accessibility 读微信节点树              | Companion `WeChatA11yProbeService`       | **失败**：`childCount=0`（微信挖空） |
| B2. TalkBack / 系统读屏开启时 `uiautomator dump` | 可读 `EditText id/bkk`、`发送 id/bql`         | **成功**                      |
| B3. 打开会话列表 → 点「平安喜乐」                      | dump 找 `text==联系人名` → `input tap`        | **成功**                      |
| B4. 剪贴板写入中文 → 点输入框 → `KEYCODE_PASTE`      | Companion `ClipboardManager` + adb paste | **成功**（输入框=`测试自动发送`，出现「发送」） |
| B5. 点击「发送」                                | dump 找 `text==发送` / `id/bql` → tap       | **成功**（气泡出现；输入框清空）          |


端到端实测文案 **「测试自动发送」** 已出现在与「平安喜乐」的聊天记录中（约 15:12）。

### 2.1 总评


| 维度      | 评定                                                     |
| ------- | ------------------------------------------------------ |
| 技术可行性   | **受限可行**（依赖「可读 UI 树」或等价手段，不能指望纯第三方无障碍读微信）              |
| 产品可落地性  | **可做 MVP**，须明确权限、失败态、仅私聊/按显示名匹配                        |
| 推荐优先级   | 作为侧栏 **微信专用增强**，默认关；需用户开启无障碍/读屏类能力                     |
| 与既有设计冲突 | 侧栏设计 §2.4 曾标「回复微信 = 超出边界」→ 本方案作为 **WR-MVP 例外**，范围收窄到微信 |


**结论：可以采用「Mac 侧栏回复 → Companion 指令 → 手机 UI 自动化发送」这条路径做产品功能。**  
推荐实现形态见 §4（**TalkBack/增强读屏可读树 + Companion 剪贴板 + 点击**，或后续收敛为自研「桥接」方案）。

## 3. 约束与风险（必须写进产品文案）

### 3.1 硬约束

1. **微信反自动化**：对普通第三方 AccessibilityService 返回空树；对 TalkBack 等读屏服务开放节点。MVP 需用户开启可读树的无障碍服务（见 §4.2）。
2. **身份只有显示名**：侧栏只有通知 `title`（如「平安喜乐」），没有微信号 / username。同名联系人、群名与好友重名、备注名变更会导致误入会话。
3. **resource-id 会变**：`com.tencent.mm:id/bkk`（输入框）、`id/bql`（发送）随版本漂移；策略应以 **文案/角色**（`发送`、`EditText`）为主，id 为辅。
4. **中文不能靠 `input text`**：IME 会篡改（实测 `MeoB_E2E_OK` → `M2B——EE——OK`）。**必须剪贴板 + 粘贴**。
5. **通道明文**：现有 Companion 局域网 JSON 明文；回复内容含私信，设置里需风险提示（与「全部通知」同级）。
6. **ROM 差异**：MIUI 可能清掉 adb 写入的无障碍开关；正式产品须引导用户在系统设置里手动开启。

### 3.2 明确不做（MVP）

- 群聊 @、表情面板、图片/语音
- 未出过通知的联系人（侧栏没有对应 `title`）
- iOS Companion
- 不打开微信的静默服务端代发（无合法 API）
- 依赖已失效的 `weixin://dl/chat`

### 3.3 风控与合规

- 自动化操作微信可能触发账号风控；产品定位为 **个人自用辅助**，非批量营销。
- 仅操作用户本机已登录微信；不上传聊天记录到云。

## 4. 推荐技术方案

### 4.1 架构

```text
Mac 侧栏（微信行）
  └─ 回复框 / 右键「回复」
       │  wechat_reply { requestId, deviceToken, contact, text, notificationId? }
       ▼
CompanionChannel / Bonjour JSON
       ▼
Android CompanionConnectionService.handleMessage
       ▼
WeChatReplyExecutor（由探测服务升级）
  1. 确保可读树无障碍已开（否则回 wechat_reply_err）
  2. 启动微信 LauncherUI
  3. 若已在目标聊天则跳过；否则会话列表/搜索匹配 contact=title
  4. ClipboardManager 写入 text
  5. 聚焦输入框 → ACTION 或 KEYCODE_PASTE
  6. 点击「发送」
  7. 校验：气泡出现或输入框清空 → wechat_reply_ok / _err
```

### 4.2 「可读树」策略（关键路径选择）


| 方案                                                     | 做法                                                          | 优点           | 缺点                              | MVP 建议     |
| ------------------------------------------------------ | ----------------------------------------------------------- | ------------ | ------------------------------- | ---------- |
| **W1. 依赖系统 TalkBack / MIUI 读屏增强**                      | 用户开启；Executor 用 `rootInActiveWindow` 或临时 `uiautomator` 等价遍历 | 真机已验证可读写发送   | 读屏干扰大；教程弹窗；体验差                  | **仅评测/内测** |
| **W2. Companion 自研 Accessibility + 手势/剪贴板，列表用 OCR/坐标** | 不读微信树                                                       | 不依赖 TalkBack | 极脆；适配成本高                        | 不推荐主路径     |
| **W3. Companion Accessibility 声明为读屏类 + 完整能力**          | `FEEDBACK_SPOKEN` 等                                         | 理想态          | **本机实测仍 childCount=0**，微信按包名白名单 | 持续跟进，暂不可用  |
| **W4. 混合：Mac/手机调试桥（adb）**                              | 仅开发者                                                        | 稳            | 不能给普通用户                         | 工程自测       |


**产品 MVP 建议（务实）**：

- **对内 / 开关名**：「微信回复（实验）」；要求开启 **无障碍（可读屏）** 且接受「回复时可能朗读/改变手势」。
- **执行层**：优先用已验证路径——**可读树时节点点击 + Companion 剪贴板粘贴 + 点发送**。
- 若可读树不可用：返回明确错误「请开启读屏类无障碍后再试」，**不要静默坐标乱点**。

> 后续若发现微信对新的合法读屏服务放行，再收敛到「仅 Companion 一键开无障碍、无需 TalkBack」。

### 4.3 联系人匹配策略

按优先级：

1. 当前已在聊天页且标题/相关节点含 `contact` → 直接粘贴发送
2. 会话列表可见行 `text == contact` → 点击进入
3. 点「搜索」→ 粘贴 `contact` → 点最佳匹配结果（精确等于 > 包含）
4. 失败 → `wechat_reply_err` code=`contact_not_found`

**过滤侧栏入口**：仅 `packageName == com.tencent.mm`；排除 `title` 空、明显系统号（可选黑名单：微信团队、微信支付等，可配置）。

## 5. 协议草案

### 5.1 Mac → Android：`wechat_reply`

```json
{
  "v": 1,
  "type": "wechat_reply",
  "deviceToken": "…",
  "requestId": "uuid",
  "contact": "平安喜乐",
  "text": "测试自动发送",
  "notificationId": "optional-phone_notification-id",
  "packageName": "com.tencent.mm"
}
```


| 字段               | 说明                               |
| ---------------- | -------------------------------- |
| `contact`        | 来自侧栏 item.`title`（去前后空白）；最大 64 字 |
| `text`           | 回复正文；最大 1000 字（与通知 body 截断对齐）    |
| `notificationId` | 可选，用于 Mac 侧标记「已回复」               |
| `packageName`    | 预留；MVP 仅接受 `com.tencent.mm`      |


### 5.2 Android → Mac：`wechat_reply_ok` / `wechat_reply_err`

```json
{
  "v": 1,
  "type": "wechat_reply_ok",
  "deviceToken": "…",
  "requestId": "uuid",
  "contact": "平安喜乐",
  "elapsedMs": 4200
}
```

```json
{
  "v": 1,
  "type": "wechat_reply_err",
  "deviceToken": "…",
  "requestId": "uuid",
  "code": "a11y_required|contact_not_found|paste_failed|send_failed|wechat_not_installed|busy|timeout",
  "message": "人可读说明"
}
```

超时建议：Android 侧硬限 **20s**；Mac 等待 **25s** 后本地失败。

## 6. Mac 侧栏 UX

### 6.1 入口

- 仅微信行：悬停或右键出现 **「回复」**；或行内展开简易输入（`SBTextField` + 发送按钮）。
- 非微信 / 无障碍未就绪：入口隐藏或禁用并 tooltip 说明。

### 6.2 交互

1. 点「回复」→ 行下展开输入框（或小 popover），焦点进 `SBTextField`
2. ⌘⏎ 或点发送 → 按钮 loading → 等 `wechat_reply_ok/err`
3. 成功：轻提示「已发送」；可选将该条标已读
4. 失败：展示 `message`（如「未找到联系人平安喜乐」）

### 6.3 设置

- 总开关：`wechatReplyEnabled`（默认 **关**）  
- 文案提示：需开启手机无障碍（读屏）、仅限已镜像的微信通知、按显示名匹配、有风控风险  
- 依赖：侧栏 `inboxEnabled` + Companion 已连接

## 7. Android 实现要点


| 模块                                                           | 职责                                              |
| ------------------------------------------------------------ | ----------------------------------------------- |
| `WeChatReplyExecutor`                                        | 状态机：open → find contact → paste → send → verify |
| `WeChatA11yProbeService` → `WeChatReplyAccessibilityService` | 剪贴板；若节点可用则 `ACTION_SET_TEXT`/`CLICK`；否则报错       |
| `CompanionConnectionService`                                 | 解析 `wechat_reply`，单飞队列（busy）                    |
| 设置页                                                          | 无障碍开关跳转 + 实验功能说明                                |


**单飞**：同一时间只跑一条回复；新请求回 `busy`。

**校验成功**：优先聊天气泡出现相同文案；否则输入框清空且「发送」消失视为成功（弱校验）。

## 8. 工作量与分期


| 阶段       | 内容                                         | 预估      |
| -------- | ------------------------------------------ | ------- |
| **WR-0** | 协议字段；Android Executor 从探测脚本产品化；adb/侧栏开关内测  | 1.5～2 日 |
| **WR-1** | Mac 侧栏回复 UI + Channel API + ok/err；设置开关与文案 | 1.5～2 日 |
| **WR-2** | 搜索路径兜底、错误码完善、忙线队列、基础日志                     | 1 日     |
| **WR-3** | 去掉 TalkBack 依赖的跟进（若微信策略变化）；多机型矩阵           | 不定      |


合计 MVP（WR-0～1）：约 **3～4 人日**。

## 9. 验收标准（WR-MVP）

1. 侧栏一条 `appLabel=微信`、`title=平安喜乐` 的通知，回复「你好」→ 手机该会话出现气泡「你好」。
2. 未开启可读树无障碍 → 明确错误，不误触其它 App。
3. 联系人不存在 → `contact_not_found`，微信停留在可恢复状态。
4. 断线 / 超时 → Mac 显示失败，可重试。
5. 非 `com.tencent.mm` 不出现回复入口。
6. 默认关闭实验开关。

## 10. 决策记录


| ID  | 决策                  | 理由                        |
| --- | ------------------- | ------------------------- |
| D1  | 采用 UI 自动化而非通知 Reply | 真机确认微信无 RemoteInput       |
| D2  | contact = 通知 title  | 协议现有字段唯一可用身份              |
| D3  | 中文必须剪贴板粘贴           | `input text` 被 IME 破坏     |
| D4  | MVP 依赖可读树无障碍        | 第三方服务被微信挖空；TalkBack 路径已验证 |
| D5  | 默认关实验开关             | 越权操作 + 风控 + 体验成本          |
| D6  | 修订侧栏设计「回复超出边界」      | 收窄为微信实验能力，不再全局禁止          |


## 11. 实现资产（仓库内）


| 路径                                                  | 说明                                               |
| --------------------------------------------------- | ------------------------------------------------ |
| `.../a11y/WeChatReplyExecutor.kt`                   | 状态机：开关/无障碍检查 → 开会话 → 粘贴 → 发送                     |
| `.../a11y/WeChatReplyAccessibilityService.kt`       | 无障碍：剪贴板、手势、可读树时节点操作；DEBUG broadcast              |
| `.../a11y/WeChatReplyIntentCache.kt`                | 缓存微信通知 `contentIntent`（按 title）                  |
| `.../a11y/WeChatReplyPrefs.kt`                      | `wechatReplyEnabled` 默认关                         |
| `CompanionConnectionService`                        | 收 `wechat_reply` → `handleWeChatReply` → ok/err  |
| `OtpNotificationListener`                           | 微信通知写入 IntentCache                               |
| `MainActivity`                                      | 实验开关 + 跳转无障碍设置                                   |
| `CompanionChannel`（Mac）                             | `requestWeChatReply…` + `wechat_reply_ok/err` 通知 |
| `PhoneNotificationSidebarController`                | 右键「回复…」+ `SBTextField` 输入 sheet                  |
| `PhoneNotificationInboxSettings.wechatReplyEnabled` | Mac 实验开关，默认关                                     |
| 登录助手设置                                              | 「微信回复（实验）」复选框                                    |


## 12. 下一步

1. ~~产品确认：接受「实验开关 + 读屏无障碍依赖」前提。~~ **已确认**
2. ~~WR-0：协议 + Android Executor。~~ **已完成**
3. ~~WR-1：Mac 侧栏回复 UI + Channel。~~ **已完成**
4. **真机联调**：双端开关 + 无障碍 → 侧栏回复一条微信。
5. WR-2：搜索兜底与错误码打磨。

