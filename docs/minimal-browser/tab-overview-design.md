# 标签概览（Tab Overview）— UI 与交互设计方案

> 目标：在地址栏右侧提供「概览」入口，将**当前窗口**已打开标签以小窗口宫格展示，支持快速切换与整理。  
> 状态：**设计定稿，待实现**  
> 关联：[multi-tab-design.md](multi-tab-design.md)、[tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md)、[multi-window-design.md](multi-window-design.md)、[favicon-fetch-cache-design.md](favicon-fetch-cache-design.md)、[new-tab-launchpad-design.md](new-tab-launchpad-design.md)、[android-browser-chrome-ui-design.md](android-browser-chrome-ui-design.md)

---

## 1. 方案定位

### 1.1 做什么

| 能力 | 说明 |
|------|------|
| **标签概览 overlay** | 覆盖内容区，以宫格卡片展示本窗全部标签 |
| **入口** | 地址栏右侧动作组「概览」按钮（`square.grid.2x2`） |
| **切换 / 关闭** | 单击卡片进入；悬停 ✕ 关闭且留在概览内继续整理 |
| **搜索过滤** | 按标题 / URL 过滤卡片（`SBTextField`） |
| **缩略图** | 缓存优先；无图时用 favicon / 首字母占位（不批量唤醒休眠标签） |

### 1.2 不做什么（首版）

- 不做跨窗口统一「概览墙」（每窗独立 `BrowserTabController`）
- 不做标签分组（roadmap 另项）
- 不做打开概览时强制 `wake` 全部休眠标签
- 不做卡片拖拽排序（标签条拖拽已存在；可二期）
- 不做磁盘持久化缩略图（会话恢复后用占位即可）
- 不与 NTP Launchpad 共用同一套网格组件（语义不同，避免耦合）
- 不做 Safari 式整行滑动关闭手势

### 1.3 设计原则

| # | 原则 |
|---|------|
| 1 | **当前窗口范围**：概览只反映本窗标签集，与现有多窗模型一致 |
| 2 | **临时工作面**：选完即关；不是独立窗口，也不是新标签页 |
| 3 | **Chrome 可并存**：标签条与工具栏保持可见，便于连续管理 |
| 4 | **内存优先**：缩略图策略服从 8/12 WebView 存活预算，禁止批量唤醒 |
| 5 | **占位可读**：无截图时仍能靠 favicon + 标题辨认标签 |
| 6 | **中文产品语气**：按钮 tip、顶栏标题、空状态均为中文 |
| 7 | **输入规范**：搜索框使用 `SBTextField` |

---

## 2. 与现有架构的关系

### 2.1 Chrome 分层（概览插入点）

```text
NSTitlebarAccessory（标签条 BrowserTabStripView）     ← 保持可见
contentLayoutGuide 以下
  └── 导航工具栏 + 地址栏行（含 ActionGroup）         ← 保持可见；概览按钮高亮
  └── contentRowStack
        ├── contentContainer
        │     ├── WKWebView / Launchpad / 进度条 / …  ← 被 overlay 盖住
        │     └── BrowserTabOverviewController.view   ← 新增全覆盖层
        ├── 通知侧栏
        └── 助手侧栏
```

### 2.2 关键现状约束

| 约束 | 对概览的影响 |
|------|----------------|
| 仅选中标签的 WebView 挂在 `contentContainer` | 非选中页不能假定随时可截图 |
| 休眠只存 `restorableURL`，不存截图 | 休眠卡必须有占位策略 |
| 窗内最多 8、全局最多 12 存活 WebView | 打开概览时禁止批量 `wake` |
| 标签条无 favicon 槽位 | 卡片自行接 `BrowserFaviconService` |
| 动作区默认宽约 184pt、易溢出 | 新按钮走 ActionGroup 目录；可排序/进溢出菜单 |
| 内容区已有查找条等 overlay | 打开概览时建议 dismiss 查找条；明确 z-order |

### 2.3 可复用资产

| 资产 | 用途 |
|------|------|
| `BrowserTabController.tabs` / `selectedTab` | 数据源与选中同步 |
| `BrowserTab.displayTitle` / `currentOrRestorableURL` / `pinned` | 卡片文案与角标 |
| `takeSnapshotWithConfiguration:`（见 CaptchaCaptureService） | 存活页截图 |
| `BrowserFaviconService` | 占位 favicon |
| `BrowserAddressBarActionGroup` | 入口按钮 |
| `BrowserFindBarController` 装入方式 | overlay 生命周期参考 |

---

## 3. 布局

### 3.1 整体线框

```text
┌─ 标签条（可见，可点选/关闭，与概览双向同步）──────────────┐
├─ ◀ ▶ ↻ │ 地址栏 │ … [⊞ 概览] … ─────────────────────────┤
│  ┌─ 概览顶栏 ──────────────────────────────────────────┐ │
│  │  标签概览 · N 个        [🔍 搜索标签]   [＋ 新标签] [✕] │ │
│  ├─────────────────────────────────────────────────────┤ │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐            │ │
│  │  │ 预览 │  │ 预览 │  │ 预览 │  │ 预览 │  …         │ │
│  │  │      │  │ ●选中│  │      │  │休眠  │            │ │
│  │  ├──────┤  ├──────┤  ├──────┤  ├──────┤            │ │
│  │  │🌐标题 │  │🌐标题 │  │🌐标题 │  │🌐标题 │            │ │
│  │  └──────┘  └──────┘  └──────┘  └──────┘            │ │
│  │                    （可垂直滚动）                     │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 3.2 概览顶栏

| 元素 | 说明 |
|------|------|
| 标题 | `标签概览` + 当前过滤前总数 `· N 个` |
| 搜索 | `SBTextField`，placeholder「搜索标签」；匹配标题或 URL（含 `restorableURL`） |
| 新标签 | `＋` → `addTab`（NTP）并**保持概览打开**，新卡片出现在末尾 |
| 关闭 | `✕` → 关闭 overlay，保持当前选中标签 |

无搜索匹配时：网格区居中文案「无匹配标签」。

### 3.3 卡片结构

自上而下：

1. **预览区**（约 **16:10**）：缩略图或占位
2. **底栏**：favicon（或首字母）+ 标题单行截断；悬停显示关闭按钮 ✕
3. **选中态**：`controlAccentColor` 描边 **2 pt** + 轻微阴影
4. **固定标签**：预览区左上角小 pin 角标
5. **休眠标签**：预览略降透明度，或右下角「休眠」微标（不打断操作）

NTP 卡片：不截 WebView，使用与 Launchpad 气质接近的占位（标题「新标签页」）。

### 3.4 宫格列数

| 内容区宽度 | 列数 | 卡片宽度约 |
|------------|------|------------|
| &lt; 720 | 2 | 自适应 |
| 720–1100 | 3 | ~220–280 |
| 1100–1600 | 4 | ~240–300 |
| &gt; 1600 | 5 | 上限约 **320** |

| Token | 建议值 |
|-------|--------|
| 卡片间距 | 16–20 pt |
| 外边距 | 24 pt |
| 圆角 | 与现有标签/控件一致（约 8–10 pt） |
| 顺序 | 与标签条一致；固定标签在前 |

垂直方向：`NSScrollView` 滚动；窗口缩小时列数可降，卡片重排。

### 3.5 视觉

| 项 | 浅色 | 深色 |
|----|------|------|
| 遮罩 / 面板底 | 近 `BrowserTabActiveFillColor` 不透明或微透明白 | 近 toolbar 深底 |
| 卡片底 | 白 / 活动标签填充色 | `white 0.22` 一带 |
| 图标 tint | `secondaryLabelColor` | 同 |
| 强调 | `controlAccentColor` | 同 |

避免另起一套皮肤；与标签条、工具栏同一色系。

---

## 4. 入口与退出

### 4.1 主入口（定稿）

在 `BrowserAddressBarActionGroup` 的 `defaultActionItems` 增加：

| 字段 | 值 |
|------|------|
| id | `tabOverview` |
| SF Symbol | `square.grid.2x2`（打开态可用 `.fill` 或背景高亮） |
| tip | `标签概览` |
| 尺寸 | **28×28**，与其它动作按钮一致 |
| 默认位置 | 动作组靠前（易见）；用户仍可拖拽排序 / 隐藏 |

**角标（P1）**：标签数 ≥ 2 时在图标右上角显示数字（风格对齐下载按钮角标）。

### 4.2 辅助入口（建议一并支持）

| 入口 | 行为 |
|------|------|
| 快捷键 | 建议 `⌘⇧\` 或 `⌃⇧Tab`（实现前再定一档，避免与系统冲突） |
| 菜单 | 「标签页」或「窗口」→「显示标签概览」 |
| 标签条溢出 ▾ | 菜单底部「显示全部标签…」（窄窗友好） |

### 4.3 退出与切换

| 操作 | 结果 |
|------|------|
| 再点「概览」按钮 | 关闭 overlay |
| 顶栏 ✕ / Esc | 关闭，**保持当前选中** |
| 单击某卡片 | `selectTab` → 关闭概览 → 聚焦内容区 |
| 点击标签条某标签 | 同步选中；**保持概览打开**（便于连续清理） |
| 点击卡片外空白 | **关闭**概览（可选；若误触反馈多可改为仅 Esc / 按钮） |

打开概览时：dismiss 页内查找条（若有）；证书警告条可保留在下层或一并遮住（实现时取「遮罩盖住即可」）。

---

## 5. 交互细节

### 5.1 点击与关闭

- **单击卡片** → 选中并退出概览  
- **悬停** → 显示 ✕；点 ✕ → 关闭该标签，卡片收拢，**不退出**概览  
- **关闭当前选中** → 自动选中相邻标签，概览选中框跟随  
- **关至逻辑下限** → 与现有一致（至少保留 1 个标签 / NTP），并关闭概览  

### 5.2 右键菜单（对齐标签条语义）

关闭 · 关闭右侧 · 关闭其他 · 固定/取消固定 ·（可选）复制链接  

实现上复用 `BrowserTabStripView` / WindowController 已有菜单构建逻辑，避免两套语义。

### 5.3 键盘（P1）

| 键 | 行为 |
|----|------|
| ← → ↑ ↓ | 宫格焦点移动 |
| Return | 打开焦点卡片（同单击） |
| Delete / ⌘W | 关闭焦点卡片 |
| Esc | 退出概览 |
| 可打印字符 | 聚焦搜索框并开始过滤 |

### 5.4 拖拽

- **P0**：不做卡片拖拽  
- **P2**：宫格内拖拽 = 调整 `tabs` 顺序，与标签条实时同步  

### 5.5 动效（克制，2–3 个）

| 动效 | 建议 |
|------|------|
| 进入 | 遮罩 fade in + 内容轻微 scale（约 0.96→1），~180 ms |
| 选中打开 | 被点卡片轻微放大后与 overlay 一同淡出 |
| 关闭卡片 | 透明度/宽度收拢，其余卡片补位 |

无障碍「减少动态效果」开启时：直接显隐，无缩放。量级对齐查找条 / 侧栏，不做视差墙。

### 5.6 与标签条同步

| 事件 | 概览行为 |
|------|----------|
| 条内选中变化 | 更新卡片选中描边；必要时滚动到可见 |
| 条内关闭 / 新增 / 固定 / 重排 | 重建或增量更新网格 |
| 概览内关闭 / 新标签 | 驱动 `BrowserTabController`，条内立即反映 |

---

## 6. 缩略图策略

### 6.1 优先级

```text
1. 内存缓存：tabID → 近期 snapshot（LRU）
2. 当前存活 WebView：可见区 takeSnapshot（异步）
3. 占位：favicon 居中 + 标题/域名 + 柔和底色
4. NTP：专用占位，不截 WebView
```

### 6.2 推荐策略（定稿）

| 时机 | 做法 |
|------|------|
| **打开概览** | 已存活 WebView 异步补图；休眠 / 无缓存用占位；**不批量 wake** |
| **离开某标签时（后台维护）** | 对即将 detach 的页做一次低分辨率 snapshot，写入内存缓存 |
| **缓存上限** | 建议最多约 **20** 张；最长边约 **480** pt；LRU 淘汰 |
| **磁盘** | 首版不做 |
| **概览打开期间** | 当前选中页 `didFinishNavigation` 后可更新对应卡片 |

这样首屏几乎零延迟，预览随日常切换逐渐变清晰，且不触碰休眠预算。

### 6.3 明确禁止

- 打开概览时对所有休眠标签 `wakeFromHibernationIfNeeded` 再截图  
- 为截图把非选中 WebView 长期同时挂到视图树  

---

## 7. 架构建议

### 7.1 组件划分

| 类 | 职责 |
|----|------|
| `BrowserTabOverviewController` | 显示/隐藏、数据绑定、键盘、与 WindowController 通信 |
| `BrowserTabOverviewView` | 顶栏 + 滚动宫格容器 |
| `BrowserTabOverviewCardView` | 单卡：预览、标题、favicon、选中/pin/休眠态、关闭 |
| `BrowserTabThumbnailCache` | `tabID → NSImage` LRU；供切标签时写入、概览读取 |

挂载：作为 `contentContainer` 的子视图，约束贴满；`hidden` 或从父视图移除表示关闭。

### 7.2 与 WindowController 的接口（示意）

```objc
// BrowserWindowController
- (void)toggleTabOverview:(id)sender;
- (void)showTabOverview;
- (void)hideTabOverview;
- (BOOL)isTabOverviewVisible;
```

动作组接线：对 `tabOverview` 项设置 `target/action` → `toggleTabOverview:`。

### 7.3 数据流

```text
BrowserTabController.tabs
        │
        ▼
BrowserTabOverviewController  ←→  ThumbnailCache
        │
        ├── 选中 / 关闭 / 新标签  → TabController API
        └── UI 刷新 ← tabControllerDidChange / 条内操作
```

### 7.4 技术选型

| 项目 | 选择 | 理由 |
|------|------|------|
| 网格 | `NSCollectionView` 或手写 `NSStackView`+约束 | 列数随宽变化；卡片量通常 &lt; 50，两种均可；偏好 CollectionView 便于补位动画 |
| 截图 | `WKSnapshotConfiguration` + 异步主线程设图 | 已有验证码截图先例 |
| Favicon | `BrowserFaviconService` | 与 Launchpad / 补全一致 |
| 搜索 | `SBTextField` | 全局输入规范 |

---

## 8. 分阶段交付

| 阶段 | 范围 | 验收重心 |
|------|------|----------|
| **TO-0（P0）** | ActionGroup 按钮 + overlay 宫格 + 标题/favicon 占位 + 单击切换/悬停关闭 + Esc/再点退出 + 与标签条选中同步 | 能整理多标签，不卡顿 |
| **TO-1（P1）** | 切标签时写入 ThumbnailCache；打开概览异步补图；搜索过滤；键盘导航；按钮角标数字 | 真正「小窗口」观感 |
| **TO-2（P2）** | 右键菜单对齐标签条；卡片拖拽排序；菜单/快捷键/溢出菜单入口；减少动态效果适配 | 打磨完整 |

开发计划可另文：`tab-overview-development-plan.md`（实现时再拆任务与文件清单）。

---

## 9. 验收标准

1. 点击地址栏右侧「概览」后，当前窗全部标签以宫格展示，顺序与标签条一致（含固定标签）。  
2. 单击卡片可切换到该标签并关闭概览；悬停 ✕ 可关闭标签且留在概览内。  
3. 休眠或无截图标签有清晰占位；打开概览不导致大量 WebView 被唤醒或内存尖峰。  
4. Esc / 再点「概览」可退出；退出后选中标签与工具栏状态正确。  
5. 标签条上的选中/关闭/新增与概览双向同步。  
6. 深色模式、窄窗（2 列）可用；搜索框为 `SBTextField`。  
7. 动作组支持将该按钮排序或隐藏；宽度不足时进入溢出菜单仍可打开概览。

---

## 10. 与其它文档的边界

| 文档 | 边界 |
|------|------|
| [new-tab-launchpad-design.md](new-tab-launchpad-design.md) | Launchpad = NTP 快捷方式；概览 = 已打开标签，勿混用组件 |
| [android-browser-chrome-ui-design.md](android-browser-chrome-ui-design.md) | Android 为标题列表面板；本方案为 Mac 宫格缩略图 |
| [tab-drag-ghost-design.md](tab-drag-ghost-design.md) | 拖拽影子仍是标签形态；概览不做完整窗口拖影 |
| [tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md) | 溢出 ▾ 可链到「显示全部标签…」作为辅助入口 |
| [professional-features-roadmap.md](professional-features-roadmap.md) | 分组 / 分屏等仍按 roadmap，不纳入本概览首版 |

---

## 11. 一句话定稿

地址栏右侧 `square.grid.2x2` 打开**当前窗口**内容区宫格 overlay；卡片采用「内存缩略图优先、否则 favicon 占位」；交互以「点选进入、悬停关闭、Esc 退出、标签条保持可见」为主，缩略图维护服从 WebView 休眠预算。
