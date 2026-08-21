# 摸鱼模式 — 开发计划

> 基于 [afk-mode-design.md](afk-mode-design.md) 的分阶段实施计划。  
> 前置条件：ChromeActions（CA-0～CA-2）、透明模式（TM-0～TM-2）、多窗口 session、`BrowserStatusItemController` 已就绪。  
> 状态：**AFK-0 / AFK-1 / AFK-2 已完成（首版交付）** · 需求已修订：**V1 不做点击穿透**  
> Cursor 计划：[.cursor/plans/afk-mode.plan.md](../../.cursor/plans/afk-mode.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 图标位置 | 标签条右侧，**透明左侧**：摸鱼 → 透明 → 精简 → 置顶 |
| 隐身 | **仅** `alphaValue=0` |
| 点击穿透 | **不做**（不改 `ignoresMouseEvents`） |
| 回入侦测 | 进程级（或每窗）全局 `NSEvent` 鼠标监视 + `window.frame` |
| 与透明 | 正交；隐身不关 `transparentMode` |
| 全屏 | 禁止新开；进全屏强制关摸鱼并现身 |
| Dock 激活 | V1 **不**强制现身 |
| Esc | 不退出摸鱼 |
| 持久化 | session 键 `afkMode` |
| Status Item | 增加进入/退出摸鱼（至少退出） |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase AFK-0 | 入口与状态骨架 | 完成 | Chrome 图标 + WC 布尔 + 菜单勾选；尚可不隐身 |
| Phase AFK-1 | 隐身 / 现身与全局监视 | 完成 | 移出 `alpha=0`、移入还原；与透明叠加 |
| Phase AFK-2 | Status Item、全屏、session、打磨 | 完成 | 出口完善、持久化、验收与文档勾选 |

**首版交付目标：AFK-0 + AFK-1 + AFK-2。**

---

## Phase AFK-0：入口与状态骨架

**目标**：图标与菜单可见、可 toggle；布尔进 WC；布局顺序正确。

### 任务清单

1. `BrowserChromeActionAfkModeID` + `defaultItems` 插入顺序最前（摸鱼）  
2. SF Symbol / tooltip / on 态  
3. `BrowserWindowController.afkModeEnabled` + `setAfkModeEnabled:`（先只改图标态）  
4. 「查看」菜单「摸鱼模式」+ `validateMenuItem`  
5. `Makefile` 若已有模块目录可先占位  
6. `make browser`；确认四图标排布与标签溢出无回归  

### 验收

- [ ] 顺序：摸鱼 → 透明 → 精简 → 置顶  
- [ ] 点击切换 on/off 视觉态  
- [ ] 菜单勾选同步  

---

## Phase AFK-1：隐身 / 现身与全局监视

**目标**：摸鱼开启后，移出仅视觉隐身，移入按原形态还原；**不**改点击模型。

### 任务清单

1. 新建 `SimpleBrowser/AfkMode/BrowserAfkModeController`  
   - 快照 `alphaValue`（**不要**快照/改写 `ignoresMouseEvents`）  
   - `concealWindow:` / `revealWindow:`  
   - `afkConcealed` 只读状态  
2. 全局鼠标监视（推荐 App 单例分发）  
   - `NSEventMaskMouseMoved`（+ 可选 Dragged）  
   - `NSMouseInRect([NSEvent mouseLocation], window.frame, NO)`  
   - **仅 inside 边沿变化**时切换  
3. `setAfkModeEnabled:YES` → Armed；若已在窗外 → 立即 Concealed  
4. `setAfkModeEnabled:NO` → reveal + 卸监视责任  
5. **不**调用 `setTransparentModeEnabled:`；隐身前后透明布尔不变  
6. 手测：纯普通窗；透明+摸鱼；置顶+摸鱼；确认未改 `ignoresMouseEvents`  
7. `make browser`  

### 验收

- [ ] 移出：看不见  
- [ ] 鼠标在窗外点其它 App：正常（落点不在本窗）  
- [ ] 移入：普通窗恢复完整 UI  
- [ ] 透明+摸鱼移入：仍是透明观感（无标签条）  
- [ ] 关摸鱼后移出不再隐藏  
- [ ] 摸鱼路径未设置 `ignoresMouseEvents=YES`  
- [ ] 鼠标移动无明显卡顿  

### 风险注意

- 摸鱼只碰 `alphaValue`，与透明模式窗口字段隔离  

---

## Phase AFK-2：Status Item、全屏、session、打磨

**目标**：隐身可退出、边界正确、可持久化、文档收尾。

### 任务清单

1. `BrowserStatusItemController` 菜单：退出/进入摸鱼（作用域对齐透明：优先 key 窗）  
2. 全屏：`setAfkModeEnabled:YES` 时若已全屏则拒绝；`windowDidEnterFullScreen` 强制关摸鱼并 reveal  
3. Session：`BrowserWindowSessionAfkModeKey` 读写；恢复时机与透明类似（UI 就绪后）  
4. 窗关闭 / WC dealloc：卸监视、防野指针  
5. 可选：进出 Concealed 30～50ms 去抖（若手测抖边再加）  
6. 按 design §9 验收勾选；更新 design/plan 状态与 `docs/README.md`  

### 验收

- [ ] 隐身时菜单栏可关摸鱼并现身  
- [ ] 全屏无法开摸鱼；摸鱼中进全屏会关闭摸鱼  
- [ ] 多窗重启后 afk 状态按 session 恢复  
- [ ] 文档状态改为已完成  

---

## 手测清单（合并）

1. 仅摸鱼：移出隐、移入现  
2. 先透明再摸鱼 / 先摸鱼再透明：移入保持透明  
3. 摸鱼+置顶：现身仍置顶  
4. 摸鱼+精简：现身仍精简  
5. 关摸鱼、Status Item 退出、全屏拦截  
6. 两窗分别开关互不干扰  
7. 标签拖拽 / 透明右键拖窗 / 地址栏在非隐身时无回归  
8. 确认实现中无 `ignoresMouseEvents` 摸鱼相关赋值  

---

## 性能约束

- 无 timer 轮询鼠标  
- Global monitor 仅摸鱼开启期间有效（进程级一份优先）  
- 回调禁止 JS 注入、禁止重布局整窗 chrome  
- 状态切换幂等（重复 conceal/reveal 无闪烁）  

---

## 实现顺序建议（Cursor）

```
AFK-0 入口 → make browser
AFK-1 Controller + monitor + alpha conceal/reveal → make browser + 手测透明叠加
AFK-2 Status Item + 全屏 + session + 文档 → 验收勾选
```
