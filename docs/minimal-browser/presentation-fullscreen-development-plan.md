# 网页全屏（Chrome 式 F11）— 开发计划

> 基于 [presentation-fullscreen-design.md](presentation-fullscreen-design.md) 的分阶段实施计划。  
> 前置条件：多标签 / `BrowserWindowController` chrome 显隐管线、`BrowserTabStripView` titlebar accessory、HTML5 元素全屏修复逻辑已就绪。  
> 状态：**待开发**

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 快捷键 | **F11** 切换；**Esc** 退出网页全屏 |
| 平台 | macOS 原生 `[window toggleFullScreen:nil]` + 强制藏壳 |
| 可用条件 | 当前标签有 `WKWebView` 且非 NTP |
| 透明 / 摸鱼 | 进入前强制关；退出 **不** 自动恢复 |
| 精简 / 侧栏 | 快照；退出 **恢复** |
| 系统绿键全屏 | 不自动藏壳（仅 F11/菜单路径藏壳） |
| Session | **不** 持久化全屏态 |
| Chrome 图标 | V1 不做（FS-1 可选） |

---

## 总览

| 阶段 | 名称 | 产出 |
|------|------|------|
| Phase FS-0 | 骨架与快捷键 | Controller + 状态布尔 + F11/Esc + 菜单（可先仅 log） |
| Phase FS-1 | 藏壳与进出场 | toggleFullScreen + 隐藏全部 chrome + WebView 铺满 |
| Phase FS-2 | 快照还原与冲突模式 | 精简/侧栏/Peek 恢复；透明/摸鱼/元素全屏/绿键退出 |
| Phase FS-3 | 验收与文档 | 手测清单、Makefile、设计文档状态更新 |

**首版交付目标：FS-0 + FS-1 + FS-2 + FS-3。**

预估工作量：**2～3 人日**（含手测与边角修复）。

---

## Phase FS-0：骨架与快捷键

**目标**：F11 / 菜单可 toggle 布尔状态；尚未藏壳也可验证快捷键不与其他 monitor 冲突。

### 任务清单

1. 新建 `SimpleBrowser/PresentationFullscreen/`  
   - `BrowserPresentationFullscreenController`：`windowController` weak 引用  
   - `@property (nonatomic, assign, readonly) BOOL active`  
   - `- (BOOL)canEnter;` `- (void)enter;` `- (void)exit;` `- (void)toggle;`  
2. `BrowserWindowController` 持有 controller；转发 `togglePresentationFullscreen:`  
3. `BrowserMenus.m`：「查看 → 进入全屏」`keyEquivalent:@"f11"`（注意 macOS 菜单 F11 写法）  
4. 扩展 `installReloadKeyMonitor` **或** 独立 monitor：  
   - F11 → `toggle`（仅 keyWindow）  
   - Esc → 若 `active` 则 `exit` 并 `return nil`  
5. `validateMenuItem:`：标题在「进入全屏」/「退出全屏」间切换；NTP 时 disable  
6. `Makefile` 加入新 `.m`；`make browser`  

### 验收

- [ ] F11 切换菜单勾选态（或内部 `active`）  
- [ ] NTP 下 F11 无效、菜单灰显  
- [ ] 不影响 F5 刷新、Esc 停止加载（非全屏时）  

---

## Phase FS-1：藏壳与进出场

**目标**：`active == YES` 时用户只见网页；系统进入全屏 Space。

### 任务清单

1. **`applyPresentationChromeHidden:`**（Controller 或 WC）  
   - 隐藏：`tabStripAccessoryRoot`、`toolbar`、交通灯、侧栏、Launchpad、Find、TabOverview、loadingProgress、证书/错误 overlay  
   - `tabStripAccessoryHeightConstraint.constant = 0`  
2. **`enter` 流程**  
   - Guard + `presentationFullscreenActive = YES`  
   - `applyPresentationChromeHidden:YES`  
   - `[window toggleFullScreen:nil]`  
3. **窗口通知**（WC 已有 stub，扩展）  
   - `windowDidEnterFullScreen:`：若 `active`，layout WebView 贴边；`pinWebViewLayoutInSuperview`  
   - `windowDidExitFullScreen:`：若曾 `active`，走 `exit` 清理  
4. **`exit` 流程**  
   - 若仍 fullScreen → `toggleFullScreen`  
   - `applyPresentationChromeHidden:NO`  
   - `presentationFullscreenActive = NO`  
5. **轻量 layout  helper**  
   - `layoutSelectedWebViewForPresentationFullscreen`  
   - **禁止** 调用完整 `refreshTabsUI`（避免 detach 全标签）  
6. 手测：YouTube / 普通页 F11 → 仅网页  

### 验收

- [ ] 全屏无标签条、地址栏、交通灯、侧栏  
- [ ] WebView 无异常留白或裁切  
- [ ] 退出后 chrome 可见（尚未要求精简/侧栏完美恢复）  

---

## Phase FS-2：快照还原与冲突模式

**目标**：退出后与进入前一致；与现有模式不打架。

### 任务清单

1. **`BrowserPresentationFullscreenSnapshot`**  
   - capture：`compactMode`、`addressBarPeekActive`、各 sidebar visible、tabOverview、findBar  
   - restore + `applyChromeVisibilityForCurrentMode`  
2. **进入前冲突处理**  
   - `setTransparentModeEnabled:NO`、`setAfkModeEnabled:NO`（复用 `windowWillEnterFullScreen` 逻辑或集中调用）  
   - dismiss tab overview；hide sidebars  
3. **HTML5 元素全屏**  
   - `canEnter` / F11：若 `webViewIsInElementFullscreen` → 先退出元素全屏或 ignore（定稿：**先退出元素全屏再允许 Presentation**）  
   - Presentation 期间 `refreshTabsUI` / attach 路径检查 `presentationFullscreenActive`  
4. **系统退出全屏**  
   - 绿键 / ⌃⌘F / 手势：`windowDidExitFullScreen` 必须清 `active` 并 restore  
5. **绿键全屏（非 Presentation）**  
   - 不设置 `active`；保持今日行为（仅关透明/摸鱼）  
6. **Sheet / 模态**  
   - 有 sheet 时 `canEnter == NO`  

### 验收

- [ ] 精简 + 开历史侧栏 → F11 → 退出 → 侧栏与精简恢复  
- [ ] 透明开 → F11 → 透明关；退出后不自动开透明  
- [ ] 视频元素全屏后再 F11 不 crash  
- [ ] Presentation 中系统退出全屏 → 不残留 hidden  
- [ ] 双窗口 F11 只影响前台窗  

---

## Phase FS-3：验收与文档

### 任务清单

1. 按设计文档 §8 完整手测  
2. 更新 `presentation-fullscreen-design.md` 状态为「已完成」  
3. （可选）`BrowserMenus` / 关于页补充 F11 说明一句  
4. （可选 FS-1.5）Chrome 动作区全屏图标  

### 回归关注

- 透明模式 TH 自动藏壳  
- 标签条 accessory 高度 / 交通灯定位  
- Element fullscreen 黑屏修复定时器  
- 新标签页 Launchpad 性能路径  

---

## 建议实施顺序（单日拆分）

| 日 | 内容 |
|----|------|
| D1 上午 | FS-0：Controller 骨架 + F11/Esc + 菜单 |
| D1 下午 | FS-1：藏壳 + toggleFullScreen + WebView layout |
| D2 上午 | FS-2：快照 + 透明/摸鱼/元素全屏/系统退出 |
| D2 下午 | FS-3：手测 + 边角 + 文档 |

---

## 依赖与并行

- **无** 后端 / 数据库依赖  
- 可与 Launchpad 性能优化并行，但 FS-1 会改 `refreshTabsUI` 分支，合并时注意冲突  
- 建议在 `BrowserWindowController` 的 `windowWillEnterFullScreen:` 中 **不要** 重复关透明/摸鱼——抽成 `- (void)prepareForNativeFullScreenTransition` 供 Presentation 与绿键共用  

---

## 测试计划（摘要）

| # | 步骤 | 期望 |
|---|------|------|
| 1 | 打开任意 https 页，F11 | 仅网页 |
| 2 | 再 F11 | 恢复原布局 |
| 3 | F11 后 Esc | 退出全屏 |
| 4 | 新标签页 F11 | 无动作 |
| 5 | 精简 + 侧栏，F11 → 退出 | 精简与侧栏恢复 |
| 6 | 透明开，F11 | 透明关，全屏正常 |
| 7 | 全屏播 YouTube 再点播放器全屏 | 元素全屏正常 |
| 8 | 两窗口，后台窗 F11 | 无反应；前台窗正常 |
