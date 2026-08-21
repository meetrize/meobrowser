# 标签栏「更多」菜单 — 自动滚动 / 大小窗预设

> 目标：在置顶图标**右侧**增加竖三点（⋯）入口；弹出菜单提供（1）页面自动竖向滚动（速度可设、滚动中改速即时生效）；（2）大窗 / 小窗模式切换与位置尺寸（及小窗透明态）预设记忆。  
> 状态：**已完成（MO-0～MO-3）**；入口与菜单结构后续演进见 [chrome-actions-customize-design.md](chrome-actions-customize-design.md)（自动滚 / 速度 / 窗口缩放已升为可固定 Catalog 图标；⋯ 为单一图钉列表）。  
> 开发计划：[chrome-more-menu-development-plan.md](chrome-more-menu-development-plan.md)  
> Cursor 计划：[.cursor/plans/chrome-more-menu.plan.md](../../.cursor/plans/chrome-more-menu.plan.md)  
> 关联：[tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) · [transparent-mode-design.md](transparent-mode-design.md) · [multi-window-design.md](multi-window-design.md) · [chrome-actions-customize-design.md](chrome-actions-customize-design.md)

---

## 1. 需求理解

### 1.1 入口

```
[…][+]  [摸鱼][透明][精简][置顶][⋯]  ░trailing
```

- 图标：SF Symbol `ellipsis`（竖排可用 `ellipsis.vertical`，macOS 11+）  
- 行为：**点击弹出 `NSMenu`**（非 toggle 高亮开关）  
- 位置：置顶**右侧**（Chrome 动作区最右）

### 1.2 功能 A — 页面自动滚动

| 项 | 理解 |
|----|------|
| 触发 | 菜单项开关「自动滚动」（可勾选） |
| 条件 | 当前页**可竖向滚动**（存在溢出 / scrollHeight > clientHeight）时才真正滚动；不可滚则开着也不动，或灰显提示 |
| 方向 | **仅向下**（V1） |
| 速度 | 有默认初值；**设置 → 常规**（或阅读相关区）增加滑杆 |
| 即时性 | **正在滚动时改滑杆，立即用新速度**，无需开关一次 |

### 1.3 功能 B — 窗口缩放（大窗 / 小窗）

| 项 | 理解 |
|----|------|
| 两种模式 | **大窗口模式** / **小窗口模式**（互斥；同一时刻只处其一，或另有「未用预设」常态，见 §3 定稿） |
| 大窗 | 用户拖移/缩放后，把当前 **frame** 记为「大窗预设」；再次进入大窗 → 恢复该 frame |
| 小窗 | **首次**进入：给初始 frame，并**默认开透明**；之后用户改位置/大小 → 记为小窗预设；**是否透明也写入小窗预设**；再进小窗 → 恢复 frame + 透明布尔 |

---

## 2. 交互漏洞与风险（分析）

### 2.1 自动滚动

| # | 漏洞 / 模糊点 | 影响 | 建议定稿（V1） |
|---|----------------|------|----------------|
| A1 | 滚到页底怎么办？ | 死循环空转或卡住 | **到底暂停**，菜单勾选自动关；可选「回顶循环」作后续 |
| A2 | 用户手动滚轮 / 触控板？ | 与自动滚冲突 | **用户一滚动即暂停自动滚**（勾选取消），避免抢滚动 |
| A2b | 鼠标移入滚动窗？ | 想看清/操作时不停 | **指针在窗内立刻暂停**（勾选保持）；**移出窗后继续自动滚** |
| A3 | 多标签 / 后台标签？ | 耗电、看不见仍在滚 | **仅当前选中标签**；切走暂停，切回不自动恢复（需再开） |
| A4 | 导航 / 刷新 / 新文档？ | 旧 timer 打到新页 | `didCommit` / 选中变更时停 |
| A5 | iframe / 特殊阅读器（微信读书 Canvas）？ | `window` 滚不动正文 | V1 对 **主 frame `window`/`document.scrollingElement`**；失败则提示「当前页不支持」；站点特例后续 |
| A6 | 速度单位不直观 | 滑杆难调 | 用「档位」或 px/s，滑杆旁显示约值（如 40～400 px/s） |
| A7 | 透明藏壳 / 摸鱼时 | 菜单在条上，条可能藏 | 仍可用 Status Item / 移入显条后再关；设置里也可关自动滚 |
| A8 | 无竖向滚动条但仍 overflow？ | 「有滚动条」检测不准 | 用 **可滚动**（scrollHeight > clientHeight + 1）而非「是否绘制出滚动条」 |

### 2.2 大窗 / 小窗

| # | 漏洞 / 模糊点 | 影响 | 建议定稿（V1） |
|---|----------------|------|----------------|
| B1 | 启动时算大还是小？ | 与 session `frame` 打架 | 增加第三态 **「自由」**：未点过大/小切换时跟 session；点过大/小后进入对应模式并套预设 |
| B2 | 何时写入预设？ | 拖拽中每帧写盘过频 | **`windowDidResize` / `windowDidMove` 结束**（或 debounce 0.4s）且当前处于该模式时写入 |
| B3 | 大窗预设含不含透明？ | 需求只写小窗含透明 | **大窗预设：仅 frame**；进大窗**不改**透明布尔（保持进入前）。小窗预设：**frame + transparentMode** |
| B4 | 小窗「默认透明」与已有透明冲突 | 进小窗强制透明，出小窗呢？ | 进小窗前 **快照** `transparentMode`；出小窗（切大窗或回自由）**恢复快照**，除非小窗预设要求保持（V1：出小窗恢复进小窗前快照） |
| B5 | 小窗首次初始 frame 多少？ | 过大过小 | 定稿：约 **420×640**，放在 **当前屏可见区右下或相对大窗右下偏移**；多屏用窗所在 screen |
| B6 | 全屏？ | 预设无意义 | **全屏禁用**大小窗切换；已全屏则菜单项灰 |
| B7 | 多窗口 | 预设全局还是每窗 | **每窗独立预设**（UserDefaults 按 window 不稳）→ V1：**应用级共享一套**大/小预设（所有窗共用），简单符合「我的阅读小窗」；多窗同时开小窗都用同一预设 frame 会重叠 → **第二扇小窗略偏移 (+24,+24)** |
| B8 | 与置顶 / 精简 / 摸鱼 | 未说明是否进预设 | V1 **不写入**；仅 frame（+ 小窗透明）。置顶等保持用户当前选择 |
| B9 | 窗口放大/缩小菜单如何表示 | 两项还是互斥组 | **单一菜单项**：当前为缩小态时显示「窗口放大」，否则显示「窗口缩小」；无勾选态，点击即切换 |
| B10 | 用户在小窗关透明 | 预设何时更新 | 关透明后若仍小窗模式，debounce 写入 `transparent=NO`；再进小窗保持不透明 |
| B11 | 最小尺寸系统限制 | 小窗被钳制 | 预设读写用实际 `window.frame`；尊重 `minSize` |
| B12 | 屏幕配置变化 | 预设跑出屏外 | 恢复前 **clamp 到可见 screen 可见区**（AppKit 常规做法） |

### 2.3 入口与信息架构

| # | 问题 | 建议 |
|---|------|------|
| C1 | ⋯ 与设置里滑杆分裂 | 菜单「自动滚动」旁可加「滚动速度…」跳转设置；设置改速仍即时生效 |
| C2 | 图标过多挤标签 | 可接受；`preferredWidth` 已扣宽；极窄窗依赖现有溢出 |
| C3 | 竖三点是否「开」态 | 菜单按钮无 on；子功能用菜单勾选表达 |

---

## 3. 改进建议（纳入 V1 或标明后续）

| ID | 建议 | V1? |
|----|------|-----|
| S1 | 自动滚到底 **停止并取消勾选** | **是** |
| S2 | 用户滚轮 **打断自动滚** | **是** |
| S2b | 指针移入窗内 **暂停**、移出 **继续**（不取消勾选） | **是** |
| S3 | 速度单位 **px/s**，范围 10–200，默认 80；慢速用亚像素累积 | **是** |
| S4 | 大小窗第三态「自由」+ 共享预设 + 恢复 clamp | **是** |
| S5 | 小窗进/出透明快照恢复 | **是** |
| S6 | 自动滚「回顶循环」 | 否，后续 |
| S7 | 大窗预设也记透明 | 否，按需求不记 |
| S8 | 小窗默认同时开置顶（摸鱼阅读） | 否，可选后续 |
| S9 | 菜单显示当前模式标记（大/小） | **是**（勾选） |

---

## 4. 行为定稿

### 4.1 ⋯ 菜单结构（V1）

```
☑ 自动滚动
  滚动速度…          → 打开设置并聚焦滑杆（或弹出小面板）
────────
  窗口缩小            → 点击后变为「窗口放大」（单一项切换，无勾选）
```

（缩小态显示「窗口放大」，自由/放大态显示「窗口缩小」。）

### 4.2 自动滚动

| 规则 | 定稿 |
|------|------|
| 作用域 | 当前窗口 **选中标签** 的主 frame |
| 实现 | `evaluateJavaScript` 定时 `scrollBy` / 或注入 rAF 循环；**优先 JS rAF + 速度变量**，设置改 `window.__MeoAutoScroll.speed` |
| 启停 | 菜单勾选；打断条件见 S1/S2；关标签/导航停 |
| 偏好 | `BrowserAutoScrollPreferences`：`speedPxPerSec`；`DidChange` 通知立刻生效 |
| 设置 UI | 常规页滑杆 + 说明「自动滚动开启时调节立即生效」 |

### 4.3 大小窗

| 规则 | 定稿 |
|------|------|
| 模式枚举 | `free` / `large` / `small`（每窗内存态；**不强制**进 session，可选记入 session） |
| 预设存储 | App 级 UserDefaults：`largeFrame`、`smallFrame`、`smallTransparent`；另 `smallPresetInitialized` |
| 进大窗 | `mode=large`；若有大窗预设则 `setFrame:display:`（animate 短）；**不改透明** |
| 进小窗 | `mode=small`；快照当前透明；若无小窗预设 → 初始 frame + **开透明**；若有预设 → 套 frame + 套透明布尔 |
| 出小窗（切大或自由） | 恢复进小窗前透明快照（若切大窗则再套大窗 frame） |
| 写预设 | 处于 large/small 且 move/resize 结束 debounce → 写对应预设；small 同时写当前 `transparentModeEnabled` |
| 全屏 | 菜单项禁用 |

### 4.4 与现有模式正交

| 能力 | 关系 |
|------|------|
| 透明 / 精简 / 置顶 / 摸鱼 | 大小窗不覆盖其图标逻辑；仅小窗进入时可能 `setTransparentModeEnabled:` |
| 透明自动藏壳 | 小窗透明后仍适用 |
| Session `frame` | 冷启动仍用 session；用户点大/小后再被预设覆盖 |

---

## 5. 技术设计摘要

### 5.1 模块

| 模块 | 职责 |
|------|------|
| ChromeActions | 新 item `moreMenu` / `ellipsis`；点击 `popUpMenu` |
| `BrowserAutoScrollController` | 每窗；启停、注入/调速、打断 |
| `BrowserAutoScrollPreferences` | 速度持久化 + 通知 |
| `BrowserWindowLayoutPresetStore` | 大/小 frame + 小窗透明 |
| WC | `windowLayoutMode`；进大/小；resize/move 观察写盘 |
| Settings | 滑杆 |

### 5.2 自动滚 JS 要点

```text
__MeoAutoScroll = { enabled, speed, rafId }
tick: scrollBy(0, speed * dt); if at bottom → post message stop
```

用户 `wheel` → native 侧停（WK 难捕 wheel 时用 JS `wheel` listener → message）。

### 5.3 预设 frame

`NSStringFromRect` / `NSRectFromString`；恢复前：

```text
frame = clampRectToVisibleScreen(frame, window.screen ?: NSScreen.mainScreen)
```

---

## 6. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | ⋯ 位置 | 置顶右侧 |
| D2 | 到底 | 停止并关勾选 |
| D3 | 用户滚动 | 打断 |
| D4 | 速度 | px/s，10–200，默认 80；设置滑杆即时；慢速满 1px 再滚 |
| D5 | 大小窗态 | free / large / small |
| D6 | 预设范围 | App 级共享；多窗小窗偏移 |
| D7 | 大窗预设 | 仅 frame |
| D8 | 小窗预设 | frame + transparent |
| D9 | 出小窗透明 | 恢复进入前快照 |
| D10 | 全屏 | 禁用切换 |

---

## 7. 验收标准（V1）

- [x] 置顶右侧有 ⋯，点击出菜单  
- [x] 自动滚动：可滚页向下匀速；到底停；滚轮打断；设置改速即时变  
- [x] 不可滚页：开启不崩溃（不滚或提示）  
- [x] 大窗：记住 frame，再进恢复（屏内）  
- [x] 小窗首次：初始尺寸 + 透明；再调后记住 frame+透明  
- [x] 小窗↔大窗透明行为符合 D8/D9  
- [x] 全屏菜单项灰  
- [x] `make browser` 通过  

---

## 8. 后续扩展

- 回顶循环、横向滚、仅阅读器容器滚  
- 每窗独立预设 / 多套命名布局  
- 小窗默认置顶  
- ⋯ 内更多阅读工具（稍后读等）  
