# SimpleBrowser 验收记录

> 本文件汇总 SimpleBrowser 各阶段验收结果。

---

## L1 验收（2026-07-10）

> Phase 3 联调验收 · 详见 [design.md](design.md) 第 6 节

### 自动化检查

| 检查项 | 命令 | 结果 |
|--------|------|------|
| 全量编译 | `make clean && make && make browser` | 通过，无编译警告 |
| 二进制与 plist | `make verify` | 通过 |
| SimpleWindow 未破坏 | `make` 独立成功 | 通过 |
| SimpleBrowser 构建 | `make browser` | 通过 |

### 内存基线（`make stats-all`）

| 应用 | RSS (KB) | 约合 |
|------|----------|------|
| SimpleWindow | ~105664 | ~103 MB |
| SimpleBrowser | ~123712 | ~121 MB |

SimpleBrowser 比 SimpleWindow 高约 **18 MB**，主要来自 WebKit，属预期范围。

### design.md L1 验收清单

| # | 验收项 | 状态 |
|---|--------|------|
| 1 | `make browser` 产出 App | 通过 |
| 2 | 启动可浏览网页 | 通过 |
| 3 | 地址栏回车可导航 | 通过 |
| 4 | 后退 / 前进 / 刷新 | 通过 |
| 5 | 窗口标题随页面更新 | 通过 |
| 6 | 加载失败 Alert | 通过 |
| 7 | 关窗后应用退出 | 通过 |
| 8 | SimpleWindow 不受影响 | 通过 |

**L1 结论：通过。**

---

## Launchpad 新标签页验收（NTP-0～NTP-3 · 2026-07-10）

> 对照 [new-tab-launchpad-design.md 第 11 节](new-tab-launchpad-design.md#11-验收标准ntp-1--ntp-2)

### 自动化检查

| 检查项 | 命令 | 结果 |
|--------|------|------|
| 全量编译 | `make clean && make && make browser` | 通过，无 `-Wall -Wextra` 警告 |
| 二进制验证 | `make verify` | 通过 |
| 废弃 HTML 占位 | `BrowserNewTabPage` 源文件 | 已删除，未链入 Makefile |

### NTP-1 功能验收

| 测试项 | 操作 | 状态 | 代码支撑 |
|--------|------|------|----------|
| 默认站点 | ⌘T 新建标签 | 通过 | `BrowserShortcutStore defaultShortcuts` + `BrowserLaunchpadView` |
| 单击打开 | 点击快捷方式 | 通过 | `launchpadView:openURL:` → `BrowserTab loadURL:` |
| 中键新标签 | 中键点击 | 通过 | `launchpadView:openURLInNewTab:` → `addTabWithURL:` |
| 地址栏导航 | 输入 URL 回车 | 通过 | `loadAddressBarURL` + `refreshTabsUI` |
| 会话恢复 | 新标签后重启 | 通过 | `about:newtab` + `loadNewTabPage` |
| 深浅色 | 系统外观切换 | 通过 | `NSVisualEffectMaterialContentBackground` + `labelColor` |
| 导航按钮 | 新标签页 | 通过 | `updateNavigationState` 禁用 ◀ ▶ ↻ |

### NTP-2 功能验收

| 测试项 | 操作 | 状态 | 代码支撑 |
|--------|------|------|----------|
| 添加 | 编辑模式点 ➕ | 通过 | `BrowserShortcutEditorSheet` + `addShortcutWithTitle:` |
| 编辑 | 右键「编辑…」 | 通过 | `presentEditingShortcut:` + `updateShortcutWithID:` |
| 删除 | 编辑模式点 × | 通过 | `removeShortcutWithID:` |
| 排序 | 拖拽 reorder | 通过 | `NSCollectionView` drag/drop + `saveShortcuts` |
| 分页 | 40+ 快捷方式 | 通过 | `kItemsPerPage=35` + 横向 scroll + 圆点指示器 |
| 非法 URL | sheet 校验 | 通过 | `validateURLString:` |
| 编辑模式 | 右键 / Esc | 通过 | `editingMode` + 本地 Esc 监听 |
| 持久化 | 重启保留 | 通过 | `NSUserDefaults` key `shortcutItems` |

### 多标签回归（L2 不退化）

| 操作 | 状态 | 说明 |
|------|------|------|
| ⌘T 新建标签 | 通过 | `addNewTab` → Launchpad |
| ⌘W 关闭标签 | 通过 | `closeSelectedTab` 未改动 |
| ⌘⇧[ / ⌘⇧] 切换 | 通过 | `selectPreviousTab` / `selectNextTab` |
| 会话恢复多标签 | 通过 | `BrowsingPreferences` + `restoreTabsFromEntries` |
| `target=_blank` | 通过 | `WKUIDelegate` 新建标签 |
| 窗口拖拽 | 通过 | Launchpad `mouseDownCanMoveWindow` 返回 NO，避免与横滑冲突 |

### 实现目录

```text
SimpleBrowser/NewTab/
├── BrowserLaunchpadView.h/.m
├── BrowserShortcutCellView.h/.m
├── BrowserShortcutEditorSheet.h/.m
├── BrowserShortcutItem.h/.m
└── BrowserShortcutStore.h/.m
```

### 结论

**Launchpad 新标签页（NTP-0～NTP-3）验收通过**，满足设计文档第 11 节全部标准。

延后项见 [new-tab-launchpad-development-plan.md](new-tab-launchpad-development-plan.md) NTP-4+（搜索等）。  
Favicon 多渠道与缓存见下方「Favicon 获取与缓存」及 [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md)。  
文件夹已单独验收：见下方「Launchpad 文件夹」。

本地验证：

```bash
make run-browser
```

---

## Launchpad 文件夹验收（FLD-0～FLD-3 · 2026-07-14）

> 对照 [new-tab-launchpad-folder-design.md §10](new-tab-launchpad-folder-design.md#10-分期与验收)  
> 开发计划：[new-tab-launchpad-folder-development-plan.md](new-tab-launchpad-folder-development-plan.md)

### 自动化检查

| 检查项 | 命令 | 结果 |
|--------|------|------|
| 全量编译 | `make clean && make browser` | 通过，无 `-Wall -Wextra` 警告 |
| Overlay 入链 | Makefile 含 `BrowserShortcutFolderOverlay.m` | 通过 |

### FLD-1 / FLD-2 功能验收

| 测试项 | 操作 | 状态 | 代码支撑 |
|--------|------|------|----------|
| 拖合建夹 | 编辑态将 link A 拖到 B 中心悬停 ≥400ms | 通过 | `createFolderWithTitle:fromItem:droppingItem:` |
| 拖入已有夹 | 拖 link 到 folder cell | 通过 | `moveItem:intoFolder:` |
| 展开 / 关闭 | 单击文件夹；Esc / 点遮罩 | 通过 | `BrowserShortcutFolderOverlay` |
| 夹内打开 | 单击 / 中键 | 通过 | overlay → dismiss → delegate |
| 改名 | 点击标题 / 右键重命名 | 通过 | `SBTextField` + `renameFolderWithID:` |
| 解散 / 删除 | 右键或 × 确认 | 通过 | `disbandFolderWithID:` / `removeFolderWithID:deleteChildren:` |
| 拖出顶层 | 夹内拖到遮罩外；或右键「移出文件夹」 | 通过 | `moveItem:toTopLevelAtOrder:` |
| 持久化迁移 | 旧 `shortcutItems` 数组 | 通过 | version 2 payload + orphan 修复 |
| 地址栏补全 | 匹配夹内站点 | 通过 | `shortcutsMatchingQuery:` 跳过 folder |
| 四宫格 / 动画 | 夹图标与展开 scale+fade | 通过 | Cell folder tiles + overlay 动画 |

### 实现目录（增量）

```text
SimpleBrowser/NewTab/
├── BrowserShortcutFolderOverlay.h/.m   # 新增
├── BrowserShortcutItem.*               # kind / folderID
├── BrowserShortcutStore.*              # version 2 + 文件夹 API
├── BrowserShortcutCellView.*           # 四宫格 / 合并环
└── BrowserLaunchpadView.*              # topLevel + merge drop
```

### 结论

**Launchpad 文件夹（FLD-0～FLD-3）验收通过**，满足设计文档 §10 标准。

---

## Favicon 获取与缓存验收（ICO-0～ICO-2 · 2026-07-14）

> 对照 [favicon-fetch-cache-design.md §11](favicon-fetch-cache-design.md#11-分期与验收)  
> 开发计划：[favicon-fetch-cache-development-plan.md](favicon-fetch-cache-development-plan.md)

### 自动化检查

| 检查项 | 命令 / 说明 | 结果 |
|--------|-------------|------|
| 全量编译 | `make browser` | 通过 |
| Favicon 入链 | Makefile 含 `SimpleBrowser/Favicon/*.m` | 通过 |
| 瀑布冒烟 | `example.com` → 落盘 + 二次磁盘命中 | 通过 |

### 功能验收

| 测试项 | 操作 | 状态 | 代码支撑 |
|--------|------|------|----------|
| 星标加入拉图标 | 地址栏 ★ 加入后后台拉取并回写 `iconURL` | 通过（逻辑） | `toggleBookmark:` + `BrowserFaviconService` |
| 编辑「自动获取」 | Sheet 按钮 UserAction 瀑布，填入链接 | 通过（逻辑） | `BrowserShortcutEditorSheet` |
| Launchpad 显示 | Cell / 四宫格走 Service，失败字母占位 | 通过（逻辑） | `BrowserShortcutCellView` |
| 补全不风暴 | 补全行 `triggerFetch=NO` | 通过 | `BrowserShortcutSuggestionPanel` |
| 长期缓存 | `Application Support/MeoBrowser/Favicons/` | 通过 | `BrowserFaviconCache` |
| 断网冷启动仍显示 | 手测 | 待手测 | 磁盘 blobs |

### 涉及文件

```text
SimpleBrowser/Favicon/
├── BrowserFaviconService.h/.m
├── BrowserFaviconCache.h/.m
├── BrowserFaviconHTMLParser.h/.m
└── BrowserFaviconUtil.h/.m
```

### 结论

**ICO-0～ICO-2 实现完成**；标签栏 favicon 与清除缓存 UI 仍属设计延后项。手测项（断网复用、连点 ★）建议在 `make run-browser` 时补勾。

---

## 登录助手 V1 验收（LA-0～LA-3 · 2026-07-15）

> 对照 [auto-login-design.md](auto-login-design.md) · [auto-login-development-plan.md](auto-login-development-plan.md)  
> Cursor 计划：`.cursor/plans/login-assist-v1.plan.md`

### 自动化检查

| 检查项 | 命令 / 说明 | 结果 |
|--------|-------------|------|
| 全量编译 | `make clean && make browser` | 通过（无新增警告） |
| LoginAssist 入链 | Makefile 含 `SimpleBrowser/LoginAssist/*.m`、`-framework Security` | 通过 |
| 测试页入包 | `Contents/Resources/login-assist-test.html` | 通过 |

### 功能验收

| 测试项 | 状态 | 说明 |
|--------|------|------|
| Recipe JSON + Keychain | 通过（逻辑） | `LoginRecipeStore` / `LoginCredentialStore` |
| 工具栏点亮 + ⌘⇧L | 通过（逻辑） | ActionGroup `loginAssist` + 文件菜单 |
| 一键 fill/click/enter | 通过（逻辑） | `LoginRunner` |
| 设置 UI + 点选拾取 | 通过（逻辑） | `BrowserLoginAssistSettingsWindowController` |
| 自动登录 / 防抖 / Esc 取消 | 通过（逻辑） | `LoginAssistController` |
| 右键多账号菜单 | 通过（逻辑） | 按钮右键 |
| 清除网站数据不删 Recipe | 通过（文案） | 设置确认文案已说明 |
| 手工端到端（测试页 demo/pass） | 待手测 | `make run-browser` 后打开 Resources 内测试页 |

### 手测步骤（建议）

1. `make run-browser`
2. 地址栏打开：`…/MeoBrowser.app/Contents/Resources/login-assist-test.html`
3. 文件 → 登录助手… → 新建 → 账号 `demo` / `pass` → 拾取字段 → 保存  
   （主机应为 `file`，路径前缀可为 `login-assist-test.html`）
4. 确认钥匙图标点亮 → ⌘⇧L 或单击 → 页面显示「登录成功」
5. 勾选自动登录后刷新，应自动提交；连刷不死循环；待执行时 Esc 可取消

### 结论

**LA-0～LA-3（V1）代码已落地**；短信 / 二维码 / Companion 属后续阶段。
