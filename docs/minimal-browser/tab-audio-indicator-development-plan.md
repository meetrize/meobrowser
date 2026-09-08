# 标签出声指示 + 点击静音 — 开发计划

> 基于 [tab-audio-indicator-design.md](tab-audio-indicator-design.md)。  
> 状态：**TA-0～TA-3 代码已落地；TA-4 部分完成（溢出图标 + 右键静音 + 导航清 mute）；待手测验收**  
> 前置：标签条 LRU/favicon、`BrowserBackgroundMediaController`、heavy-page HP-0～3。

---

## 行为定稿

| ID | 定稿 |
|----|------|
| D1 | 策略 **A**：切标签默认**不** pause；后台可继续出声 |
| D2 | `isAudible` / `isPageMutedByUser` / `mediaHeavy` 三者解耦 |
| D3 | 静音 = 页级 mute，**不** pause；点击喇叭不选中标签 |
| D4 | 检测：公开 `requestMediaPlaybackState` 轮询 + 可选 `_isPlayingAudio` |
| D5 | 静音：可选 `_setPageMuted:`，降级 JS `video/audio.muted` |
| D6 | 主文档新导航清除用户 mute；hibernate 保留 mute 标志并在唤醒重应用 |
| D7 | Minimal：favicon 角标；Comfortable/Compact：favicon 后独立按钮 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| TA-0 | 文档与模型字段 | 0.5 天 | design/plan；`BrowserTab` 字段 |
| TA-1 | AudioController 检测 + 静音 | 2 天 | 轮询/SPI/JS；挂接生命周期 |
| TA-2 | 标签条 UI + sync | 2 天 | `BrowserTabItemView` 喇叭；strip sync |
| TA-3 | 失活策略修订 + 联调 | 1～1.5 天 | 取消默认 pause；mediaHeavy 由 audible 置位 |
| TA-4 | 打磨（溢出/菜单/导航清 mute） | 1 天 | P2 项与验收 |

**合计：约 6.5～7 个工作日**

---

## Phase TA-0：文档与模型

### 任务

- [x] **0.1** 撰写 `tab-audio-indicator-design.md`
- [x] **0.2** 撰写本开发计划
- [x] **0.3** `BrowserTab`：`isAudible` / `isPageMutedByUser`；`discardWebView` 清 `isAudible`
- [x] **0.4** 交叉引用 heavy-page（失活默认不再 pause）

### 自测

1. [x] 头文件可编译；旧行为暂不变直至 TA-3

---

## Phase TA-1：BrowserTabAudioController

### 任务

- [x] **1.1** 新建 `Tabs/BrowserTabAudioController.h/.m`
- [x] **1.2** 窗口级：`startMonitoringTabs:` / `stop`；主线程 timer ~0.75s
- [x] **1.3** L1：`requestMediaPlaybackStateWithCompletionHandler`（macOS 12+）
- [x] **1.4** L2：`_isPlayingAudio` runtime 探测
- [x] **1.5** `setPageMuted:forTab:`：SPI `_setPageMuted:` 或 JS 降级
- [x] **1.6** `toggleMuteForTab:`；变化回调 `audibleStateDidChangeHandler`
- [x] **1.7** Makefile 加入源文件；`BrowserWindowController` 创建/销毁时挂接
- [x] **1.8** 休眠唤醒后 `applyMuteStateIfNeeded`

### 自测

1. [ ] YouTube 播放 → `isAudible==YES`（待手测）
2. [ ] toggle mute → 无声；再 toggle → 有声（待手测）
3. [x] 无 WebView / NTP → 不崩溃（编译通过）

---

## Phase TA-2：标签条 UI

### 任务

- [x] **2.1** `BrowserTabItemView`：`showsAudioIndicator` / `audioMuted` / `onToggleMute`
- [x] **2.2** SF Symbol 按钮；`hitTest` 优先 audio
- [x] **2.3** Comfortable/Compact layout；Minimal 角标
- [x] **2.4** `syncWithTabs` / `makeTabItemForTab` 同步态与回调
- [x] **2.5** Delegate：`tabStripView:didToggleMuteForTabID:`
- [x] **2.6** hover tip：「静音此标签」/「取消静音」

### 自测

1. [ ] 点喇叭不切换标签、不启动拖拽（待手测）
2. [ ] 三档宽度布局正常（待手测）
3. [ ] 选中/非选中均可见喇叭（待手测）

---

## Phase TA-3：失活策略修订

### 任务

- [x] **3.1** `refreshTabsUI`：不再调用 `pauseMediaInWebView` 作为默认路径
- [x] **3.2** 失活时若 `isAudible` → `mediaHeavy=YES`；跳过昂贵快照逻辑保留
- [x] **3.3** 更新 `heavy-page-ui-responsiveness-design.md` 与 development-plan 定稿表
- [x] **3.4** `BrowserBackgroundMediaController` 保留 API（供可选/调试）

### 自测

1. [ ] 切走 YouTube 仍出声 + 喇叭仍在（待手测）
2. [ ] ~90s 后 mediaHeavy 标签仍可被休眠（待手测）
3. [ ] 切回不自动 play（若站点未自己恢复）（待手测）

---

## Phase TA-4：打磨

### 任务

- [x] **4.1** 主文档 committed 清除 `isPageMutedByUser` 并解除 mute
- [x] **4.2** 溢出菜单行显示喇叭（只读）
- [x] **4.3** 右键「静音标签」
- [ ] **4.4** 验收清单勾选；文档状态改为已完成

### 验收清单

| # | 场景 | 期望 | 状态 |
|---|------|------|------|
| 1 | 前台有声视频 | 喇叭出现 | [ ] |
| 2 | 点喇叭 | 静音且不切标签 | [ ] |
| 3 | 再点 | 恢复有声 | [ ] |
| 4 | 后台出声 | 非选中标签仍显示喇叭 | [ ] |
| 5 | 停止播放 | 喇叭消失（≤1s） | [ ] |
| 6 | Minimal | 可辨认并可点 | [ ] |
| 7 | 休眠唤醒已静音 | 保持静音 | [ ] |
| 8 | 直播重页点静音 | 标签栏仍可点 | [ ] |

---

## 实现顺序建议

先 TA-0 → TA-1 → TA-2 打通 MVP，再 TA-3 取消失活 pause（否则后台指示难验），最后 TA-4。
