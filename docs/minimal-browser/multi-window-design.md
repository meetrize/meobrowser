# 多窗口 — 实现方案

> 目标：在现有「单窗口 + 多标签」架构上支持多个浏览器窗口（⌘N、链接在新窗口打开、窗口级会话恢复），且不显著增加应用体积与空闲内存。  
> 状态：**已实现（MW-0～MW-3，2026-07-15）**  
> 开发计划：[multi-window-development-plan.md](multi-window-development-plan.md)  
> Cursor Plan（可 Build）：[.cursor/plans/multi-window.plan.md](../../.cursor/plans/multi-window.plan.md)  
> 路线图：`professional-features-roadmap.md` §3.5 / M3

---

## 1. 方案定位

### 1.1 做什么

| 层级 | 名称 | 能力 |
|------|------|------|
| **MW-1** | 最小可用 | ⌘N 新建窗口；窗口列表由 AppDelegate 管理；菜单走 First Responder；关闭最后一窗退出 |
| **MW-2** | 会话与 WebKit | 窗口级会话持久化/恢复；`createWebView` / 右键支持「新窗口」策略 |
| **MW-3** | 资源与体验 | 全局存活 WebView 预算；下载管理应用级共享；外链打开策略；窗口菜单 |

**首版交付目标：MW-1 + MW-2。** MW-3 可随验收并行或紧随其后。

### 1.2 不做什么（首版）

- 不做「标签拖到窗外变新窗口」（可后续加）
- 不做多 Profile / 多数据存储隔离（窗口间仍共享 `WKWebsiteDataStore.defaultDataStore`）
- 不做独立 WebKit process pool（继续默认池，Cookie/登录态跨窗口一致）
- 不做分屏 / 侧边栏（路线图另项）
- 不改变单窗口内标签休眠语义（仍按窗口内预算工作；MW-3 再加全局预算）

### 1.3 与现有能力的关系

| 现有能力 | 本方案关系 |
|----------|------------|
| `AppDelegate` 单例 `_browserWindowController` | 改为窗口列表 + 工厂方法 |
| `BrowserWindowController` | **可多实例**；不再安装菜单；不再独自写全局会话 |
| `BrowserTabController` / `BrowserTab` | 已是窗口作用域，基本复用 |
| `BrowsingPreferences.tabSession` | 扩展为 `windowSession`（兼容旧单窗数据） |
| `BrowserMenus` 硬绑定 `target` | 改为 `target = nil`（First Responder）或由 AppDelegate 安装一次 |
| `createWebView…windowFeatures:` | 今日一律新标签；按策略可建新窗口 |
| `BrowserDownloadManager` 每窗一个 | MW-3 提升为应用级单例 |
| Launchpad / ShortcutStore / Favicon | 保持应用级单例；每窗各自 `BrowserLaunchpadView` |
| 地址栏补全 panel | 设计已约定「每窗独立 controller」— 自然适配 |

**原则**：多窗口 = 多个「完整浏览器窗口壳」共享同一浏览配置文件；性能成本由存活页面数决定，不由窗口壳数量决定。

---

## 2. 用户场景

### 2.1 典型流程

```
启动 App
  → 恢复 N 个窗口（MW-2；无数据则 1 个空/NTP 窗口）
用户 ⌘N
  → 新窗口，内含 1 个新标签页（Launchpad）
用户在窗口 A ⌘T
  → 仅窗口 A 增加标签
页面 target=_blank / 右键「在新窗口打开」
  → 按策略：新标签（兼容现状）或新窗口（MW-2）
关闭窗口
  → 若非最后一窗：销毁该窗控制器并持久化剩余窗口
  → 若最后一窗：按现有逻辑退出应用
```

### 2.2 快捷键与菜单（定稿）

| 操作 | 快捷键 | 作用域 |
|------|--------|--------|
| 新建窗口 | ⌘N | App（AppDelegate 或 First Responder → key window 工厂） |
| 新建标签页 | ⌘T | **当前 key 窗口** |
| 关闭标签页 | ⌘W | 当前 key 窗口；关最后一标签 → 关该窗口 |
| 关闭窗口 | ⌘⇧W（可选）或系统窗口菜单 | 关闭当前浏览器窗口 |
| 下载面板 | ⌘J | 当前 key 窗口弹出（数据源 MW-3 后为共享） |
| 标签切换 ⌘⇧[ / ] | 当前 key 窗口 |

建议菜单结构：

- **文件**：新建窗口（⌘N）、新建标签页可保留在标签菜单、下载（⌘J）
- **标签页**：现有项不变，target 改为 First Responder
- **窗口**：沿用系统「窗口」菜单（最小化、前置等）；不必自建复杂窗口列表

### 2.3 WebKit「新窗口」策略（定稿）

| 来源 | MW-1 | MW-2+ |
|------|------|-------|
| `createWebView` 且无 mainFrame（典型 popup / target=_blank） | 继续 **新标签**（零行为回归） | 可配置；默认仍 **新标签** |
| 显式「在新窗口打开链接」（右键 / 菜单，若实现） | — | **新窗口**，带该 URL 一个标签 |
| `windowFeatures` 带明显独立窗口尺寸 | — | 可选：新窗口并尽量应用 frame（可降级忽略尺寸） |

> **定稿**：默认不把所有 popup 都变成独立 `NSWindow`，避免广告弹窗刷屏；独立窗口以用户主动操作为主。

---

## 3. 架构设计

### 3.1 目标结构

```
AppDelegate
  ├─ NSMutableArray<BrowserWindowController *> *browserWindows
  ├─ + newBrowserWindow / openURL:inNewWindow:
  ├─ 安装浏览器菜单（一次）
  └─ BrowserDownloadManager *sharedDownloads   (MW-3)

BrowserWindowController  (N 个)
  ├─ NSWindow + chrome
  ├─ BrowserTabController
  ├─ WKWebViewConfiguration（可每窗一份，共享 defaultDataStore）
  ├─ BrowserLaunchpadView（每窗）
  └─ 地址栏 / 补全 / 可选下载 panel UI
```

### 3.2 AppDelegate 职责

| 方法 / 行为 | 说明 |
|-------------|------|
| `createBrowserWindowWithSession:` | 工厂：配置 → 创建 controller → 加入列表 → show |
| `newBrowserWindow:` | ⌘N：空会话（1× NTP） |
| `removeBrowserWindow:` | windowWillClose 回调后移除；persist |
| `keyBrowserWindowController` | `NSApp.keyWindow.windowController` 若为浏览器窗则返回 |
| `openURLs:` | 投递给 key 窗口；无窗口则先建再投递 |
| `applicationWillTerminate` | 持久化**全部**窗口会话 |
| `applicationShouldTerminateAfterLastWindowClosed` | 保持 `YES` |

### 3.3 菜单改造（关键路径）

现状：每个 `BrowserWindowController init` 调用 `installTabMenuForTarget:self` 等，多实例会**重复插入菜单且绑死第一个/最后一个 target**。

改造：

1. `AppDelegate.applicationWillFinishLaunching`（或首窗创建前）**只安装一次** File / Tab / View。
2. 菜单项 `target = nil`，`action` 指向已在 `BrowserWindowController` 上实现的同一 selector（经 First Responder / key window）。
3. `BrowserWindowController` **删除** init 内的 `install*Menu` 调用。
4. App 级动作（新建窗口、设置）留在 AppDelegate。

`NSMenuItemValidation` 已在窗口控制器实现的，继续由 key 窗口响应即可。

### 3.4 会话数据模型

**旧格式**（保留读取兼容）：

```json
tabSession: { "tabs": [...], "selectedIndex": 0, "pinnedCount": 0 }
```

**新格式**：

```json
windowSession: {
  "version": 1,
  "windows": [
    {
      "tabs": ["https://…", "about:newtab"],
      "selectedIndex": 0,
      "pinnedCount": 0,
      "frame": "{{x, y}, {w, h}}",   // 可选，NSStringFromRect
      "isMiniaturized": false         // 可选
    }
  ]
}
```

规则：

| 规则 | 说明 |
|------|------|
| 写入 | 始终写 `windowSession`；可同时写回「第一窗」到旧 `tabSession` 作短过渡，或启动迁移后删旧键 |
| 读取 | 有 `windowSession.windows` 则用；否则把旧 `tabSession` 包成单窗数组 |
| 空会话 | 至少恢复 / 创建 1 个窗口，内含 NTP |
| 持久化触发 | 现有 0.3s debounce **每窗**仍可调用；实际写入改为「收集全部窗口 → AppDelegate / Preferences 一次写」 |

推荐 API 形状：

```objc
// BrowsingPreferences
+ (NSArray<NSDictionary *> *)savedWindowSessions; // 每项含 tabs/selectedIndex/pinnedCount/frame
+ (void)saveWindowSessions:(NSArray<NSDictionary *> *)sessions;
```

`BrowserWindowController` 提供 `-sessionDictionary` / `-restoreFromSessionDictionary:`，不再直接 `saveTabEntries:`。

### 3.5 窗口关闭与最后标签

保持现有语义：关闭窗口内最后一标签 → `tabControllerRequestsCloseWindow` → `[window close]`。

额外：

- `windowWillClose:`：通知 AppDelegate 从列表移除，并 `persistAllWindowSessions`。
- 设置窗、下载 panel、补全 panel **不计入**「浏览器窗口列表」。

### 3.6 下载（MW-3）

| 方案 | 说明 |
|------|------|
| **推荐** | `BrowserDownloadManager` 单例（或 AppDelegate 持有）；各窗 toolbar/badge 观察同一 manager；⌘J 在 **key 窗口** 弹出 panel |
| 暂缓（MW-1/2） | 每窗仍各自 manager（功能可用，但跨窗下载列表分裂） |

### 3.7 休眠预算（MW-3）

| 层级 | 行为 |
|------|------|
| 窗口内 | 保留 `kMaxLiveWebViews = 8` |
| 全局 | 新增例如 `kMaxLiveWebViewsGlobal = 12`；超额时优先休眠非 key、非前台窗口的闲置标签 |

MW-1/2 可不做全局预算；文档中标明风险：N 窗 ≈ 最多 N×8 存活 WebView。

### 3.8 配置与数据共享

每个窗口可 `[[WKWebViewConfiguration alloc] init]`，但：

- `websiteDataStore = defaultDataStore`（登录态一致）
- 不自定义 `WKProcessPool`（与今日一致）
- `NSURLCache` 共享设置保留在首次配置时执行一次即可（避免每窗重复 `setSharedURLCache`）

---

## 4. 性能影响（设计约束）

| 维度 | 预期 | 约束 |
|------|------|------|
| 应用体积 | ≈0 | 仅 ObjC + UserDefaults schema |
| 空窗内存 | 低（数 MB～十余 MB 量级 UI） | 新窗口默认仅 NTP，不预创建 WebView |
| 响应速度 | 建窗应即时 | 禁止在 `init` 同步加载重资源；wallpaper 仍走现有共享解码 |
| 多页内存 | 与「同等数量存活标签」同阶 | MW-3 全局休眠预算 |

验收时可用 `make stats-browser` 对比：1 窗 1 NTP vs 3 窗各 1 NTP vs 1 窗 3 存活页。

---

## 5. 主要改动文件

| 文件 | 改动 |
|------|------|
| `AppDelegate.m/.h` | 窗口列表、工厂、⌘N、统一 persist、外链路由 |
| `BrowserMenus.m/.h` | 安装一次；File 增加「新建窗口」；target=nil |
| `BrowserWindowController.m` | 去掉装菜单；会话 API；window close 回调；可选 new-window 入口 |
| `BrowsingPreferences.m/.h` | `windowSession` 读写 + 旧格式迁移 |
| `BrowserTabController.m` | MW-3 可选：参与全局预算 |
| `BrowserDownloadManager` | MW-3：共享实例 |
| `docs/README.md` / roadmap | 索引与勾选状态 |

**预计新增代码量**：中等（约数百行），无新第三方依赖。

---

## 6. 风险与决策

| 风险 | 缓解 |
|------|------|
| 菜单重复 / 绑错窗口 | 菜单只装一次 + First Responder |
| 会话互相覆盖 | 禁止窗口各自 `saveTabEntries`；统一 `saveWindowSessions` |
| Popup 刷屏 | 默认 popup→标签；仅主动「新窗口打开」建窗 |
| 内存随窗数线性涨（休眠分窗） | MW-3 全局预算 |
| 下载列表分裂 | MW-3 共享 DownloadManager |
| `NSURLCache` 被多次重置 | 配置抽取为一次性 `+configureSharedWebKitDefaults` |

### 仍可后续讨论

1. ⌘W 关最后标签是关窗还是留 NTP（今日：关窗 — **保持**）
2. 外链（`openURLs:`）进 key 窗口还是总是新窗口（建议：**key 窗口新标签**）
3. 是否在「窗口」菜单列出全部浏览器窗标题（系统通常已够用）

---

## 7. 验收标准（摘要）

详见开发计划「验收」节。核心：

- [ ] ⌘N 可开第二窗；两窗各自标签互不串
- [ ] ⌘T / ⌘W / 缩放 / 下载快捷键只影响 key 窗口
- [ ] 重启后窗口数与各窗标签恢复（MW-2）
- [ ] 旧 `tabSession` 用户升级后仍能打开（单窗迁移）
- [ ] 关闭最后一浏览器窗 → App 退出
- [ ] 设置窗、补全面板不占用「浏览器窗」会话槽
- [ ] `make browser` 通过；NTP 空多窗内存明显低于「多存活页」

---

## 8. 参考

- 现状分析结论：多窗口成本 ≈ 窗口壳 + 存活页面；体积可忽略
- [multi-tab-design.md](multi-tab-design.md)
- [professional-features-roadmap.md](professional-features-roadmap.md) §3.5 / M3
- [address-bar-shortcut-autocomplete-design.md](address-bar-shortcut-autocomplete-design.md)（多窗口约定）
- [download-design.md](download-design.md)
