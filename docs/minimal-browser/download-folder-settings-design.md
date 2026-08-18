# 下载目录与面板入口 — 设计方案（V1.2）

> 目标：下载浮层**无论是否有列表**都能打开当前下载目录；并在设置中自定义该目录。仍默认静默落盘，不问单次路径。  
> 状态：**V1.2 已实现**（2026-08-18）  
> 开发计划：[download-folder-settings-development-plan.md](download-folder-settings-development-plan.md)  
> 关联：[download-design.md](download-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md) §3.8

---

## 1. 方案定位

### 1.1 产品一句话

下载面板表头常驻「打开下载文件夹」和「下载设置」；设置窗口「常规」页可改默认下载目录。**单次下载仍不问路径。**

### 1.2 痛点

| 用户场景 | 现状 | 本方案 |
|----------|------|--------|
| 列表已清空 / 从未下过文件，仍想打开 Downloads | 面板只有「暂无下载」，没有目录入口 | 表头文件夹按钮始终可用 |
| 想把附件落到项目目录 / 外置盘，而不是 `~/Downloads` | 写死系统「下载」文件夹 | 设置里选一次，之后静默写入该目录 |
| 从下载面板直达该项设置 | 只能走「MeoBrowser → 设置」再翻页 | 表头齿轮打开设置并落到「常规」 |

### 1.3 做什么 / 不做什么

| 做（V1.2） | 不做（明确边界） |
|------------|------------------|
| 面板表头**始终**显示「打开下载文件夹」 | 每次下载弹出 `NSSavePanel` /「下载前询问」 |
| 面板表头齿轮 → 现有设置窗口 | 独立「下载设置」小窗（避免两套设置） |
| 设置「常规」：显示路径、选择文件夹、恢复默认 | 新开「下载」Tab（本版仅一项设置） |
| 新下载写入用户选定目录；重名仍 `-1`、`-2`… | 进行中的任务改道到新目录 |
| 自定义目录失效时回退系统「下载」并提示 | 安全范围书签（当前非沙盒，见 §5.3） |
| | 永久下载历史、暂停续传、Android 端 |

### 1.4 设计原则

1. **工作流终点仍在 Finder**：表头打开的是**目录**；行内「显示」仍是**选中该文件**。  
2. **空态也完整**：清空列表不等于丢掉目录入口。  
3. **设置只有一处**：齿轮只是捷径，改目录只在 `BrowserSettingsWindowController`。  
4. **改目录只影响未来任务**：已开始的 `WKDownload` 保持原 `destinationURL`。  
5. **默认行为不变**：未设置时仍是 `NSDownloadsDirectory`（`~/Downloads`）。

---

## 2. 现状基线

| 项 | 现状 |
|----|------|
| 落盘目录 | `BrowserDownloadManager` 内 `UniqueDestinationURLInDownloads` 写死 `NSDownloadsDirectory` |
| 面板表头 | 左「下载」；右仅「清空已完成」（空列表时禁用） |
| 行内文件夹 | 进行中/完成且已有路径时，「在 Finder 中显示」该文件 |
| 设置窗 | `BrowserSettingsWindowController`：常规 / 云同步 / 键盘 / 隐私 / 开发者；无下载项 |
| 设置入口 | `AppDelegate showBrowserSettings:`；窗口复用，**记住上次 Tab** |
| 沙盒 | 未启用 App Sandbox（`MeoBrowser.entitlements` 仅 `web-browser`）→ 可存 POSIX 路径 |

V1 展望里「自定义目录」原标为 V2，本方案将其提前为 **V1.2**；「下载前询问」仍留 V2。

---

## 3. 交互设计

### 3.1 下载面板表头

面板宽度仍 360pt。表头右簇：**清空已完成（文案）→ 打开目录 → 设置**。

```
┌─────────────────────────────────────────────┐
│ 下载                    清空已完成  [📁] [⚙️] │
├─────────────────────────────────────────────┤
│  列表行 …                                    │
│  或 「暂无下载」                              │
└─────────────────────────────────────────────┘
```

| 控件 | SF Symbol | Tooltip | 可见 / 可用 |
|------|-----------|---------|-------------|
| 清空已完成 | （现有文案按钮） | — | 始终可见；无已完成/失败项时禁用（与现网一致） |
| 打开下载文件夹 | `folder` | 打开下载文件夹 | **始终可见、始终可点**（含空列表、已清空） |
| 下载设置 | `gearshape` | 下载设置… | **始终可见、始终可点** |

图标按钮规格对齐行内操作：无边框、28×28、`secondaryLabelColor` tint。

「清空已完成」不得因空态被隐藏，也不得挡住两个图标。标题「下载」保持左对齐。

### 3.2 打开下载文件夹

1. 解析 **有效目录**（§5.2）。  
2. **先关闭浮层**（浮层 `canBecomeKeyWindow == NO`，且会在应用失活时关掉）。  
3. `[[NSWorkspace sharedWorkspace] openURL:directoryURL]` 打开该文件夹（不选中某个文件）。  
4. 失败：对浏览器主窗口出 Alert「无法打开下载文件夹」+ 简短原因；可附「打开设置」按钮。

与行内「在 Finder 中显示」的区别：表头打开**目录本身**；行内 `activateFileViewerSelectingURLs:` 选中**该文件**。

### 3.3 齿轮 → 设置

1. 关闭下载浮层。  
2. `[AppDelegate showBrowserSettings:]` 显示现有设置窗口。  
3. **强制选中「常规」Tab**（窗口会复用并记住上次 Tab；从下载进来必须落到有「下载位置」的页）。  
4. 设置成为 key window，居中/前置逻辑与菜单「设置」相同。

从菜单打开设置：**不**强行切 Tab，保持用户上次停留页。

### 3.4 浮层关闭与点击穿透

现有：点面板外 / Esc / ⌘J / 应用失活 / 主窗失 key → 关面板。

| 操作 | 浮层 |
|------|------|
| 点文件夹 / 齿轮 | 主动 `dismissPanel`，再执行 Finder / 设置 |
| 点「清空已完成」 | 保持打开，刷新列表 |
| Finder 被激活 | 即使未主动 dismiss，现有 `DidResignActive` 也会关；仍建议主动 dismiss，避免时序毛刺 |
| 设置成为 key | 主窗会 ResignKey；必须先 dismiss，避免与 monitor 抢关闭 |

点击仍落在面板内时，现有 local mouse monitor 不关闭面板，按钮 action 可正常触发。

---

## 4. 设置窗口（常规）

在「常规」Tab、默认浏览器区块**之下**增加「下载位置」：

```
下载位置
[ ~/Downloads                          ]  [选择…]  [恢复默认]
将文件保存到此文件夹，不再询问。
```

| 控件 | 说明 |
|------|------|
| 路径展示 | **只读**标签（`NSTextField` label，中间截断）。**不是输入框**，不使用 `SBTextField` |
| 选择… | `NSOpenPanel`：只选目录、单选、可建新文件夹；sheet 挂在设置窗 |
| 恢复默认 | 清除自定义路径，回到系统「下载」；已是默认时禁用 |

选定后立刻写入偏好并发通知；**不**影响进行中的下载。

路径展示用 `stringByAbbreviatingWithTildeInPath`（`~/Downloads`、`~/Projects/dl`）。

自定义目录存在但不可写 / 已删除时：路径旁或 hint 显示「该文件夹不可用，新下载将保存到系统下载文件夹」，「选择…」「恢复默认」仍可用。

---

## 5. 架构

```
BrowserDownloadPreferences          UserDefaults
        │  effectiveDirectoryURL
        ▼
BrowserDownloadManager              落盘 / revealDownloadDirectory
        │
        ├─ BrowserDownloadPanel     表头 folder / gear
        └─ BrowserSettingsWindowController   常规 · 下载位置
                    ▲
                    │ show + select 「常规」
           AppDelegate / BrowserWindowController
```

| 类型 | 职责 |
|------|------|
| `BrowserDownloadPreferences` | 读写自定义目录；计算有效目录；通知 |
| `BrowserDownloadManager` | 所有落盘走有效目录；`revealDownloadDirectoryInFinder` |
| `BrowserDownloadPanel` | 表头两按钮；gear 经 delegate 交给窗口 |
| `BrowserSettingsWindowController` | 常规页 UI；`selectTabWithIdentifier:` |
| `AppDelegate` | `showBrowserSettingsSelectingTab:`（或等价） |

模块仍在 `SimpleBrowser/Downloads/`；偏好类与 Manager 同目录。Makefile 增加 `BrowserDownloadPreferences.m`。

### 5.1 偏好 API（草案）

```objc
FOUNDATION_EXPORT NSNotificationName const BrowserDownloadPreferencesDidChangeNotification;

@interface BrowserDownloadPreferences : NSObject
+ (instancetype)sharedPreferences;

/// 用户选定的目录；nil 表示使用系统「下载」。
@property (nonatomic, copy, nullable) NSURL *customDirectoryURL;

/// 实际写入用：自定义目录可用则用之，否则系统「下载」（必要时 create:YES）。
@property (nonatomic, copy, readonly) NSURL *effectiveDirectoryURL;

@property (nonatomic, assign, readonly) BOOL usesCustomDirectory;
@property (nonatomic, assign, readonly) BOOL customDirectoryIsReachable;

- (void)resetToSystemDownloadsDirectory;
- (NSString *)displayPath; // 带 ~ 的展示串
@end
```

UserDefaults key：`MeoBrowserDownloadDirectoryPath`（POSIX 路径字符串）。

校验：`fileExists` + `isDirectory` + `isWritableFileAtPath:`。不通过则 `effectiveDirectoryURL` 回退系统「下载」，但 **不自动清空** 自定义值（设置里仍能看到坏路径，由用户改选或恢复默认）。

`setCustomDirectoryURL:` 只在设置里、用户从 OpenPanel 确认后调用。

### 5.2 Manager 落盘

将 `UniqueDestinationURLInDownloads` 改为基于 `effectiveDirectoryURL` 做重名 `-1`、`-2`…（现有三处调用：WK 落盘、blob/JS 回退、data URL 等均走同一函数）。

新增：

```objc
- (NSURL *)downloadDirectoryURL;                 // 转发 preferences.effective
- (BOOL)revealDownloadDirectoryInFinder;        // 失败返回 NO，由 UI Alert
```

`takeOwnershipOfDownload` / `decideDestination` 继续 `completionHandler(uniqueURL)`，目录来源改为偏好。

### 5.3 沙盒与书签

当前 **非沙盒**，存路径足够。若日后启用 App Sandbox：改为 security-scoped bookmark，并在读写目录时 `startAccessingSecurityScopedResource`。本版不实现书签，在代码注释与本方案留下口子即可。

### 5.4 设置 Tab 标识

`addTabNamed:` 今日用中文 title 当 identifier。本版改为稳定 id，便于齿轮定位：

| identifier | 标签 |
|------------|------|
| `general` | 常规 |
| `sync` | 云同步 |
| `keyboard` | 键盘 |
| `privacy` | 隐私 |
| `developer` | 开发者 |

`AppDelegate` 增加例如 `-showBrowserSettingsSelectingTabIdentifier:`；菜单「设置」仍走无参 `showBrowserSettings:`（不切 Tab）。

---

## 6. 错误与边界

| 情况 | 行为 |
|------|------|
| 从未自定义 | 有效目录 = `~/Downloads`（`create:YES`） |
| 自定义目录被删 / 改成文件 | 新下载回退系统「下载」；设置显示警告；表头打开：优先尝试自定义，失败则打开回退目录，仍失败再 Alert |
| 自定义目录只读 | 同上回退；设置提示不可写 |
| OpenPanel 取消 | 不改偏好 |
| 改目录时有进行中下载 | 已开始的任务不受影响；之后的新任务用新目录 |
| 重名 | 与 V1 相同：`name-1.ext` |
| 多窗口 | Manager / 偏好全局一份；任一窗口改设置，全部窗口下次下载生效 |
| iCloud / 外置盘 | 允许用户选中；可达性失败时走回退 |

不在本版做「目录变更确认对话框」（改目录是显式设置操作）。

---

## 7. 验收清单

- [ ] 空列表、清空后、有进行中/完成项时，表头文件夹与齿轮都在且可点  
- [ ] 文件夹按钮打开的是**当前有效下载目录**（默认 `~/Downloads`），不是某个文件  
- [ ] 行内「显示」仍只选中该文件  
- [ ] 齿轮关闭浮层，打开设置并停在「常规」，可见「下载位置」  
- [ ] 菜单「设置」不强制切 Tab  
- [ ] 「选择…」后新下载出现在新目录；重名规则不变  
- [ ] 「恢复默认」后新下载回到 `~/Downloads`  
- [ ] 进行中的下载在改目录后仍写到开始时的路径  
- [ ] 自定义目录删除后，新下载仍成功（回退），设置有警告  
- [ ] ⌘J / Esc / 点外部关闭行为与 V1 一致；点表头图标不误关后再无法打开  
- [ ] `make browser` 通过；无新增业务侧 `NSTextField` 输入框  

---

## 8. 实现文件（预期）

| 路径 | 变更 |
|------|------|
| `SimpleBrowser/Downloads/BrowserDownloadPreferences.h/.m` | **新建** |
| `SimpleBrowser/Downloads/BrowserDownloadManager.*` | 有效目录落盘；reveal 目录 |
| `SimpleBrowser/Downloads/BrowserDownloadPanel.*` | 表头两按钮；delegate |
| `SimpleBrowser/BrowserWindowController.m` | gear → AppDelegate |
| `SimpleBrowser/BrowserSettingsWindowController.*` | 常规页；稳定 Tab id |
| `SimpleBrowser/AppDelegate.*` | 选 Tab 打开设置 |
| `Makefile` | 新 `.m` |

---

## 9. V2 仍不做

- 下载前询问保存位置  
- 按站点不同目录  
- 完成通知、失败续传 UI  
- 下载独立窗口 / shelf  
