# 透明模式 Chrome 修订 — 开发计划

> 基于 [transparent-mode-chrome-revision-design.md](transparent-mode-chrome-revision-design.md)。  
> 前置：TM-0～TM-2、精简模式、ChromeActions、摸鱼（AFK）已就绪。  
> 状态：**TC-0 / TC-1 / TC-2 已完成**  
> Cursor 计划：[.cursor/plans/transparent-mode-chrome-revision.plan.md](../../.cursor/plans/transparent-mode-chrome-revision.plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 透明态标签条 | 显示（不卸 titlebar accessory） |
| 透明态交通灯 | 显示 |
| 透明态地址栏 | 跟随精简（+ Peek） |
| 透明态可切精简 | 是 |
| 透明+精简 Peek | 允许 |
| 侧栏 | 进入仍收起 |
| 页面/窗口透明 | 不变 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase TC-0 | 去掉「卸标签条 / 藏交通灯 / 强制藏栏」 | 完成 | 进入透明后条在、灯在；toolbar 跟精简 |
| Phase TC-1 | 精简联动与 Peek | 完成 | 透明态切换精简即时正确；⌘L Peek 可用 |
| Phase TC-2 | 退出路径清理、手测、文档 | 完成 | accessory 标志简化、验收、文档交叉更新 |

**交付目标：TC-0 + TC-1 + TC-2。**

---

## Phase TC-0：进入路径修正

**目标**：一进透明就能看到标签条；地址栏不再被透明强制关掉。

### 任务清单

1. `enterTransparentModeChrome`  
   - 删除（或旁路）`removeTitlebarAccessoryViewController`  
   - `transparentModeAccessoryRemoved` 不再置 YES（或整段删除）  
   - `setStandardWindowButtonsHidden:NO`（显示交通灯）  
   - 去掉裸 `self.toolbar.hidden = YES`  
   - 调用现有精简布局：`moveNavButtonsToTabStrip` / `ToToolbar` + `applyToolbarVisibilityForCompactState`（按当前 `compactModeEnabled`）  
2. `applyToolbarVisibilityForCompactState`：删除「透明则强制 hidden」短路  
3. `make browser`；手测：透明+非精简见条+地址栏；透明+精简见条不见地址栏  

### 验收

- [ ] 进入透明标签条在  
- [ ] 非精简有地址栏；精简无地址栏  
- [ ] 交通灯可见  

---

## Phase TC-1：精简联动与 Peek

**目标**：透明开着时切精简、Peek 与常态一致。

### 任务清单

1. 确认 `setCompactModeEnabled:` 在透明态完整执行（搬家 ◀▶、条高、toolbar 显隐）  
2. `beginAddressBarPeek`：去掉 `if (transparentModeEnabled) return`  
3. 手测：透明下开/关精简；精简下 ⌘L Peek → Return/Esc  
4. `make browser`  

### 验收

- [ ] 透明态开关精简，地址栏与 ◀▶ 正确  
- [ ] 透明+精简 Peek 可用且收起后仍透明  

---

## Phase TC-2：退出清理与文档

**目标**：退出无脏状态；文档与验收对齐。

### 任务清单

1. `exitTransparentModeChrome`：若未卸 accessory，跳过「加回」；保留精简重放与窗口还原  
2. 全文搜 `transparentModeAccessoryRemoved` / `toolbar.hidden` / Peek 透明拦截，清残留  
3. （可选）标签条半透明底，仅当手测难读时再加  
4. 更新 `transparent-mode-design.md` 交叉说明「壳显隐以 chrome-revision 为准」  
5. 勾选 design §6 验收；更新本 plan / Cursor plan 状态  

### 验收

- [ ] 退出透明布局与样式正确  
- [ ] 摸鱼叠加无回归  
- [ ] 文档状态已更新  

---

## 手测清单（合并）

1. 非精简 → 透明：条 + 地址栏 + 灯  
2. 精简 → 透明：条 + 无地址栏 + 灯；◀▶ 在条左  
3. 透明中切精简开/关  
4. 透明+精简 ⌘L Peek  
5. 退出透明；再进再出  
6. 透明+摸鱼移出/移入  
7. Status Item 仍可退出透明  

---

## 关键文件（预期）

| 文件 | 改动 |
|------|------|
| `BrowserWindowController.m` | enter/exit、`applyToolbarVisibilityForCompactState`、Peek |
| （可选）标签条容器 | 半透明底 |
| 文档 | revision design/plan、原 transparent-mode-design 交叉引用、README |

---

## 实现顺序（Cursor）

```
TC-0 进入路径 + toolbar 规则 → make browser
TC-1 精简联动 + Peek → make browser
TC-2 退出清理 + 文档验收
```
