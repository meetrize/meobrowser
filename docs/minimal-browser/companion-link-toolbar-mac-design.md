# Mac 地址栏「互联状态」入口 — 设计方案

> 目标：在 Mac MeoBrowser 地址栏右侧工具栏中，增加与 Android 端**同构**的互联状态图标与状态圆点；点击打开互联配对设置；并对 Mac 侧配对设置区做与 App 一致的「标题区 + 状态卡片」美化。  
> 状态：**ML-1～ML-3 已实现**（2026-07-21）；待真机手测多窗口 / Dark Mode / 顺序迁移  
> 关联：[auto-login-design.md](auto-login-design.md) · [companion-protocol.md](companion-protocol.md) · [companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [android-browser-chrome-ui-design.md](android-browser-chrome-ui-design.md) · [find-in-page-design.md](find-in-page-design.md)（ActionGroup 范式）

---

## 1. 方案定位

### 1.1 产品一句话

**一眼知道手机有没有连上，一点就能配对。**  
Mac 地址栏右侧常驻「互联」按钮；状态圆点与 Android 底栏语义对齐；点击进入美化后的互联设置页（现有登录助手窗口内的 Companion 区，经改造后成为主视觉入口）。

### 1.2 为什么现在做

| 现状痛点 | 本方案 |
|----------|--------|
| 连接状态只藏在「登录助手」设置深处 | 地址栏右侧一眼可见 |
| `key.horizontal`（登录助手）表示「有无 Recipe」，**不表示**手机是否在线 | 新增独立「互联」按钮，语义不混 |
| Android 已有底栏互联图标 + 状态圆点 + 美化配对页 | Mac / Android 两端交互同构，降低学习成本 |
| 断连后用户常不知道要去哪检查 | 图标灰点 + 点击直达配对卡 |

### 1.3 与 Android 的同构关系

| 维度 | Android（已做） | Mac（本方案） |
|------|-----------------|---------------|
| 入口位置 | 底栏六键之一 | 地址栏右侧 ActionGroup 一键 |
| 视觉 | 链路图标 + 右上角状态圆点 | **同语义**：SF Symbol + 右上角状态圆点 |
| 三态 | 已连接 / 连接中 / 未连接 | **同三态文案**；底层映射 Mac 通道状态（见 §4） |
| 点击 | 打开「互联与配对」页 | 打开登录助手设置，并**滚到 / 聚焦**互联状态卡片 |
| 设置页 | Toolbar + 返回 + 顶部状态卡片 | **同布局语言**：顶部状态大卡片 + 分区卡片（见 §5） |

两端角色不同（Mac 广播等待，手机主动连接），但**用户看到的状态语言必须一致**：绿=可用、琥珀=进行中、灰=不可用。

### 1.4 做什么 / 不做什么（V1）

| 做 | 不做 |
|----|------|
| ActionGroup 新增 `companionLink` 按钮 + 状态圆点 | 用登录助手 `key` 按钮兼作连接状态（禁止混用） |
| 订阅 `CompanionChannelStateDidChangeNotification` 实时刷新圆点 | 在地址栏内嵌完整配对表单浮层 |
| 点击 → 打开设置并定位到互联卡片 | 新建独立「互联」App / 独立 Preference pane |
| 美化 Companion 区为「状态卡片 + 分区卡片」 | 拆掉登录助手其它 Recipe 管理能力 |
| Tooltip 显示「互联 · 已连接/…」 | 未连接时强制弹窗打断浏览 |
| 默认排序靠近登录助手（见 §3.2） | 强制锁定按钮不可拖拽（仍可进溢出菜单） |

---

## 2. 用户场景

### 2.1 日常确认

```
用户打开 MeoBrowser
  → 地址栏右侧看到「链路」图标，圆点为绿
  → Tooltip：「互联 · 已连接到手机」
  → 继续浏览；验证码 / 同步 / 通知镜像可用
```

### 2.2 首次配对 / 重连

```
圆点为灰（未连接）或琥珀（等待中）
  → 点击互联图标
  → 打开登录助手设置窗口，视口滚到顶部「互联状态」卡片
  → 选择临时配对码或固定安全码，按提示操作
  → 手机连接成功 → 工具栏圆点变绿；卡片标题变「已连接」
```

### 2.3 与登录助手并存

```
登录某站需要验证码
  → 互联圆点已绿（通道 OK）
  → 再点「钥匙」登录助手执行 Recipe
  → 两者职责分离：链路 vs 填表
```

若通道未连且填码失败：保持现有 toast / 提示，并**可附带**「打开互联设置」动作（增强，非必须阻塞 V1）。

---

## 3. 工具栏入口（地址栏右侧）

### 3.1 放置位置

落在现有 `BrowserAddressBarActionGroup`（`SimpleBrowser/AddressBar/BrowserAddressBarActionGroup.m`），与查找 / 下载 / 登录助手同一套：

- 尺寸：28×28 pt，间距 2 pt  
- 风格：`NSBezelStyleInline`、无边框、SF Symbol 15pt medium  
- 支持拖拽排序与溢出「更多工具」菜单（沿用现有机制）

### 3.2 默认排序（建议）

在 `defaultActionItems` 中插入新项，**紧挨登录助手之后**（或之前，见决策 D1）：

```
查找 · 下载 · 登录助手 · 【互联】 · 验证码助手 · RSS · …
```

推荐：**登录助手之后**。理由：先「填表钥匙」，再「手机链路」，阅读顺序符合「登录需要手机」的心智；且不挤占查找/下载高频位。

| 决策 | 选项 | 建议 |
|------|------|------|
| D1 默认位置 | A. 登录助手后 · B. 登录助手前 · C. 最左侧 | **A** |
| D2 升级后旧用户顺序 | 仅当 prefs 无该 id 时追加到默认相对位置 | **是**（与 findInPage 同类迁移） |

### 3.3 图标与状态圆点

**图标（SF Symbol，二选一，建议拍板 D3）：**

| 候选 | Symbol | 说明 |
|------|--------|------|
| **推荐** | `link` 或 `link.circle` | 与 Android 链路语义一致，不易与「钥匙登录」混淆 |
| 备选 | `iphone.and.arrow.forward` / `cable.connector` | 更具「手机」感，但系统版本差异更大 |

默认 tint：`secondaryLabelColor`（与其它工具一致）。  
**不要**用 accent 表示「已连接」——accent 在本产品里表示「本页有可操作事项」（登录匹配、下载忙碌、RSS 发现）。连接态**只靠圆点颜色**。

**状态圆点：**

- 位置：按钮右上角，约 8×8 pt（视觉略小于 Android 10dp，适配 28pt 按钮）  
- 描边：1pt，颜色跟工具栏行背景（浅色白 / 深色对应 tab 填充），避免融进图标  
- 颜色（与 Android `LinkConnectionState` 对齐）：

| 状态 | 圆点 | Tooltip 后缀 |
|------|------|----------------|
| 已连接 | `#34C759` / `systemGreenColor` | 已连接到手机 |
| 等待中 / 广播中 | `#FF9F0A` / `systemOrangeColor` | 等待手机连接… |
| 未连接 / 已停止 | `#8E8E93` / `tertiaryLabelColor` | 未连接 |

未连接时图标可略降透明度（约 0.7），与 Android 一致。

### 3.4 交互

| 操作 | 行为 |
|------|------|
| 单击 | 打开 `BrowserLoginAssistSettingsWindowController`，并调用 `revealCompanionSection`（新建）：窗口 key + 滚到状态卡片 |
| 拖拽 | 调整 ActionGroup 顺序（现有） |
| 右键 | V1 可不做；V1.1 可选「复制主机地址 / 刷新配对码」 |
| 长按 | macOS 无长按惯例；不做 |

菜单增强（可选，同 PR 或紧随）：

- **文件 → 互联与配对…**（或挂在登录助手菜单旁）→ 与单击同路径  
- 快捷键：V1 **不占用**；避免与 ⌘⇧L（一键登录）冲突

### 3.5 Accessibility

- `toolTip` / accessibility label：`互联 · {状态标题}`  
- 圆点为装饰，不单独暴露 accessibility 元素（状态已在 label 中）

---

## 4. 状态模型（Mac ↔ 用户文案）

### 4.1 底层状态（已有）

`CompanionChannel.state`：

| 枚举 | 含义 |
|------|------|
| `Stopped` | 通道未启动 |
| `Advertising` | Bonjour / 端口已开，等待手机 |
| `Connected` | 手机已 hello_ok，会话保持 |

另有：`usingTemporaryPort`、`statusText`、配对设备数等，供卡片副标题使用。

### 4.2 映射到三态 UI（与 Android 同文案族）

| UI 三态 | Mac 条件 | 标题（卡片 / Tooltip） |
|---------|----------|------------------------|
| **CONNECTED** | `state == Connected` | 已连接到手机 |
| **CONNECTING**（等待中） | `state == Advertising` | 等待手机连接… |
| **DISCONNECTED** | `state == Stopped`（或启动失败） | 未连接 |

说明：Android 的「连接中」是手机正在连 Mac；Mac 的「等待中」是在广播。用户侧都显示**琥珀点 + 进行中文案**，避免两端各说各话。

### 4.3 副标题（卡片 detail）

优先级建议：

1. 已连接：`手机在线 · 验证码可自动推送`（若有多台曾配对，附加「另有 N 台曾配对」）  
2. 临时端口：沿用现有「固定端口被占用…」文案  
3. 安全码模式未设码 / 已设码：沿用 `refreshCompanionUI` 现有 hint  
4. 临时配对码模式：`等待手机连接。可复制配对码给 Companion。`  
5. 兜底：`CompanionChannel.statusText`

### 4.4 刷新时机

| 事件 | 动作 |
|------|------|
| `CompanionChannelStateDidChangeNotification` | 更新所有窗口 ActionGroup 圆点 + 若设置窗打开则刷新卡片 |
| 设置窗 `refreshCompanionUI` | 与现有一致，并驱动卡片标题/按钮 |
| 窗口新建 / ActionGroup rebuild | 读当前 `CompanionChannel` 状态初始化圆点 |

实现注意：多窗口时每个 `BrowserWindowController` 的 ActionGroup 都要订阅或经中枢刷新，避免只亮一个窗口。

---

## 5. 设置页美化（与 Android 同构）

### 5.1 信息架构（登录助手窗口内）

现有窗口已混合「Recipe 管理 + Companion」。V1 **不拆窗**，但把 Companion 区改成与 Android 配对页同构的卡片流，并保证从工具栏进入时**首先看到状态卡片**：

```
┌─────────────────────────────────────────────────────────┐
│  登录助手                                      ✕        │  ← 可保留现有窗标题；或副标题「含互联配对」
├─────────────────────────────────────────────────────────┤
│  ┌─ 互联状态 ─────────────────────────────────────┐     │
│  │  (图标)  已连接到手机          [绿点]           │     │
│  │          手机在线 · 验证码可自动推送             │     │
│  │          主机：192.168.x.x:port（点按复制）     │     │
│  │          [ 刷新配对码 / 视模式显示主操作 ]       │     │
│  └────────────────────────────────────────────────┘     │
│  ┌─ 连接方式 ─────────────────────────────────────┐     │
│  │  临时配对码 | 固定安全码                         │     │
│  │  大号配对码 / 安全码输入（SBTextField）         │     │
│  │  注销已配对设备 …                               │     │
│  └────────────────────────────────────────────────┘     │
│  ┌─ 通知镜像 ─────────────────────────────────────┐     │
│  │  （现有开关，卡片化）                           │     │
│  └────────────────────────────────────────────────┘     │
│  ┌─ 局域网同步 ───────────────────────────────────┐     │
│  │  （现有开关，卡片化）                           │     │
│  └────────────────────────────────────────────────┘     │
│  … Recipe 列表等其它原有区块 …                          │
└─────────────────────────────────────────────────────────┘
```

与 Android 对齐要点：

1. **状态卡片置顶**（互联相关的第一视觉）  
2. **分区卡片**：白底 / 系统 `controlBackgroundColor`、圆角约 10–12pt、轻分隔，避免长表单一根线劈到底  
3. **连接方式 / 通知 / 同步** 与 Android 分区语义对应  
4. 输入框继续走 **SBKit**（`SBTextField` / `SBSecureTextField`）

### 5.2 `revealCompanionSection` 行为

从工具栏点击进入时：

1. `showWindow:` / 使窗口 key  
2. 若通道 `Stopped`，保持现有 `refreshCompanionUI` 内自动 `start` 行为  
3. 滚动视图 `scrollPoint` / `scrollToView:` 到状态卡片，并短暂 `highlight`（可选：1 次边框闪烁或 `NSView` 强调，避免打扰）

### 5.3 与「文件 → 登录助手…」关系

| 入口 | 落地 |
|------|------|
| 工具栏「互联」 | 打开设置 + **reveal 互联卡片** |
| 文件 → 登录助手… | 打开设置，**默认滚到顶部**（若顶部已是互联卡，则自然可见）；不强制改行为 |
| 登录助手按钮右键 → 管理配置 | 保持现有（Recipe 导向） |

可选后续：登录助手菜单增加「互联与配对」子项，与工具栏同路径。

---

## 6. 视觉规范（Mac chrome）

| 元素 | 规范 |
|------|------|
| 工具栏按钮 | 与 ActionGroup 其它键一致；仅圆点表达连接态 |
| 圆点颜色 | 绿 / 橙 / 灰，见 §3.3；尊重 Dark Mode（用系统色优先） |
| 状态卡片标题 | 17–18pt semibold；与现有 `companionConnectionLabel` 同级 |
| 副标题 | 12–13pt `secondaryLabelColor` |
| 主机链接 | 等宽 + `linkColor`，点击复制（已有） |
| 卡片背景 | Light：白；Dark：raised 材质或 white 8–12% |
| 页面底 | 与现有设置窗一致，避免另起一套「网页风」 |

禁止：

- 用紫色渐变、大面积 glow、胶囊堆叠（与产品其它 chrome 不一致）  
- 在工具栏按钮上叠文字徽章（圆点足够）

---

## 7. 实现要点（供开发计划拆分）

### 7.1 建议文件触点

| 模块 | 路径 / 职责 |
|------|-------------|
| Action 目录 | `BrowserAddressBarActionGroup.m`：新增 `companionLink` item、`companionLinkButton`、圆点 subview |
| 状态映射 | 新建小工具类或 category：`CompanionLinkUIState`（三态 ← `CompanionChannel`），避免 UI 散落 if |
| 刷新 | `LoginAssistController` 或 `BrowserWindowController` 监听 channel 通知，调用 ActionGroup `updateCompanionLinkAppearance` |
| 设置窗 | `BrowserLoginAssistSettingsWindowController.m`：重构 Companion 区布局 + `revealCompanionSection` |
| 符号 | SF Symbol；若需自定义矢量，再补 Asset（优先系统符号） |

### 7.2 顺序持久化

`BrowserAddressBarActionOrder`（UserDefaults）：新 id `companionLink` 在已有数组中缺失时，插入到 `loginAssist` 之后；不要把用户自定义顺序整体重置。

### 7.3 与下载角标的层级

下载按钮已有红色进度角标。互联圆点同为角标位，互不冲突（不同按钮）。绘制时注意 `wantsLayer` / 坐标系与现有 download badge 一致，避免 Retina 糊边。

### 7.4 测试清单（验收）

- [ ] 冷启动：通道 Advertising → 琥珀点；手机连上 → 绿点；断开 → 灰或重回琥珀  
- [ ] 多窗口：所有窗口圆点同步  
- [ ] 点击互联 → 设置窗出现且状态卡片在可视区  
- [ ] 拖拽排序 / 溢出菜单仍含「互联」  
- [ ] Dark Mode 圆点描边可见  
- [ ] 登录助手钥匙按钮外观逻辑**不变**（仍只反映 Recipe/表单）  
- [ ] 未配对时填码失败提示仍可用  

---

## 8. 风险与决策待确认

| ID | 问题 | 建议默认 |
|----|------|----------|
| D1 | 默认排在登录助手前还是后 | **后** |
| D3 | SF Symbol 用 `link` 还是带手机符号 | **`link`**（跨版本稳、与 Android 语义近） |
| D4 | 是否从登录助手窗口拆出独立「互联」窗 | **V1 不拆**；只做 reveal + 卡片美化 |
| D5 | Advertising 是否显示琥珀（有人觉得「未连上就该灰色」） | **显示琥珀**（「正在等手机」≠「功能关闭」） |
| D6 | 工具栏点击是否只 reveal、不自动 `start` | **保持现有 refresh 内 auto-start**（减少「点了还是停着」） |

---

## 9. 里程碑建议

| 阶段 | 内容 | 预估 |
|------|------|------|
| **ML-1** | ActionGroup 按钮 + 圆点 + 状态订阅 + 点击打开设置 | 0.5–1 日 |
| **ML-2** | `revealCompanionSection` + 状态卡片置顶重构 | 1–1.5 日 |
| **ML-3** | 连接方式 / 通知 / 同步分区卡片化 + Dark Mode 打磨 | 0.5–1 日 |
| **ML-4** | 多窗口 / 顺序迁移 / 验收手测 | 0.5 日 |

合计约 **2.5–4 人日**（不含大范围 Recipe UI 重排）。

---

## 10. 文档与代码索引

| 资源 | 路径 |
|------|------|
| ActionGroup | `SimpleBrowser/AddressBar/BrowserAddressBarActionGroup.m` |
| 通道状态 | `SimpleBrowser/LoginAssist/Companion/CompanionChannel.h/.m` |
| 设置窗 Companion UI | `SimpleBrowser/LoginAssist/BrowserLoginAssistSettingsWindowController.m` |
| Android 对照实现 | `companion/android/.../BrowserActivity.kt` · `LinkConnectionState.kt` · `activity_main.xml` |
| Android 底栏设计背景 | 本对话方案 + `android-browser-development-plan.md` §3.10 |

---

## 11. 一句话结论

在 Mac 地址栏右侧 ActionGroup 增加独立的「互联」键（链路图标 + 绿/琥珀/灰圆点），状态映射自 `CompanionChannel`，点击打开登录助手设置并定位到美化后的顶部状态卡片——与 Android 底栏入口**同构**，且与「登录助手钥匙」职责分离。

**请确认 §8 决策 D1/D3/D4/D5 后即可开工实现。**
