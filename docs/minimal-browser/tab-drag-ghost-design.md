# 标签拖拽跟随阴影 — 交互与实现方案

> 目标：拖动标签时提供**跟随指针的半透明「影子标签」**，区分「条内排序」与「拖出成新窗口」，提升可预期性与完成感。  
> 状态：**已实现（DG-0～DG-2，2026-07-15）**  
> 开发计划：[tab-drag-ghost-development-plan.md](tab-drag-ghost-development-plan.md)  
> Cursor Plan：[.cursor/plans/tab-drag-ghost.plan.md](../../.cursor/plans/tab-drag-ghost.plan.md)  
> 现状：[`BrowserTabItemView`](../../SimpleBrowser/Tabs/BrowserTabItemView.m) 阈值后仅平移真实标签；[`BrowserTabStripView`](../../SimpleBrowser/Tabs/BrowserTabStripView.m) 夹紧在条内；松手在窗外 → 整页迁入新窗口。  
> 关联：[multi-window-design.md](multi-window-design.md)、[multi-tab-design.md](multi-tab-design.md)、[tab-strip-adaptive-width-design.md](tab-strip-adaptive-width-design.md)

---

## 1. 方案定位

### 1.1 做什么

| 能力 | 说明 |
|------|------|
| **影子标签（Drag Ghost）** | 拖拽阈值后出现与源标签同外形的半透明浮层，跟随鼠标 |
| **双模式反馈** | 条内：排序预览；条外：明确「松开 → 新窗口」 |
| **落点动画** | 松手后影子收束到目标位置（槽位或新窗口标题栏区域）后消失 |
| **无障碍降级** | 动画可关 / 性能不足时仍可不显示影子，拖拽逻辑不变 |

### 1.2 不做什么（首版）

- 不做跨应用拖放（不把链接拖到 Finder / 外部 App）
- 不做多标签同时拖成一摞
- 不做完整窗口缩略图预览（Safari 式）—— 首版仅「标签形态」影子
- 不改变现有 reorder / move-to-new-window 语义与真实 WebView 迁移逻辑

### 1.3 设计原则

| # | 原则 |
|---|------|
| 1 | **影子搬运，源位占坑**：条内拖时真实标签变「占位态」，影子负责跟手 |
| 2 | **模式可读**：用户不靠猜松手结果——条内 vs 条外视觉有清晰分野 |
| 3 | **轻量**：影子是轻量 `NSView` / `NSImageView` 快照，不复制 `WKWebView` |
| 4 | **不挡操作**：影子不参与 hit-test；不改变关闭按钮 / 排序命中逻辑 |
| 5 | **中文产品语气**：状态提示可用简洁中文（可选角标），不堆英文 |

---

## 2. 拖拽状态机

```
Idle
  │ mouseDown（选中标签）
  │ |Δx| ≥ 阈值（保持现有 4pt，可选改为欧氏距离）
  ↓
DraggingInStrip（条内排序）
  │ 指针落到「拖出判定区」
  ↓
DraggingDetach（将成新窗口）
  │ 回到条内有效区
  ↓
DraggingInStrip
  │
  ├─ mouseUp in strip → CommitReorder → Idle
  ├─ mouseUp outside  → CommitNewWindow → Idle
  └─ Esc / 取消       → Cancel → Idle（源位恢复）
```

### 2.1 阈值（Threshold）

| 项 | 建议 | 说明 |
|----|------|------|
| 触发距离 | **4 pt**（可调到 6） | 与今日一致，避免误触 |
| 度量 | 首版仍可用 `|Δx|`；优化可改为 `hypot(Δx, Δy)` | 竖直微抖也能触发影子，拖出更自然 |
| 触发瞬间 | 创建影子 + 源标签进入占位态 + `beginReorderDrag` | 同帧，避免闪一下「实体飞走」 |

### 2.2 区域判定

| 区域 | 定义 | 模式 |
|------|------|------|
| **条内有效区** | 标签条（含左右拖动空白区）bounds 向外扩张 **8 pt** 的 hit rect，坐标系为窗口/屏幕 | `DraggingInStrip` |
| **拖出区** | 不在条内有效区 | `DraggingDetach` |

> 用「扩张条」而不是「整个窗口外」，是因为：用户常在标题栏上下甩一点指针；Safari/Chrome 也是「离开标签条」即进入拆窗语义，不必等完全离开 `NSWindow.frame`。

与现实现状对齐建议：

- **松手成新窗口**：继续用「屏幕点不在源 `NSWindow.frame`」**或**升级为「不在条内有效区且持续 ≥ 80 ms」二选一（见 §6 决策）。
- **影子模式切换**：一律按「是否在条内有效区」切换视觉，响应更快。

---

## 3. 视觉规范

### 3.1 影子标签外观

影子是源 `BrowserTabItemView` 的**外观克隆**（标题 + 固定态宽度暗示 + 选中样式），不是空阴影块。

| 属性 | 条内排序（InStrip） | 拖出新窗（Detach） |
|------|---------------------|---------------------|
| 尺寸 | 与源标签当前 `frame.size` 一致 | 同左，可略放大 **1.02×** |
| 不透明度 | **0.88** | **0.78** |
| 圆角 | 与源标签一致 | 同左 |
| 阴影 | `shadowOpacity 0.25`，`blur 8`，`offset (0, -2)` | `opacity 0.35`，`blur 12`，略强 |
| 描边 | 无或极淡 | 可选 1pt 强调色描边（系统 accent，α=0.35） |
| 缩放 | 1.0 | 1.02～1.04（暗示「将独立」） |
| 角标 | 无 | 可选小标签「新窗口」（9–10pt，半透明胶囊） |
| 指针 | 默认箭头或 `closedHandCursor` | 同左 |

深色 / 浅色：跟随窗口有效外观；内容用与标签条相同的 fill / title 色，避免硬编码纯白灰。

### 3.2 源标签「占位态」

拖起后，条内原位**不再显示完整实心标签**，而显示槽位：

| 方案 | 描述 | 推荐 |
|------|------|------|
| A. 空心轮廓 | 同尺寸圆角虚线/浅填充 α=0.2 | **推荐** |
| B. 压缩空隙 | 其它标签挤过来，无显式槽 | 差，难对齐插入点 |
| C. 源标签半透明留在原位 + 影子跟手 | 双影易乱 | 不采用 |

插入预览：其余标签仍按现有 `layoutTabsExcludingDraggedItem` 让出插入空隙；占位槽跟在「逻辑插入下标」对应的空隙上，或固定显示在「被拖标签的逻辑坑」上（见 §4.1）。

### 3.3 层级与宿主

| 层级 | 说明 |
|------|------|
| 影子窗口 / 浮层 | 优先：`NSPanel`（borderless、nonactivating、opaque=NO）浮在所有控件之上，便于**跨出原窗口**仍跟手 |
| 备选 | 加在 `NSScreen` 级的自定义 borderless `NSWindow`（`ignoresMouseEvents=YES`） |
| 禁止 | 把影子加在 `tabsContentView` 内——离开窗口会裁剪 |

`ignoresMouseEvents = YES`，不抢事件；拖拽仍由 `BrowserTabItemView` 的 tracking loop 驱动。

---

## 4. 交互细节（分模式）

### 4.1 条内排序（DraggingInStrip）

```
指针移动
  → 影子中心点 ≈ 指针位置 + 抓取偏移（grab offset）
  → 原逻辑 insertionIndexForDraggedItem 仍用「内容坐标上的投影」
  → 其余标签让出空隙；源占位槽跟着插入空隙走（或固定坑 + 空隙二选一，见下）
```

**抓取偏移（Grab Offset）**

- mouseDown 时记录：指针相对源标签 `bounds` 的局部点 `grabPoint`
- 影子左下角（或中心）= 指针屏坐标 − grabPoint  
- 避免影子左上角突然跳到指针下，造成「拖空」感

**条内跟手 vs 实体平移**

| 策略 | 行为 | 推荐 |
|------|------|------|
| **Ghost-led（推荐）** | 真实 `draggingItem` 隐藏或 α=0；只用影子跟手；插入预览靠其它标签让位 | 与「透明阴影」目标一致 |
| Hybrid | 条内实体仍 clamp 平移，影子叠在上面 | 冗余，首版不做 |

现有 `moveReorderDragForItem:deltaX:` 对实体的 clamp 在 Ghost-led 下改为：

- 实体：藏起 / 占位  
- 插入索引：用指针换算到 `tabsContentView` 的 `x`（不必再绑实体 frame）

### 4.2 拖出新窗口（DraggingDetach）

进入条件：指针离开「条内有效区」。

| 反馈 | 行为 |
|------|------|
| 影子 | 切换到 Detach 视觉（更透、略放大、可选「新窗口」角标） |
| 条内 | 占位槽可保留，或淡出占位并让其它标签合拢（合拢更强调「将带走」）——**推荐合拢 120ms** |
| 指针 | 可保持 closedHand |
| 松手 | 影子短促放大或飞向将出现的窗口标题栏位置，随新窗口 `orderFront` 淡出 |

取消回到条内：影子切回 InStrip 样式；标签条重新让出插入空隙（与离开前 last preview index 衔接，避免跳动）。

### 4.3 松手落点

| 结果 | 动画（时长建议） | 随后 |
|------|------------------|------|
| 条内重排 | 影子 120～160ms ease-out **吸附到目标槽位中心**，淡出 | `didMoveTabID:toIndex:`（已有） |
| 新窗口 | 影子 160～200ms 移向 `screenPoint` 附近新窗 frame 的标题栏中点，同时新窗显示；影子 fade out | 现有 `extractTabKeepingAlive` + `adoptTab` |
| 取消（Esc） | 影子 120ms 回到源槽，淡出 | 恢复模型顺序，不 commit |

首版**可不做 Esc 取消**（记入后续）；做则需在 tracking loop 监听 `keyDown`。

### 4.4 边界与特殊标签

| 情况 | 行为 |
|------|------|
| 固定标签 | 允许拖；条内仍受 pinned 区间限制（现有逻辑）；可拖出成新窗且保持 pinned |
| 唯一标签 | 可拖出；松手后原窗关闭（已有）；影子落点对着新窗即可 |
| 溢出菜单中的标签 | 首版不支持从 ▾ 菜单拖出；仅条内可见标签 |
| 拖到另一浏览器窗标签条 | **首版不做**跨窗拖入；落到其它窗仍视为「本窗拖出 → 新窗口」。跨窗合并列为后续 |

### 4.5 与右键菜单关系

- 右键「将标签移到新窗口」：**不走影子动画**（瞬时迁移），或可选播放一段「标签弹出」短动画（非必须）
- 拖拽中不打开 context menu

---

## 5. 动效时间表（定稿建议）

| 事件 | 时长 | 曲线 |
|------|------|------|
| 影子出现 | 80ms | ease-out；α 0→目标，scale 0.96→1 |
| 模式切换 InStrip ↔ Detach | 100ms | 交叉淡入淡出样式参数 |
| 条内其它标签让位 | 保持现有瞬时或 80ms | 若现为无动画，首版可保持瞬时以降低复杂度 |
| 松手吸附 / 飞向新窗 | 120～200ms | ease-in-out |
| 影子消失 | 与吸附重叠最后 80ms | α→0 |

性能：拖动中**每帧只更新影子 `setFrameOrigin` / `setFrame`**，禁止每帧重绘位图；位图在 `began` 时生成一次。

---

## 6. 待拍板决策

| # | 问题 | 选项 | 建议 |
|---|------|------|------|
| D1 | 松手「新窗口」判定 | A) 窗外 frame（现状）B) 离开标签条 C) 二者任一 | **B**：与影子模式一致；实现时改 `endReorderDrag` |
| D2 | 拖出时条内是否合拢 | 合拢 / 留槽 | **合拢** |
| D3 | Detach 是否显示「新窗口」角标 | 要 / 不要 | **要**（可本地化一行字） |
| D4 | Esc 取消 | 首版要 / 不要 | **不要**（记 V2） |
| D5 | 跨窗拖入其它 Meo 窗口 | 首版 ghost 不做 → **见 [tab-cross-window-drop-design.md](tab-cross-window-drop-design.md)** |

---

## 7. 架构与实现要点

### 7.1 模块划分

```
BrowserTabItemView          阈值、tracking、回调（改为传 screen/window point）
        ↓
BrowserTabStripView         状态机、插入索引、占位、松手 commit
        ↓
BrowserTabDragGhostController   新建：影子生命周期、截图、跟手、模式样式、落点动画
        ↓
AppDelegate / WindowController  仅接收最终 move / adopt（逻辑已有）
```

建议新文件：

- `SimpleBrowser/Tabs/BrowserTabDragGhostController.h/.m`
- 可选 `BrowserTabDragPlaceholderView`（占位槽）

### 7.2 Ghost 内容生成

| 方式 | 说明 |
|------|------|
| **推荐** | `began` 时对源 `BrowserTabItemView` `bitmapImageRepForCachingDisplayInRect:` → `NSImage`，放入 ghost 的 `NSImageView` |
| 备选 | 手写复制 title/pinned/selected 的轻量 `BrowserTabItemView` 实例（非条内那份） |

截图一次即可；拖动中改 α/shadow/scale，不重新 cache。

### 7.3 回调演进（相对现状）

现状：

```objc
onReorderDragMoved(CGFloat deltaX);
onReorderDragEnded(NSPoint locationInWindow);
```

建议：

```objc
onReorderDragMoved(NSPoint locationInWindow); // 或附带 screenPoint
onReorderDragEnded(NSPoint locationInWindow);
```

Strip 内同时计算：

- `contentX` → 插入索引  
- `screenPoint` → ghost 位置 + 是否在条内有效区  

### 7.4 与真实 WebView 迁移

影子**绝不**持有 `WKWebView`。松手 `CommitNewWindow` 仍走：

`extractTabKeepingAlive` → `createBrowserWindowAdoptingTab:frame:`  

动画可与窗口创建并行：先 `orderFront` 新窗（可先设 frame），影子飞向标题栏再 remove。

### 7.5 无障碍与偏好（可选）

- 若 `NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion`：跳过位移动画，影子瞬移消失  
- 不强制偏好面板开关；需要时可后续加「标签拖拽动效」

---

## 8. 验收标准

### 交互

- [ ] 拖过阈值后立即出现半透明影子，并跟手；源位为占位或合拢，无「双实体」
- [ ] 条内拖动：其它标签让位；松手后顺序正确；影子吸附后消失
- [ ] 拖出条外：影子进入 Detach 样式（更透/略大/可选角标）
- [ ] 在 Detach 态松手：标签真正迁到新窗口（WebView 不重载）；影子收束动画可感知
- [ ] 从 Detach 拖回条内：恢复排序模式，可继续插入
- [ ] 影子不阻挡点击；拖拽中不误触关闭按钮
- [ ] 固定标签 / 最后一标签拖出行为与现网语义一致

### 性能与质量

- [ ] 拖动过程主线程无明显掉帧（典型 10～20 标签）
- [ ] `make browser` 无警告
- [ ] Reduce Motion 下无长距离位移动效

### 非目标回归

- [ ] 单击选中、双击关闭、右键菜单、溢菜单不受影响
- [ ] 未拖出时窗口内排序与升级前一致

---

## 9. 分阶段落地（供开发计划引用）

| 阶段 | 内容 |
|------|------|
| **DG-0** | GhostController + 截图影子跟手；条内藏源标签；松手无动画亦可 |
| **DG-1** | InStrip / Detach 双样式；条内有效区判定；松手吸附动画 |
| **DG-2** | 与新窗口创建联动的落点动画；Reduce Motion；打磨角标与阴影参数 |
| **DG-3** |（可选）Esc 取消；跨窗拖入 |

---

## 10. 参考体验（对齐而非照搬）

| 产品 | 可借鉴 | 不照搬 |
|------|--------|--------|
| Safari | 条外即「独立」感、影子跟手 | 整页实时缩略预览 |
| Chrome | 拖出合拢、落点成新窗 | 多标签拖栈 |
| MeoBrowser | 真实 WebView 迁移（已有） | — |

---

## 11. 小结

用 **「截图影子跟手 + 源位占坑/合拢 + 条内/拖出双模式」**，在不改动 WebView 迁移正确性的前提下，把当前「实体夹紧在条内平移」升级为可感知的现代拖拽。首版聚焦 DG-0～DG-1；落点动画与无障碍为 DG-2。

**建议默认决策**：D1=离开标签条、D2=拖出合拢、D3=显示「新窗口」角标、D4/D5=延期。
