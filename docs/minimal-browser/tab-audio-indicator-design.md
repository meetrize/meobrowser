# 标签出声指示 + 点击静音 — 设计方案

> 目标：网页播放有声视频/音乐时，对应标签显示可点喇叭图标；点击对该标签做**页级静音**（非暂停），再点恢复。  
> 状态：**代码已落地（TA-0～TA-4 主体）；待手测验收**  
> 开发计划：[tab-audio-indicator-development-plan.md](tab-audio-indicator-development-plan.md)  
> 关联：[multi-tab-design.md](multi-tab-design.md) · [tab-strip-lru-favicon-design.md](tab-strip-lru-favicon-design.md) · [heavy-page-ui-responsiveness-design.md](heavy-page-ui-responsiveness-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**像 Chrome / Safari：谁在出声谁亮喇叭；点喇叭只静音该页，不切标签、不停播。**

### 1.2 背景与问题

| 现状 | 问题 |
|------|------|
| 标签条仅有 favicon / 标题 / 关闭 / pin | 多标签时无法辨认「谁在响」 |
| `BrowserBackgroundMediaController` 失活强制 `pause` + DOM `muted` | 后台无法继续出声；也不是用户可控的页级静音 |
| `mediaHeavy` 仅服务休眠与跳过快照 | **不能**当作「正在出声」UI 状态 |
| 无 WebKit 出声 / 页 mute 封装 | 检测与静音散落将难以维护 |

### 1.3 做什么（V1）

| 能力 | 说明 |
|------|------|
| **出声检测** | 每标签维护 `isAudible`；公开 API 轮询 + 可选 SPI |
| **页级静音** | `isPageMutedByUser`；点击喇叭切换；优先 `_setPageMuted:`，降级 JS |
| **标签条图标** | Comfortable/Compact：favicon 与标题间可点喇叭；Minimal：favicon 角标/替换 |
| **策略 A 后台可听** | 切标签**不再**默认 pause；保留 `mediaHeavy` 加速休眠作重页兜底 |
| **状态解耦** | `isAudible` / `isPageMutedByUser` / `mediaHeavy` 三者独立 |

### 1.4 不做什么（V1）

- **不**做站点默认静音名单、广告音识别
- **不**做全局音量条 / 跨窗口统一混音 UI
- **不**把麦克风采集态与「播放出声」混成同一图标（采集指示若做，另开）
- **不**硬链 WebKit 私有头文件；SPI 仅 `respondsToSelector:` / `objc_msgSend`
- **不**在重新选中时自动 `play()`（与 heavy-page 一致）
- **不**改 pinned 专用宽度算法（喇叭挤进现有 leading 区）

### 1.5 设计原则

1. **静音 ≠ 暂停**：静音后媒体可继续解码/播放（无声）。  
2. **点击喇叭 ≠ 选中标签**：命中区单独接收事件，不触发 reorder/select。  
3. **后台可听 + 重页可杀**：体验优先可听；资源靠 90s `mediaHeavy` 休眠与预算淘汰。  
4. **用户 mute 优先于系统/性能 mute**：失活逻辑不得清掉 `isPageMutedByUser`。  
5. **节流刷新**：出声态变化合并进 `updateTabStripDisplay`，避免直播刷爆主线程。

---

## 2. 交互设计

### 2.1 场景

#### 场景 A — 前台播放

```
用户在标签 A 打开 YouTube 并播放
  → A 出现喇叭（speaker.wave.2）
  → 点击喇叭 → 页静音，图标变 speaker.slash
  → 再点 → 取消静音，恢复有声
```

#### 场景 B — 后台继续出声（策略 A）

```
用户切到标签 B，A 仍在播
  → A（非选中）仍显示喇叭
  → 可在 A 上点静音而不切到 A
```

#### 场景 C — 停止播放

```
页面 pause / 播完 / 无媒体
  → 短暂延迟后喇叭消失
  → 若仍 isPageMutedByUser：可保留静音态直至导航策略清除（见 §4.3）
```

#### 场景 D — Minimal 挤满

```
标签宽 32 pt
  → 喇叭以小角标叠在 favicon 右下，或暂替 favicon
  → tooltip：「静音此标签」/「取消静音」
```

### 2.2 图标与文案

| 状态 | SF Symbol | Tooltip |
|------|-----------|---------|
| 出声且未静音 | `speaker.wave.2.fill` | 静音此标签 |
| 用户已静音（仍显示控件） | `speaker.slash.fill` | 取消静音 |
| 未出声且未静音 | 隐藏按钮 | — |

V1：**已静音时即使短暂 `isAudible==NO` 仍显示划线喇叭**，避免点完立刻消失无法恢复；主文档导航可清除 mute（§4.3）。

### 2.3 右键菜单（P2，可与 V1 同迭代若成本低）

- 「静音标签」/「取消静音」
- 「静音其他标签」（可选）

---

## 3. 架构

```text
WKWebView
  └─ BrowserTabAudioController（窗口级调度或每 tab 观察）
        ├─ poll / SPI → tab.isAudible
        └─ setPageMuted → tab.isPageMutedByUser + WebKit/JS

BrowserTab
  ├─ isAudible
  ├─ isPageMutedByUser
  └─ mediaHeavy（性能，独立）

BrowserTabItemView
  └─ audioButton → onToggleMute

BrowserTabStripView.syncWithTabs
  └─ 同步 audible / muted

BrowserBackgroundMediaController（修订）
  └─ 失活：探测媒体 → mediaHeavy；默认不再 pause/mute
     （探测可复用 AudioController 的 isAudible）
```

### 3.1 检测策略（优先级）

| 层 | 机制 | 说明 |
|----|------|------|
| L1 公开 | `requestMediaPlaybackStateWithCompletionHandler` 轮询（约 0.5～1s） | Playing → audible |
| L2 SPI | `_isPlayingAudio`（selector 探测；可试 KVO） | 更贴近真实出声 |
| L3 降级 | 注入 play/pause/volumechange（可选，V1 可不做） | 覆盖不全 |

合并规则：任一来源为真则 `isAudible=YES`；连续两轮为假再清（防闪烁）。

### 3.2 静音策略

| 层 | 机制 |
|----|------|
| L1 SPI | `_setPageMuted:` + `_WKMediaAudioMuted`（1<<0） |
| L2 降级 | JS：所有 `video,audio` 设 `muted`；尽力 `AudioContext.suspend` |

唤醒休眠 / 重建 WebView 后：若 `isPageMutedByUser`，重新应用 mute。

### 3.3 与 heavy-page 对齐

| 原 HP-1 | 本方案 |
|---------|--------|
| 失活 `pause` + DOM `muted` | **默认取消**；改由用户 mute + 休眠治理 |
| `mediaHeavy` | 保留；可由「失活时曾 audible / 探测到媒体」置位 |
| 跳过昂贵快照 | 保留：`mediaHeavy` 或当前 `isAudible` |
| 不自动 `play()` | 不变 |

---

## 4. 数据模型与生命周期

### 4.1 `BrowserTab` 新增

```objc
@property (nonatomic, assign) BOOL isAudible;
@property (nonatomic, assign) BOOL isPageMutedByUser;
```

`discardWebView` / hibernate：`isAudible=NO`；**可保留** `isPageMutedByUser` 以便唤醒重应用（或清除——V1 定稿：**唤醒后重应用，hibernate 时保留 mute 标志**）。

### 4.2 `BrowserTabAudioController`

职责：

- 对窗口内存活 WebView 做检测调度（单 timer，遍历 tabs）
- `toggleMuteForTab:` / `applyMuteStateForTab:`
- 状态变化回调 → `BrowserWindowController` 节流 `updateTabStripDisplay`

### 4.3 Mute 清除时机

| 事件 | 行为 |
|------|------|
| 用户再点喇叭 | 取消 mute |
| 主文档 committed 新导航 | V1：**清除** `isPageMutedByUser`（贴近 Chrome） |
| 同文档 hash / pushState | 保留 |
| 关标签 | 随 tab 销毁 |

---

## 5. UI 布局（`BrowserTabItemView`）

### 5.1 Comfortable / Compact

- leading：favicon → **audioButton(14～16pt)** → pin? → title → close  
- `audioButton` 仅在 `isAudible || isPageMutedByUser` 时显示  
- title leading 约束随 audio 显隐切换  

### 5.2 Minimal

- favicon 右下 8～10pt 角标按钮；或静音态用 slash 替换中心图标一小会儿  
- V1 推荐：**角标叠放**，favicon `hitTest` 仍穿透；audio 按钮自己吃点击  

### 5.3 hitTest

与 close 相同：`hitTest` 优先返回 `audioButton`，避免进入标签 `mouseDown` tracking。

### 5.4 溢出菜单（V1 轻量）

- 行尾或标题旁小喇叭图标（不可点亦可；P2 可点）  
- 至少视觉一致，避免「条上挤没了却还在响」完全无提示  

---

## 6. 验收标准（摘要）

1. 有声播放 → 对应标签出现喇叭  
2. 点喇叭 → 立刻无声，图标变静音；不切换选中  
3. 再点 → 恢复有声  
4. 切走后（策略 A）后台仍可出声且非选中标签仍显示喇叭  
5. 停止播放后喇叭消失（允许 ≤1s 延迟）  
6. Minimal 下仍可点静音  
7. 休眠唤醒后若曾用户静音，保持静音  
8. 直播重页下点静音不卡死标签栏  

---

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 公开 API 漏检 Web Audio | SPI 增强；文档标明尽力而为 |
| 取消失活 pause 导致后台吃资源 | `mediaHeavy` 90s 休眠 + 预算淘汰；后续可加「仅暂停 video」开关 |
| SPI 系统升级失效 | 运行时探测；失败走公开/JS |
| 布局与 pin/close 冲突 | 显式约束优先级；手测三档 |

---

## 8. 文档交叉引用

实现落地后更新：

- [heavy-page-ui-responsiveness-design.md](heavy-page-ui-responsiveness-design.md)：失活默认不再 pause  
- [multi-tab-design.md](multi-tab-design.md)：标签态增加 audio  
- 本开发计划勾选任务  
