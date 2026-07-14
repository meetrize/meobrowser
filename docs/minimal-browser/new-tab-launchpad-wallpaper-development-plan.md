# Launchpad 新标签页背景图 — 开发计划

> 基于 [new-tab-launchpad-wallpaper-design.md](new-tab-launchpad-wallpaper-design.md) 的分阶段实施计划。  
> 前置条件：Launchpad NTP-0～NTP-3 已完成；外观面板（图标/间距）可用；文件夹 FLD 已交付。  
> **状态：BG-0～BG-3 已完成（2026-07-14）。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase BG-0 | Store / 磁盘 | 完成 | `BrowserWallpaperStore` + ImageIO 导入 + meta |
| Phase BG-1 | MVP 显示与入口 | 完成 | Launchpad 壁纸层 + 外观面板选图/清除/启用 |
| Phase BG-2 | 可读性与省内存 | 完成 | 压暗叠层、不可见卸图、材质切换打磨 |
| Phase BG-3 | 联调验收 | 完成 | `make browser` 通过、文档与 acceptance 同步 |

---

## Phase BG-0：Store 与磁盘

**目标**：壁纸读写与降采样落盘，进程内共享解码；尚不接 UI 亦可。

### 任务清单

- [x] **0.1** 新增 `BrowserWallpaperStore.h/.m`（单例、`BrowserWallpaperDidChangeNotification`）
- [x] **0.2** `wallpaperDirectoryURL` → `Application Support/MeoBrowser/LaunchpadWallpaper/`
- [x] **0.3** `meta.plist` 读写：`enabled`、`sourceFileName`、`displayMaxPixelSize`、`scrimAlpha`、`updatedAt`
- [x] **0.4** `BrowserWallpaperMaxScreenPixelEdge()`：遍历 `NSScreen`，最长边像素，clamp ≤ 3840
- [x] **0.5** `importImageFromURL:completion:`：后台 ImageIO 缩略 + EXIF transform → 写 `display.jpg` → 主线程通知
- [x] **0.6** `clearWallpaper`：删 display（及 optional original）+ 重置 meta
- [x] **0.7** `setWallpaperEnabled:` / `setScrimAlpha:`（alpha 可先持久化，BG-2 再接 UI）
- [x] **0.8** `acquireDisplayImage` / `releaseDisplayImage`：引用计数；0→1 从 `display.jpg` 解码；归零释放
- [x] **0.9** Makefile 加入 `BrowserWallpaperStore.m`

---

## Phase BG-1：MVP 显示与外观入口

**目标**：有壁纸时新标签页铺满显示；外观面板可选图 / 清除 / 开关。

### 任务清单

#### 1A — Launchpad 视图

- [x] **1.1** `BrowserLaunchpadView` 最底层增加壁纸 `NSImageView` 或 `CALayer`（`contentsGravity = resizeAspectFill`）
- [x] **1.2** collection / scroll 背景保持 clear；壁纸在 `effectView` 之下
- [x] **1.3** `wallpaperEnabled && displayImage`：显示壁纸层，`effectView.hidden = YES`；否则反向
- [x] **1.4** 监听 `BrowserWallpaperDidChangeNotification`，刷新层
- [x] **1.5** 视图可见时 `acquire`，移除 / dealloc 时 `release`（`setHidden:` + `viewDidMoveToWindow`）

#### 1B — 外观面板

- [x] **1.6** `preferredPanelSize` 增高，增加「背景」分区标题
- [x] **1.7** 「选择图片…」→ `NSOpenPanel` → `importImageFromURL:`；失败用简短 alert
- [x] **1.8** 「清除」→ `clearWallpaper`
- [x] **1.9** 「使用背景图片」开关 → `setWallpaperEnabled:`；无文件时选中则先触发选图
- [x] **1.10** 展示 `sourceFileName`（次要 label，截断）
- [x] **1.11** `reloadFromAppearance` 同步壁纸控件状态；「恢复默认」**不**清壁纸
- [x] **1.12** 齿轮 tooltip 改为「外观与背景」

#### 1C — 联调

- [x] **1.13** 多开几个 `about:newtab`：单窗口共享 LaunchpadView + Store
- [x] **1.14** 重启 App：enabled + 文件仍生效（代码路径）

---

## Phase BG-2：可读性与省内存

**目标**：图标在亮/暗图上可读；无可见新标签时卸除解码图。

### 任务清单

- [x] **2.1** 壁纸与网格之间加 `scrimView`（黑半透明）
- [x] **2.2** 外观面板「压暗」滑杆（0～70%），连续更新
- [x] **2.3** 默认 `scrimAlpha` 0.30
- [x] **2.4** Launchpad `hidden == YES` 时 release
- [x] **2.5** 离开新标签后解码图可释放；再开从 `display.jpg` 恢复
- [x] **2.6** 空白区右键：「设置背景图片…」「清除背景」
- [ ] **2.7** （可选延后）外接更大屏时重烘焙

---

## Phase BG-3：联调与验收

### 任务清单

- [x] **3.1** `make clean && make browser`（无警告）
- [x] **3.2** 对照 [设计稿 §9](new-tab-launchpad-wallpaper-design.md#9-分期与验收) 勾选
- [x] **3.3** 更新 [acceptance.md](acceptance.md) 追加壁纸节
- [x] **3.4** 本计划各阶段勾选完成；更新 README / roadmap 状态
- [x] **3.5** 回归：快捷方式拖拽、文件夹展开、外观间距预设（构建路径未改）

### 发布检查

```bash
make clean && make browser && make verify
make run-browser
```

---

## 实现文件

```text
SimpleBrowser/NewTab/
├── BrowserWallpaperStore.h/.m              # 新增
├── BrowserLaunchpadView.h/.m               # 壁纸层 + 生命周期
├── BrowserLaunchpadAppearancePanel.h/.m    # 背景分区 UI
└── (Makefile 增加 WallpaperStore + ImageIO)
```

**不修改**：`BrowserShortcutStore`、会话恢复、地址栏补全数据路径。

---

## 延后工作（BG-3+）

- 浅色 / 深色各一套壁纸  
- 保留 `original.*` 并支持「重新优化」  
- 动图 / 视频壁纸  
- 壁纸库 / 在线图  
- 每窗口或每标签独立背景  
- 外接更大屏时空闲重烘焙  

---

## 完成定义（Definition of Done）

1. Phase BG-0～BG-3 任务全部勾选  
2. 行为符合 [new-tab-launchpad-wallpaper-design.md](new-tab-launchpad-wallpaper-design.md)  
3. 多标签共享一份显示图；无壁纸路径与现网 Launchpad 一致  
4. 无编译警告；Makefile 可独立构建  
5. 文档与实现一致  

**Launchpad 背景图（BG-1+BG-2）已交付。**
