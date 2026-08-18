# 下载目录与面板入口 — 开发计划

> 基于 [download-folder-settings-design.md](download-folder-settings-design.md)。  
> 前置：下载 V1.1 已就绪（`BrowserDownloadManager` / `BrowserDownloadPanel` / 设置窗）。  
> 状态：**DF-0 / DF-1 / DF-2 已实现**（2026-08-18）；手测见下方清单。  
> 关联：[download-design.md](download-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md) §3.8

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 表头右簇顺序 | 「清空已完成」→ `folder` → `gearshape` |
| 空态 | 两图标仍显示且可点；「清空已完成」仍仅禁用、不隐藏 |
| 打开目录 | `NSWorkspace openURL:` 打开**有效目录**；先 `dismissPanel` |
| 齿轮 | dismiss → 设置窗 → **强制「常规」Tab** |
| 菜单「设置」 | 不切 Tab |
| 自定义目录存储 | UserDefaults POSIX 路径；非沙盒，不做 bookmark |
| 失效目录 | 不自动清空；`effectiveDirectoryURL` 回退系统「下载」 |
| 进行中任务 | 不改道 |
| 路径 UI | 只读 label +「选择…」+「恢复默认」；无 `SBTextField` |
| 「下载前询问」 | **本版不做** |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| Phase DF-0 | 偏好与落盘 | 0.5 日 | `BrowserDownloadPreferences`；Manager 写入有效目录 |
| Phase DF-1 | 设置 UI | 0.5 日 | 常规「下载位置」；稳定 Tab id；按 Tab 打开设置 |
| Phase DF-2 | 面板表头 | 0.5 日 | 文件夹 + 齿轮；空态手测 |

**首版交付：DF-0 + DF-1 + DF-2（约 1～1.5 人日）。**

建议节奏：先 DF-0 保证改目录真正生效，再 DF-1 能改，最后 DF-2 补入口。

---

## Phase DF-0：偏好与落盘

**目标**：未改设置时行为与今日完全一致；API 已走「有效目录」，为设置/表头打底。

### 任务清单

#### 0A — Preferences

- [x] **0.1** 新建 `SimpleBrowser/Downloads/BrowserDownloadPreferences.h/.m`
  - `+sharedPreferences`（对齐 `BrowserDeveloperPreferences`）
  - `customDirectoryURL` / `effectiveDirectoryURL` / `usesCustomDirectory` / `customDirectoryIsReachable`
  - `resetToSystemDownloadsDirectory`
  - `displayPath`
  - key：`MeoBrowserDownloadDirectoryPath`
  - 变更发 `BrowserDownloadPreferencesDidChangeNotification`
- [x] **0.2** `effectiveDirectoryURL`：自定义可达且可写则用之；否则 `URLForDirectory:NSDownloadsDirectory create:YES`

#### 0B — Manager

- [x] **0.3** `UniqueDestinationURLInDownloads` 改为使用 `effectiveDirectoryURL`（所有现有调用点：WK destination、blob/JS 回退、data URL 等）
- [x] **0.4** 公开 `-downloadDirectoryURL`、`-revealDownloadDirectoryInFinder`（失败返回 NO）
- [x] **0.5** 头文件注释：落盘目录来自偏好，不再写死「写入 Downloads」

#### 0C — 构建

- [x] **0.6** Makefile：加入 `BrowserDownloadPreferences.m`（已有 `-ISimpleBrowser` / Downloads 则只加源）
- [x] **0.7** `make browser` 通过

#### 0D — 验收 DF-0

- [ ] **0.8** 不设自定义路径时，文件仍落到 `~/Downloads`，重名规则不变
- [ ] **0.9**（开发者临时写 UserDefaults 或单测式手改）设置合法自定义路径后，**新**下载出现在该目录
- [ ] **0.10** 改路径时已有进行中任务仍写原路径

---

## Phase DF-1：设置窗口

**目标**：用户可在设置「常规」里选择 / 恢复下载目录。

### 任务清单

#### 1A — Tab 标识

- [x] **1.1** `addTabNamed:` 增加稳定 `identifier`（`general` / `sync` / `keyboard` / `privacy` / `developer`）
- [x] **1.2** `BrowserSettingsWindowController` 公开 `-selectTabWithIdentifier:`
- [x] **1.3** `AppDelegate`：`-showBrowserSettingsSelectingTabIdentifier:`（内部 show + select）；现有 `-showBrowserSettings:` 行为不变（不切 Tab）

#### 1B — 常规页 UI

- [x] **1.4** 「默认浏览器」下方增加「下载位置」：caption、只读路径、选择…、恢复默认、hint
- [x] **1.5** `showWindow:` / 偏好通知时刷新路径、警告文案、「恢复默认」enable
- [x] **1.6** 「选择…」→ `NSOpenPanel`（仅目录、可新建）sheet → `customDirectoryURL = panel.URL`
- [x] **1.7** 「恢复默认」→ `resetToSystemDownloadsDirectory`
- [x] **1.8** 自定义不可达/不可写：hint 说明将回退系统「下载」

#### 1C — 验收 DF-1

- [ ] **1.9** 菜单打开设置，切到其它 Tab 再关，再开仍停在该 Tab
- [ ] **1.10** `showBrowserSettingsSelectingTabIdentifier:@"general"` 一定停在常规且能看到下载位置
- [ ] **1.11** 选新目录后下载文件出现在该处；恢复默认后回到 `~/Downloads`
- [ ] **1.12** OpenPanel 取消不改路径
- [x] **1.13** 无新增可编辑 `NSTextField` / 未走 SBKit 的输入框

---

## Phase DF-2：面板表头

**目标**：空态与有列表时都能打开目录、打开设置。

### 任务清单

#### 2A — 表头布局

- [x] **2.1** `BrowserDownloadPanel` 增加 `folderButton`、`settingsButton`（规格对齐行内 28×28）
- [x] **2.2** 约束：清空按钮 trailing 接到 folder 左侧；gear trailing = 面板 -10；与标题垂直居中
- [x] **2.3** `reloadFromManager`：**不要**按 `items.count` 隐藏两图标；清空按钮 enable 逻辑保持现状
- [x] **2.4** Accessibility / tooltip：打开下载文件夹、下载设置…

#### 2B — 动作与 delegate

- [x] **2.5** Protocol 增加 `-downloadPanelDidRequestSettings:`（或由 WindowController 直接转 AppDelegate）
- [x] **2.6** folder：`dismissPanel` → `revealDownloadDirectoryInFinder`；失败则对 `ownerWindow` Alert（可带「打开设置」）
- [x] **2.7** gear：`dismissPanel` → `showBrowserSettingsSelectingTabIdentifier:@"general"`
- [x] **2.8** `BrowserWindowController` 实现新 delegate；注意与现有 close delegate 并存

#### 2C — 验收 DF-2

- [ ] **2.9** 对照设计 §7 清单手测
- [ ] **2.10** 点齿轮：浮层关掉，设置在常规；Esc / 点外部关面板仍正常
- [ ] **2.11** 点文件夹：Finder 打开有效目录；应用切到 Finder 后浮层已关
- [x] **2.12** 更新 [download-design.md](download-design.md) §2.3 表头描述，V2 去掉「自定义目录」
- [x] **2.13** `make browser` 通过（`make verify` 仍依赖 SimpleWindow ibtool，与本功能无关）

---

## 关键改动面（预期）

| 文件 / 目录 | 变更 |
|-------------|------|
| `SimpleBrowser/Downloads/BrowserDownloadPreferences.*` | **新建** |
| `SimpleBrowser/Downloads/BrowserDownloadManager.*` | 有效目录落盘、reveal 目录 |
| `SimpleBrowser/Downloads/BrowserDownloadPanel.*` | 表头按钮、delegate |
| `SimpleBrowser/BrowserWindowController.m` | gear / 失败 Alert |
| `SimpleBrowser/BrowserSettingsWindowController.*` | 常规区块、Tab id |
| `SimpleBrowser/AppDelegate.*` | 按 Tab 打开设置 |
| `Makefile` | 新 `.m` |
| `docs/minimal-browser/download-design.md` | V1.2 表头 / 落盘；V2 收缩 |
| `docs/minimal-browser/professional-features-roadmap.md` | §3.8 补一行自定义目录 |
| `docs/README.md` | 索引本方案与本计划 |

---

## 测试清单（手测）

| # | 步骤 | 期望 |
|---|------|------|
| 1 | 新装/无自定义，⌘J，列表空 | 表头有文件夹与齿轮；清空禁用 |
| 2 | 点文件夹 | Finder 打开 `~/Downloads`；浮层关闭 |
| 3 | 下一普通附件 | 文件在 `~/Downloads`，重名 `-1` |
| 4 | 点齿轮 | 设置打开且为「常规」，可见下载位置 `~/Downloads` |
| 5 | 选择… 选 `~/Desktop/MeoDL`，下一附件 | 文件在 `MeoDL` |
| 6 | 开始一个大文件，下载中再改目录 | 该文件仍进旧目录；下一个进新目录 |
| 7 | 清空已完成后再点文件夹 | 仍打开**当前有效目录**（不是空操作） |
| 8 | 恢复默认后再下 | 回到 `~/Downloads` |
| 9 | Finder 删掉自定义目录后再下 | 文件进系统「下载」；设置有警告 |
| 10 | 菜单打开设置，停在「隐私」；再从齿轮进 | 变为「常规」（菜单路径下次仍可停在上次 Tab） |
| 11 | Esc / 点页面空白 | 浮层关闭，与 V1 一致 |
| 12 | 多窗口各开面板 | 同一全局目录；改设置两边生效 |

---

## 风险与回滚

| 风险 | 缓解 / 回滚 |
|------|-------------|
| 表头变挤，「清空已完成」被截断 | 略减按钮间距；必要时清空改用 `trash` 图标 + tooltip |
| 浮层 dismiss 与设置 key 抢时序 | 动作里**先** dismiss 再 show；不要依赖 ResignKey 顺带关 |
| 自定义盘弹出后不可达 | 回退系统「下载」，不中断浏览 |
| 误把 OpenPanel 挂在非 key 浮层 | 选目录只放设置窗 sheet |
| 日后沙盒 | Preferences 换 bookmark；本版路径存储集中一处便于替换 |

回滚粒度：可先撤 DF-2 表头按钮，保留偏好+设置；再撤 DF-1 UI，保留默认 `~/Downloads` 落盘。

---

## 完成定义（DoD）

- [x] DF-0～DF-2 代码任务清单全部勾选
- [ ] 设计 §7 验收标准手测
- [x] [download-design.md](download-design.md) 表头/落盘与 V2 展望已同步
- [x] 路线图 §3.8 标明可自定义下载目录
- [x] 无新增业务输入框（路径只读）；无「下载前询问」
