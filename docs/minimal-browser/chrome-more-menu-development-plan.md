# 标签栏「更多」菜单 — 开发计划

> 基于 [chrome-more-menu-design.md](chrome-more-menu-design.md)。  
> 前置：ChromeActions、透明模式、设置窗常规页。  
> 状态：**MO-0～MO-3 已完成**  
> Cursor 计划：[.cursor/plans/chrome-more-menu.plan.md](../../.cursor/plans/chrome-more-menu.plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 入口 | 置顶右侧 ⋯ 菜单 |
| 自动滚 | 选中标签主 frame；到底停；滚轮打断；速度设置即时 |
| 大小窗 | free/large/small；App 级预设；小窗含透明；出小窗恢复透明快照 |
| 全屏 | 禁用大小窗项 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase MO-0 | ⋯ 入口与菜单骨架 | 完成 | 图标 + 空菜单/占位项 |
| Phase MO-1 | 自动滚动 + 设置滑杆 | 完成 | 启停、速度、打断、设置即时 |
| Phase MO-2 | 大窗 / 小窗预设 | 完成 | 模式切换、读写预设、透明快照 |
| Phase MO-3 | 打磨与验收 | 完成 | 全屏灰、多窗偏移、文档勾选 |

**交付：MO-0～MO-3。**

---

## Phase MO-0：⋯ 入口

### 任务

1. `BrowserChromeActionMoreMenuID`；`defaultItems` 插到置顶后  
2. Symbol `ellipsis`；**非 toggles**（或 toggles=NO）  
3. WC：`showChromeMoreMenu:` → 按钮下方 `popUpStatusItemMenu` / `NSMenu popUpMenuPositioningItem`  
4. 菜单占位：自动滚动、大窗口、小窗口（可先无逻辑）  
5. `make browser`  

### 验收

- [ ] 顺序：… 置顶 ⋯  
- [ ] 点击弹出菜单  

---

## Phase MO-1：自动滚动

### 任务

1. `BrowserAutoScrollPreferences`（speed）+ 通知  
2. `BrowserAutoScrollController`（挂 WC）：注入/启停、`setSpeed`、选中标签变更停、导航停  
3. JS：rAF 向下滚；触底 → 消息停；`wheel` → 消息打断  
4. 设置常规页滑杆；改值发通知 → 滚动中即时 `speed`  
5. 菜单勾选绑定 `autoScrollEnabled`  
6. `make browser`  

### 验收

- [ ] 长页自动下滚；到底停勾选  
- [ ] 滚轮打断  
- [ ] 滑杆改速立即变  

---

## Phase MO-2：大小窗

### 任务

1. `BrowserWindowLayoutPresetStore`：large/small frame、smallTransparent、initialized  
2. WC：`windowLayoutMode`；`enterLargeLayoutMode` / `enterSmallLayoutMode`  
3. 小窗：进前透明快照；首次初始 frame+开透明；有预设则套用  
4. 出小窗：恢复透明快照；进大窗套 large frame  
5. `windowDidMove`/`DidResize` debounce 写当前模式预设  
6. 恢复前 clamp 可见屏；第二小窗偏移  
7. 菜单互斥勾选  
8. `make browser`  

### 验收

- [ ] 大窗记住位置尺寸  
- [ ] 小窗首次透明+尺寸；再进恢复含透明  
- [ ] 出小窗透明恢复合理  

---

## Phase MO-3：打磨

### 任务

1. 全屏禁用大小窗菜单项  
2. 自动滚「滚动速度…」跳转设置（可选）  
3. design §7 勾选；README；Cursor plan 完成  

---

## 手测清单

1. ⋯ 菜单开自动滚 / 改速 / 打断 / 到底  
2. 大切小、小改位置后再进  
3. 小窗关透明再进仍不透明  
4. 小窗切大窗后透明恢复  
5. 全屏菜单灰  
6. 透明藏壳下移入再开 ⋯  

---

## 关键文件（预期）

| 路径 | 说明 |
|------|------|
| `ChromeActions/*` | more item |
| `AutoScroll/*` 或挂 TransparentMode 旁 | 滚动 |
| `WindowLayout/*` 或 `BrowserWindowLayoutPresetStore` | 预设 |
| `BrowserWindowController.*` | 菜单、模式 |
| `BrowserSettingsWindowController.*` | 滑杆 |
| `Makefile` | 新源 |

---

## 实现顺序

```
MO-0 ⋯ 菜单 → make browser
MO-1 自动滚 + 设置 → make browser
MO-2 大小窗预设 → make browser
MO-3 打磨文档
```
