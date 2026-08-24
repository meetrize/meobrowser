# 重页 UI 响应性 — 设计方案

> 目标：打开视频直播等极占 CPU/GPU 的页面时，**其它标签切换、标签栏点击、Chrome 交互仍保持可点**；避免单击被误判为拖拽。  
> 状态：**HP-0～HP-3 已落地（代码）**；手测见开发计划验收项。开发计划见 [heavy-page-ui-responsiveness-development-plan.md](heavy-page-ui-responsiveness-development-plan.md)。  
> 关联：[navigation-hang-remediation-design.md](navigation-hang-remediation-design.md) · [multi-tab-design.md](multi-tab-design.md) · [multi-window-design.md](multi-window-design.md) · [tab-drag-ghost-design.md](tab-drag-ghost-design.md) · [afk-mode-design.md](afk-mode-design.md)  
> Cursor 计划：[.cursor/plans/heavy-page-ui-responsiveness.plan.md](../../.cursor/plans/heavy-page-ui-responsiveness.plan.md)

---

## 1. 问题定义

### 1.1 用户体感

| 场景 | 典型表现 |
|------|----------|
| 打开直播 / 重度视频页 | 整窗变「钝」；点其它标签有明显延迟 |
| 同上，点标签栏 | 单击被识别为拖拽排序 |
| 切走后仍开着直播标签 | CPU/GPU 持续高占用，其它标签也受拖累 |

### 1.2 根因分层（与导航卡死治理对齐）

MeoBrowser = **AppKit UI 进程 + 系统 WebKit（Network / WebContent / GPU）**。页面已在独立内容进程；**应用层不自研多进程引擎**。

| 类型 | 含义 | 本方案重点 |
|------|------|------------|
| **R1. 后台重页仍全速跑** | 切标签只 detach，媒体/JS 继续 | **失活 pause/mute；媒体标签加速休眠** |
| **R2. 切页同步过重** | `mouseDown` → 同步完整 `refreshTabsUI` | **关键路径瘦身；非关键延后** |
| **R3. 手势阈值过低** | 4pt + 模态 tracking，主线程一卡易误拖 | **提高阈值 + 时间门控** |
| **R4. UI 回调风暴** | progress/title/script 打主线程 | **合并/节流** |
| **R5. 进程粘连（次要）** | 默认 pool + ProcessSwap 关闭 | **本迭代不做默认拆 pool**（见「明确不做」） |

> **产品承诺**：前台允许重页吃资源；**非前台标签不得持续播流抢 CPU/GPU**；标签栏单击在负载下仍应稳定选中而非拖拽。

### 1.3 明确不做

| 不做 | 理由 |
|------|------|
| 自研 Chromium 式多进程 / 换内核 | 与原生 WebKit 定位冲突 |
| 默认每标签独立 `WKProcessPool` | 拆散 Cookie/登录；与多窗共享 `defaultDataStore` 冲突 |
| 依赖私有 SPI 精细 throttle WebContent | 脆弱、升级易碎 |
| 失活后自动 `play()` 恢复直播 | 尊重用户；站点可自行恢复或由用户点击 |
| AFK 模式顺带卸载 WebView | AFK 仅视觉隐藏；资源治理走本方案 |

---

## 2. 现状基线

| 能力 | 现状 |
|------|------|
| 引擎 | `WKWebView` / `BrowserWebView` |
| Process pool | 未自定义；共享 `defaultDataStore` |
| ProcessSwap | 私有 API 关闭（OAuth / opener） |
| 后台标签 | 离屏存活；**无 pause 媒体** |
| 休眠 | 闲置 10 min 或窗内 8 / 全局 12 预算 |
| 切标签 | `BrowserTabItemView mouseDown` → `onSelect` → 同步 `refreshTabsUI` |
| 拖拽 | `kReorderDragThreshold = 4.0`；无时间门控 |
| 缩略图 | 切走前 `takeSnapshot`（异步完成，但启动仍耗 GPU） |

---

## 3. 方案总览

```text
失活标签
  ├─ closeAllMediaPresentations（已有全屏）
  ├─ JS pause + mute video/audio     ← HP-1
  ├─ 标记 mediaHeavy（若发现媒体）   ← HP-1
  └─ 跳过昂贵 takeSnapshot           ← HP-1

选中切换（refreshTabsUI）
  ├─ 同步：detach / wake / attach / 最小 chrome
  └─ 异步：overview、证书条、透明样式等 ← HP-0

标签手势
  ├─ 距离阈值 ↑（约 10pt）
  └─ 按下后 ≥150ms 才允许进入 reorder ← HP-0

休眠
  └─ mediaHeavy：闲置约 90s 可 hibernate ← HP-2

主线程
  └─ estimatedProgress 等合并刷新       ← HP-3
```

---

## 4. 详细设计

### 4.1 失活媒体策略（HP-1）

**触发点**：`detachWebViewIfNeeded:` 之前或之内，对即将离屏的存活 WebView。

**行为**：

1. 已有：全屏态 `closeAllMediaPresentations`
2. 新增：`evaluateJavaScript` 暂停并静音所有 `video`/`audio`（含影子树尽力而为；失败忽略）
3. 若暂停到至少一个元素（或脚本返回 count>0）→ `tab.mediaHeavy = YES`
4. **不**在重新选中时自动 `play()`

**实现归属**：`BrowserBackgroundMediaController`（或等价小工具类）+ `BrowserTab.mediaHeavy`。

### 4.2 切走跳过昂贵快照（HP-1）

| 条件 | 行为 |
|------|------|
| `tab.mediaHeavy == YES` 或暂停检测到媒体 | **不**调用 `takeSnapshot` |
| 其它普通页 | 保持现有「detach 前异步 capture」 |

直播帧快照对 GPU 极贵，且切走后缩略图可用上一帧或占位。

### 4.3 `refreshTabsUI` 关键路径（HP-0）

**同步（必须）**：

- 对非选中：pause 媒体（fire-and-forget）→ 条件快照 → detach
- 选中：`wakeFromHibernationIfNeeded` → `attachWebViewForTab:` → `loadPending…`
- launchpad 显隐（不强制 `reloadShortcuts`）
- `updateTabStripDisplay` / 导航按钮最小态 / progress KVO 挂接
- `endAddressBarEditingIfNeeded`

**延后到下一 runloop（`dispatch_async` main）**：

- `launchpadView reloadShortcuts`
- tab overview `reloadFromTabController`
- 证书警告 / 导航错误可见性同步
- `syncTransparentPageStyleForSelection`
- `updateTabOverviewButtonAppearance`（若非关键）

须保证：延后块校验「仍是同一 selectedTab」，避免快速连切错乱。

### 4.4 标签拖拽门控（HP-0）

| 项 | 旧值 | 新值 |
|----|------|------|
| 距离阈值 | 4 pt | **10 pt** |
| 时间门控 | 无 | 自 `mouseDown` 起 **≥150 ms** 且超距离才进入 reorder |

选中仍可在 `mouseDown` 触发（保持现交互），但 **reorder 不得在短按抖动下启动**。

### 4.5 媒体标签加速休眠（HP-2）

| 标签 | 闲置阈值 |
|------|----------|
| 普通 | 600 s（不变） |
| `mediaHeavy` 且非 selected、非 `resistsHibernation`、非风险保护 host | **90 s** |

预算淘汰时：同等条件下 **优先淘汰 `mediaHeavy`**（rank 更低）。

休眠后清除 `mediaHeavy`（WebView 已毁）。再次打开直播并切走会重新标记。

### 4.6 主线程节流（HP-3）

- `estimatedProgress` KVO：合并到约 **50～100 ms** 或进度差 ≥0.02 再刷 UI
- 后台标签的 `titleDidChangeHandler` → `updateTabStripDisplay`：若非选中，可 coalesce（可选，避免过度）

首版以 progress 合并为主；script handler 大改不动（登录助手等另案）。

### 4.7 设置（可选，HP-3 末）

| Key | 默认 | 说明 |
|-----|------|------|
| `backgroundPauseMedia` | YES | 失活暂停媒体 |
| `mediaTabFastHibernate` | YES | mediaHeavy 90s 休眠 |

无设置 UI 时用 UserDefaults 默认即可；设置窗开关可后置。

---

## 5. 进程与隔离边界

与 [navigation-hang-remediation-design.md](navigation-hang-remediation-design.md) 一致：

- **硬隔离手段**仍是销毁 WebView（hibernate / hard recover）
- **不**默认引入 per-tab `WKProcessPool`
- NH-5 风险 pool 仍为可选扩展，**不在本方案必做范围**

---

## 6. 主要改动文件

| 文件 | 改动 |
|------|------|
| `Tabs/BrowserTabItemView.m` | 拖拽阈值 + 时间门控 |
| `Tabs/BrowserTab.h/.m` | `mediaHeavy` |
| `Tabs/BrowserTabController.m` | 媒体加速休眠；预算优先淘汰 |
| `BrowserWindowController.m` | `refreshTabsUI` 拆分；detach 前 pause；条件快照；progress 节流 |
| 新建 `Tabs/BrowserBackgroundMediaController.*`（或 `Browser/`） | pause/mute JS |
| `Makefile` | 编译新文件 |
| 本文档 + development-plan + Cursor plan | 索引与阶段 |

---

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 切回直播需用户再点播放 | 产品接受；可日后加「恢复后台媒体」开关 |
| pause JS 对自定义播放器无效 | 尽力而为；加速休眠兜底 |
| 延后 chrome 导致短暂徽章错位 | 仅延后非关键；关键导航态同步 |
| 时间门控影响快速拖拽排序 | 150ms 仍短；真拖拽通常更长按 |
| 保护 host 上的直播不休眠 | 仍 pause；只是不 90s 销毁 |

---

## 8. 验收要点

- [ ] 开直播页 → 切到其它标签：CPU/GPU 明显下降；切标签体感接近普通页
- [ ] 主线程繁忙时单击标签：稳定选中，**不**误进排序拖影
- [ ] 真拖拽排序仍可用（按住移动 >10pt 且 >150ms）
- [ ] mediaHeavy 标签失活约 90s 后可进入休眠（非保护、非 resists）
- [ ] 切回休眠标签：正常恢复 URL；**不**自动播放
- [ ] `make browser` 通过
