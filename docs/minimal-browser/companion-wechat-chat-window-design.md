# 微信通知会话窗（WH）— 可行性评估与实现方案

> 状态：**WH-0 已实现** · 日期：2026-07-22  
> 关联：[companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md) · [companion-wechat-sidebar-reply-design.md](companion-wechat-sidebar-reply-design.md) · [companion-protocol.md](companion-protocol.md)

---

## 0. 一句话结论

| 诉求 | 结论 |
|------|------|
| 侧栏保留**全部通知历史**（尤其微信） | **可行**。当前「同联系人只留最新一条」主要是 Android `sbn.key` 复用 + Mac 同 `id` **覆盖写**，不是能力做不到 |
| 按通知标题（用户名）开**独立聊天窗** | **可行**。Mac 本地新「会话线程」模型即可，不改手机微信真聊天协议 |
| 窗内展示：入站通知历史 + 本机发出回复历史 | **可行**。入站靠镜像 append；出站靠 `wechat_reply_ok` 落库 |
| 发送后**停在窗内可连续聊**，点关闭才关 | **可行**。把现有一次性 Alert sheet 换成常驻 `NSPanel`/`NSWindow` |

**总评：产品可落地；优先做 Mac 本地会话模型 + 聊天窗 UI，协议几乎不用动。**  
限制要写进文案：**不是完整微信聊天记录**（只含「出过系统通知的内容」+「经 Meo 发出的回复」），身份只有显示名。

---

## 1. 用户目标（原话对齐）

1. Mac 通知侧栏**保留所有通知历史**，尤其微信。  
2. 微信：按通知 **title（用户名/会话名）** 进入独立聊天窗口。  
3. 窗口内：该用户相关的**全部通知历史** + **我发出的回复历史**。  
4. 发送后窗口不关，可继续聊；用户点关闭才关。

---

## 2. 现状为何「同人只留一条」

```text
微信刷新同一会话通知
  → Android 常用同一 StatusBarNotification.key
  → phone_notification.id 不变（package:key）
  → Mac PhoneNotificationInboxStore 按 id upsert → 覆盖 title/body
  → 侧栏视觉上「只剩最新一条」
```

| 层 | 行为 | 文件 |
|----|------|------|
| Android ID | 优先 `package:sbn.key` | `NotificationPayloadBuilder.buildId` |
| Android 闸门 | 同 id 60s 内可丢弃 | `NotificationMirrorGate` |
| Mac 入库 | **仅按 `itemID` 覆盖**，无 `(package,title)` 线程 | `PhoneNotificationInboxStore upsertMirrorPayload:` |

侧栏本身是**扁平通知列表**，没有「会话」概念；WR 回复成功也**只 toast，不落出发历史**。

---

## 3. 可行性评估

### 3.1 能做到的

| 能力 | 依据 |
|------|------|
| 入站多条历史 | 改入库策略：微信（或全局）改为 **append 消息**，或「会话行 + 消息表」双层；不必改 Companion 推送频率也能先把「每次推上来且 id 变了」的都留住；若要保留「同 key 刷新的每一版正文」，需 Android 侧在 body 变化时生成**新消息 id** 或另发 `phone_notification_append` |
| 按 title 会话窗 | Mac 用 `threadKey = packageName + "\n" + normalize(title)` 聚合 |
| 出站历史 | `wechat_reply_ok` 时写入本地 `direction=out`；失败可标红/可重试 |
| 连续聊天 UX | 独立 panel：列表 + 输入框；发送走现有 `wechat_reply`；成功后清空输入框、append 气泡、保持 firstResponder |
| 与现有 WR | 复用 Android 执行器与实验开关/无障碍；聊天窗只是更好的 Mac 壳 |

### 3.2 做不到 / 做不全（必须产品诚实）

| 限制 | 说明 |
|------|------|
| ≠ 微信聊天记录同步 | 没出过通知的消息、已划掉未镜像的、静默消息，Mac **没有** |
| 同名误聚 | 只有显示名，无 wxid；两人同备注会并进同一线程（与 WR 相同风险） |
| 群聊 | MVP 可先按 title 一视同仁；@、引用不做 |
| 多媒体 | 通知里通常只有文本预览；图/语音只能显示「[图片]」类摘要（若通知自带） |
| 对方已读/输入中 | 无协议字段 |
| 同 id 刷新丢中间态 | 若不改 Android，同一 `sbn.key` 连续更新仍可能只见到最后一次 upsert；要「每一次正文变更都留档」必须改推送 id 或 append 语义 |

### 3.3 风险

- 存储膨胀：全量 append + 7 天/2000 条策略要按**消息条数**重算。  
- 隐私：本地明文 JSON 含私信；沿用收件箱路径与加密远期议。  
- 连续发送：手机端仍有 ~2s/条与 `busy`；窗内需排队或禁用连点。

**结论：可以实现「通知衍生的轻量会话窗」；不能宣传成「微信电脑版聊天同步」。**

---

## 4. 推荐产品形态

### 4.1 信息架构

```text
侧栏（收件箱，仍扁平或微信可折叠）
  ├─ 其它 App：保持现有通知行
  └─ 微信：可显示「会话摘要行」（最新一条 + 未读数）
        └─ 双击 / 右键「打开会话」→ 会话窗（NSPanel）

会话窗（每 threadKey 一窗，可多开）
  ├─ 标题：联系人显示名
  ├─ 消息列表：时间序气泡（入站左 / 出站右）
  ├─ 底部：SBTextField + 发送（⌘↩）
  └─ 关闭按钮 / 窗关闭 → 销毁或隐藏（推荐隐藏保历史）
```

### 4.2 交互

| 操作 | 行为 |
|------|------|
| 双击微信通知行 | **打开/前置**该 title 的会话窗（替换或并行于现「回复 sheet」；建议双击 = 开会话，不再弹一次性 Alert） |
| 窗内发送 | `wechat_reply`；成功 append 出站；失败 toast + 可重试；**不关窗** |
| 新通知到达且 thread 匹配 | 若窗已开：底部插入气泡并可选轻微滚动；侧栏摘要更新 |
| 关闭 | 仅关 UI；历史留在本地库 |

### 4.3 侧栏「保留所有历史」两种档位

| 档位 | 行为 | 复杂度 |
|------|------|--------|
| **A. 会话内全历史（推荐 MVP）** | 扁平侧栏仍可对微信做摘要合并；**完整历史只在会话窗** | 中 |
| **B. 侧栏也逐条列出每次通知** | 微信每次 body 变更都占一行；列表更吵 | 低改存储、高改 UX |

推荐 **A**：侧栏干净，历史在会话窗查。

---

## 5. 数据模型（Mac 本地）

### 5.1 线程 `PhoneChatThread`

| 字段 | 说明 |
|------|------|
| `threadId` | 稳定 id：`sha1(packageName + "\0" + normalizeTitle(title))` 或 UUID + 索引 |
| `packageName` | `com.tencent.mm` |
| `title` | 当前显示名（备注变更时可更新，旧消息仍挂本 thread） |
| `lastMessageAt` / `lastPreview` / `unreadCount` | 侧栏摘要 |
| `pinned` | 可选 |

`normalizeTitle`：复用 Android/Mac 已有规则（去未读角标、冒号前缀等）。

### 5.2 消息 `PhoneChatMessage`

| 字段 | 说明 |
|------|------|
| `messageId` | 入站：可用 `notificationId + "#" + bodyHash + "#" + postTimeMs` 防重复；出站：UUID |
| `threadId` | |
| `direction` | `in` \| `out` |
| `text` | 正文 |
| `createdAt` | |
| `notificationId` | 入站关联（可选） |
| `requestId` | 出站关联 `wechat_reply` |
| `status` | 出站：`sending` \| `sent` \| `failed` |

### 5.3 与现有 `PhoneNotificationItem` 关系

- **短期**：收件箱表保留；微信 upsert 时**额外** `append` 一条 `PhoneChatMessage`（若正文相对该线程上次入站有变化）。  
- **侧栏微信行**：可由 `PhoneChatThread` 生成摘要，或继续用最新 `PhoneNotificationItem` 作入口。  
- **长期（可选）**：微信不再占用「每人一行通知」，只进会话库。

### 5.4 持久化

- 路径建议：`~/Library/Application Support/MeoBrowser/PhoneChat/`  
  - `threads.json` + `messages/{threadId}.jsonl`（append-friendly）或单库 SQLite（消息量大时更优）  
- MVP 可用 JSONL；预估每消息 <1KB，1 万条可接受。  
- 保留策略：消息 `createdAt` 超 `retentionDays` 删除；或每线程上限 N 条（如 500）。

---

## 6. 入库与去重策略（关键）

### 6.1 Mac（MVP 必做）

收到 `phone_notification` 且 `packageName == com.tencent.mm`：

1. `thread = ensureThread(title)`  
2. 若 `shouldAppend(thread, body, postTimeMs, notificationId)`：  
   - 与该线程**最后一条入站**正文相同且时间间隔 < 2s → 跳过（防重复推）  
   - 否则 append `direction=in`  
3. 更新线程摘要；若会话窗打开则 UI 插入  
4. 收件箱：可继续同 id 覆盖（侧栏摘要），**或**改为不覆盖、只更新 preview

### 6.2 Android（增强，WH-1）

目标：同 `sbn.key` 但 **EXTRA_TEXT 变化** 时也留下历史。

方案二选一：

1. **派生消息 id**：`id = originalKey + ":" + bodyHash`（或 `postTimeMs`），使 Mac 视为新行/新消息；或  
2. **新类型** `phone_notification_message`：只带 `threadTitle/body/postTime`，专供会话库 append，不影响收件箱 id 语义。

推荐 2，语义更清晰；MVP 可先只做 6.1，接受「同 key 刷新可能丢中间正文」。

### 6.3 出站

```text
用户点发送
  → 本地先 insert status=sending（乐观 UI）
  → wechat_reply
  → ok：status=sent
  → err：status=failed，保留文案可重试
```

---

## 7. UI 方案（AppKit）

### 7.1 会话窗

- `NSPanel`（`floating` / `utility`）或普通 `NSWindow`，`releasedWhenClosed=NO`，关闭即 `orderOut`。  
- 消息区：`NSTableView`/`NSOutlineView` 或简单 `NSScrollView` + stack；气泡可用自定义 `NSView`。  
- 输入：**必须** `SBTextField`（仓库规范）；发送按钮；⌘↩ 发送。  
- 多窗：`NSMapTable<threadId, WindowController>`。

### 7.2 侧栏改动

- 微信行副标题：最新预览 + 可选未读点。  
- 双击：`openOrFocusChat(thread)`。  
- 右键：保留「回复…」可改为「打开会话」；「复制」等不变。  
- 非微信：行为不变。

### 7.3 空态 / 失败

- 无障碍未开、后台弹出未开：窗内横幅提示（复用现 toast 文案）。  
- 发送中：输入区 disable 或队列深度 1。

---

## 8. 协议影响

| 消息 | 是否需要改 |
|------|------------|
| `phone_notification` | MVP **不强制**；WH-1 可选 append 语义或新 type |
| `wechat_reply` / `_ok` / `_err` | **不改字段**；Mac 用 `requestId`/`contact` 落库 |
| 新协议 | 可选 `wechat_chat_sync`（远期从手机拉历史）— **本期不做** |

---

## 9. 分期实现

### WH-0（约 2～3 人日）— 会话窗 MVP ✅

1. `PhoneChatStore`：thread + message 落盘；微信入站 append（正文变化才追加）。  
2. `PhoneChatWindowController`：列表 + `SBTextField` + 发送；成功不关窗。  
3. 侧栏双击微信 → 开会话窗；出站写入 `wechat_reply_ok`。  
4. 保留策略与收件箱天数对齐。  

**验收**：同联系人连续两条不同通知正文 → 窗内两气泡；发出两条回复 → 窗内可见；关窗再开历史仍在。

实现文件：`PhoneChatModels` / `PhoneChatStore` / `PhoneChatWindowController`；入库接线于 `PhoneNotificationInboxStore`；侧栏双击/「打开会话…」。

### WH-1（约 1～2 人日）— 历史更完整

1. Android：body 变化时稳定 append（新 id 或新 message 类型）。  
2. 侧栏微信改「会话摘要行」+ 未读数。  
3. 失败重试、发送队列。

### WH-2（可选）

1. 全局「所有通知」也改为严格 append（非覆盖）可选开关。  
2. 搜索会话 / 导出。  
3. SQLite 迁移。

---

## 10. 明确不做（本期）

- 同步手机微信完整聊天记录、漫游  
- 无通知联系人的冷启动会话列表  
- 图片/语音/红包发送  
- 云同步会话库  
- 多设备 Mac 共用同一会话库

---

## 11. 工作量与依赖

| 项 | 估计 |
|----|------|
| WH-0 | 2～3 人日（纯 Mac + 少量侧栏接线） |
| WH-1 | 1～2 人日（含 Android） |
| 依赖 | 现有 WR 实验开关、无障碍、后台弹出；Companion 已连接 |

---

## 12. 建议决策

1. **做**：以「通知衍生会话窗」立项 WH-0，满足「历史 + 连续聊 + 关窗才关」。  
2. **文案**：设置/窗内注明「仅含通知镜像与 Meo 发出的消息，不是完整微信记录」。  
3. **双击行为**：从「一次性回复 sheet」升级为「打开会话窗」（更符合连续聊）。  
4. **同 key 刷新**：WH-0 先 Mac 侧尽量 append；要「一条不漏」再上 WH-1 Android。

若认可本方案，下一步可直接按 WH-0 拆任务实现（Store → Window → 侧栏双击接线 → 出站落库）。
