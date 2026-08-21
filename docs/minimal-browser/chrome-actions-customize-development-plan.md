# 标签栏 Chrome 动作区定制 — 开发计划

> 基于 [chrome-actions-customize-design.md](chrome-actions-customize-design.md)（含自动滚 / 速度 / 窗口缩放图标化、菜单单一列表）。  
> 前置：ChromeActions（CA）、⋯ 更多菜单（MO）、地址栏 ActionGroup 可参考。  
> 状态：**已完成（CP-0～CP-3）**  
> Cursor 计划：`.cursor/plans/chrome-actions-customize.plan.md`

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| Catalog | 摸鱼、透明、精简、置顶、**自动滚动**、**滚动速度**、**窗口缩放**（+ 固定 ⋯） |
| 菜单 | **单一列表**七项 + 图钉；**不分两段** |
| 默认条上 | **七开关/动作 + ⋯**（hidden 默认空） |
| 可拖 | 除 ⋯ 外全部可见图标 |
| 拖到 ⋯ | 写入 hidden |
| 持久化 | App 级 Order + Hidden；多窗通知 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase CP-0 | Catalog 扩项 + Layout Store + 按偏好渲染 | **完成** | 七项目录；默认全部可见；条上渲染正确 |
| Phase CP-1 | 新三项条上行为 + 拖拽改序/溢出 | **完成** | wire 自动滚/速度/缩放；拖拽与 drop-⋯ |
| Phase CP-2 | 单一图钉菜单 | **完成** | ⋯ 仅统一列表；无下半区 |
| Phase CP-3 | 态同步、多窗、打磨验收 | **完成** | on/标题/全屏禁用；通知；文档 |

**交付：CP-0～CP-3。** 预估约 2.5～4 人日。

---

## Phase CP-0：Catalog + Store + 渲染

**目标**：数据与目录就绪；默认 UI 与现网一致；尚可无拖拽。

### 任务

#### 0A — Catalog

1. `BrowserChromeActionItem` 增加常量：  
   - `BrowserChromeActionAutoScrollID`  
   - `BrowserChromeActionScrollSpeedID`  
   - `BrowserChromeActionWindowLayoutID`  
2. `+catalogItemsExcludingMoreMenu`（或扩展 `defaultItems` 逻辑）：七项元数据（symbol / toolTip / toggles）。  
3. `moreMenu` 仍由 view 拼在可见列表末尾。

#### 0B — LayoutStore

4. `BrowserChromeActionLayoutStore`：order / hidden API + 通知。  
5. 缺省：order=七项默认序；hidden=空（全部可见）。  
6. 迁移：旧四项 order 时追加三 id；新 id 不强制进 hidden。

#### 0C — 渲染

7. View：`visible = filter(!hidden) + moreMenu` → `reloadWithItems:`。  
8. WC：reload 后 `wireChromeActionButtons`（本阶段旧四项 + ⋯ 必绑；新三项可先绑好 selector）。  
9. `make browser`；手测默认仍四图标。

### 验收

- [x] 冷启动条上：七图标 + ⋯（含自动滚/速度/缩放）  
- [x] Defaults 中 order 含七项；hidden 默认空或不存在  
- [x] 手动把某 id 写入 hidden 并 reload → 条上少该图标  
- [x] `make browser` 通过  

---

## Phase CP-1：新三项行为 + 拖拽

**目标**：钉在条上的新图标可用；完成 F1/F2。

### 任务

#### 1A — 行为 wire 与态

1. `autoScroll` → toggle 控制器；`setOn:` 随 `enabled` / `didDisableHandler` 更新。  
2. `scrollSpeed` → `openAutoScrollSpeedSettings:`。  
3. `windowLayout` → `toggleWindowLayoutZoom…`；小窗=on；切换后刷新 symbol/tooltip；全屏 `button.enabled=NO`。  
4. 统一入口可选：`-performChromeActionForItemID:` 供菜单与按钮共用。

#### 1B — 拖拽

5. 阈值拖拽改序；可见子序列写回完整 order。  
6. drop 到 ⋯ → hidden。  
7. 抑制误 click；更新 `preferredWidth` / strip 约束。  
8. 参考 AddressBar ActionGroup，复制适配。

### 验收

- [x] 钉上自动滚后可开关；打断后图标关态正确  
- [x] 钉上滚动速度，点击进设置滑杆  
- [x] 钉上窗口缩放，可大小窗切换；全屏按钮灰  
- [x] 任意可见图标可拖改序、可拖进 ⋯  
- [x] 微移点击不误拖  
- [x] `make browser` 通过  

---

## Phase CP-2：单一图钉菜单

**目标**：⋯ 菜单 = 七行自定义 view；删除原分段菜单代码。

### 任务

1. `BrowserChromeActionMenuRowView`：标题（可勾选）+ 图钉。  
2. `showChromeMoreMenu:` **只**按 `orderedIDs` 建行；**删除** separator 与手写自动滚/速度/大小窗 `NSMenuItem`。  
3. 标题 → `performChromeAction…`；图钉 → Store hidden 翻转 + 刷新条 + 更新 row。  
4. 打开菜单时：  
   - `autoScroll` 勾选 = controller.enabled  
   - `windowLayout` 标题 = 放大/缩小文案；全屏禁用标题  
5. 菜单宽度足够显示图钉。

### 验收

- [x] 菜单恰好七项、无分段线  
- [x] 每项有图钉；已在条上为取消固定、已隐藏为可固定  
- [x] 点「自动滚动」文字与钉在条上点击等效  
- [x] 图钉钉上/移除后条上即时变化  
- [x] `make browser` 通过  

---

## Phase CP-3：多窗、打磨、验收

### 任务

1. 观察 `LayoutDidChangeNotification`，多窗 reload + rewire。  
2. a11y：图钉/标题 label。  
3. 脚注更新：`tab-strip-chrome-actions-design.md`、`chrome-more-menu-design.md`（指向统一 Catalog）。  
4. design §8 与本计划勾选。  
5. 全量手测。

### 验收

- [x] 两窗布局同步  
- [x] 设计 §8 全过  
- [x] `make browser` 通过  

---

## 手测清单

1. 默认条上七图标 + ⋯  
2. ⋯ 菜单七项单一列表，均有图钉  
3. 「自动滚动」可开关；拖到 ⋯ 再藏；图钉钉回  
4. 「滚动速度…」点击打开设置  
5. 「窗口缩小」切换大小窗；全屏禁用执行  
6. 拖拽交换任意两项，重启保持  
7. 取消固定至仅 ⋯，再从菜单钉回  
8. 短按 vs 拖拽手势正确  
9. 第二窗口同步  
10. 精简/透明显条下仍可用  

---

## 关键文件（预期）

| 路径 | 说明 |
|------|------|
| `ChromeActions/BrowserChromeActionItem.*` | 三新 id + catalog |
| `ChromeActions/BrowserChromeActionLayoutStore.*` | **新建** |
| `ChromeActions/BrowserChromeActionMenuRowView.*` | **新建** |
| `ChromeActions/BrowserTabStripChromeActionsView.*` | layout + 拖拽 |
| `BrowserWindowController.m` | 统一菜单、三项 wire、态同步 |
| `Makefile` | 新源 |
| `docs/minimal-browser/chrome-actions-customize-*.md` | 本文与设计 |
| `docs/minimal-browser/chrome-more-menu-design.md` | 结构脚注 |
| `docs/minimal-browser/tab-strip-chrome-actions-design.md` | 拖拽脚注 |

---

## 实现顺序

```
CP-0  七项 Catalog + Store + 默认全部可见渲染
CP-1  新三项行为 + 拖拽/溢出
CP-2  单一图钉菜单（去掉两段式）
CP-3  多窗 / a11y / 文档验收
```

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 默认露出过多图标 | 用户可拖进 ⋯；后续可做窄窗自动溢出 |
| 自定义 menu view | 最小行高；备选降级为无行内图钉 |
| windowLayout 动态标题 | 弹菜单前与 layoutMode 变更时刷新 |
| autoScroll 打断漏刷新 | `didDisableHandler` 内 `setOn:NO` |
| order 写回错误 | 只重排可见子序列；打日志校验 |

---

## 完成定义（DoD）

- 设计 §8 全勾选  
- CP-0～CP-3 任务勾选  
- 不回归：摸鱼 / 透明 / 精简 / 置顶 / 自动滚 / 改速 / 大小窗  
- 菜单无两段、三项可钉上条上使用  
