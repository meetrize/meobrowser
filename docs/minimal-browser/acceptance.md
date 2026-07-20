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

**LA-0～LA-3（V1）代码已落地**；V2 短信 / Companion 见下一节。

---

## 登录助手 V2 验收（短信 OTP + Android Companion · 2026-07-15）

> 对照 [auto-login-design.md](auto-login-design.md) · [companion-protocol.md](companion-protocol.md) · [auto-login-development-plan.md](auto-login-development-plan.md)  
> Cursor 计划：`.cursor/plans/login-assist-v2.plan.md`  
> Android：`companion/android/MeoCompanion/`

### 自动化检查

| 检查项 | 命令 / 说明 | 结果 |
|--------|-------------|------|
| Mac 编译 | `make clean && make browser` | 通过（含 Network / Companion / OTPInbox） |
| 协议文档 | `docs/minimal-browser/companion-protocol.md` | 已写 |
| Android 工程 | Kotlin 源码 + Manifest 短信/前台服务 | 已落地（需 Android Studio `assembleDebug`） |
| 测试页短信区 | `login-assist-test.html` 含发码 + OTP | 已入包 |

### 功能验收

| 测试项 | 状态 | 说明 |
|--------|------|------|
| OTPInbox TTL / 一次性消费 | 通过（逻辑） | `OTPInbox` |
| Bonjour 收码 + 配对 | 通过（逻辑） | `CompanionChannel` / 设置页配对码 |
| Recipe waitOTP（hybrid/sms） | 通过（逻辑） | `LoginRunner` + 设置「账密+短信」 |
| 粘贴 / 剪贴板降级 | 通过（逻辑） | waitOTP 期间轮询 + 菜单「粘贴验证码」 |
| Android 读短信推码 | 待手测 | `SmsOtpReceiver` + `CompanionClient` |
| 断连明示 | 通过（逻辑） | 设置状态 + 失败提示含配对说明 |
| 端到端真机 | 待手测 | 同 Wi‑Fi 配对后推码填入测试页 |

### 手测步骤（主路径）

1. `make run-browser` → 打开 Resources 内 `login-assist-test.html`
2. 登录助手设置：模式选「账密 + 短信」，账号 `demo`/`pass`，拾取短信区字段与「发送验证码」按钮，保存
3. 记下设置页 **配对码** 与端口；Android 安装 Companion，输入配对码连接（或填 `MacIP:端口`）
4. 一键登录 → 点发送验证码 → 手机推码（或「手动发送测试码」/粘贴页上显示的码）→ 应显示「短信登录成功」

### 结论

**Mac 侧 V2 管线与 Android 工程已落地**；真机 Bonjour/短信端到端待手测勾选。TOTP（LA-4）仍后置。

---

## Companion 手机通知镜像验收（NM-0～NM-2 · 2026-07-20）

> 对照 [companion-notification-mirror-design.md](companion-notification-mirror-design.md) · [companion-notification-mirror-development-plan.md](companion-notification-mirror-development-plan.md) · [companion-protocol.md](companion-protocol.md) V2.1

### 自动化检查

| 检查项 | 命令 / 说明 | 结果 |
|--------|-------------|------|
| Mac 编译 | `make browser`（含 UserNotifications） | 通过 |
| Android 编译 | `companion/android/MeoCompanion` → `./gradlew assembleDebug` | 通过 |
| 协议 V2.1 | `phone_notification` / `_ok` | 已文档化 |

### 功能验收（逻辑 / 代码）

| 测试项 | 状态 | 说明 |
|--------|------|------|
| 默认仅验证码 | 通过（逻辑） | `NotificationMirrorMode.OTP_ONLY` |
| 全部模式需确认 | 通过（逻辑） | MainActivity 对话框 |
| 噪音过滤 ongoing / 空内容 / 自身 | 通过（逻辑） | `NotificationNoiseFilter` |
| 去重 60s + 限流 ~5/s | 通过（逻辑） | `NotificationMirrorGate` |
| Mac 鉴权 + 一律 ack | 通过（逻辑） | `CompanionChannel` |
| 标题前缀展示 | 通过（逻辑） | `PhoneNotificationPresenter` |
| 关闭镜像仍 ack、不展示 | 通过（逻辑） | `mirrorEnabled` |
| OTP 双弹抑制（3s） | 通过（逻辑） | 镜像后抑制验证码横幅 |
| 前台也弹横幅 | 通过（逻辑） | `willPresentNotification` |
| 未知 type 安全忽略 | 通过（逻辑） | 向前兼容 |

### 手测清单（真机 · 待勾选）

- [ ] 默认「仅验证码」：微信普通消息不出现在 Mac
- [ ] 仅验证码：验证码仍可填入登录助手
- [ ] 「全部通知」：普通通知 Mac 标题含 App 名
- [ ] 全部 + 验证码通知：可填码且系统通知不双弹
- [ ] 播放音乐等 ongoing 不推送
- [ ] Mac 关「接收镜像」后不再弹（填码仍可用）
- [ ] Mac 拒绝系统通知权限后填码仍可用
- [ ] 断线后 Android 有节流后的「跳过」提示；重连后恢复

### 结论

**NM-0～NM-2 代码已落地**；上表手测项需同 Wi‑Fi 真机勾选（NM-3）。

---

## 登录表单内联助手 V1.5 验收（IF-0～IF-3 · 2026-07-15）

> 对照 [login-form-inline-design.md](login-form-inline-design.md) · [login-form-inline-development-plan.md](login-form-inline-development-plan.md)  
> Cursor 计划：`.cursor/plans/login-form-inline.plan.md`

### 自动化检查

| 检查项 | 结果 |
|--------|------|
| `make browser` | 通过（含 AuthenticationServices） |
| 新模块入链 | `LoginFormDetector` / `SystemPasswordBridge` / `SaveRecipePromptCoordinator` / Prefs |

### 功能验收

| 测试项 | 状态 |
|--------|------|
| 测试页密码框右侧内联钥匙 | 通过（逻辑）；待手测 |
| 点图标弹出菜单（系统密码 / Recipe / 保存） | 通过（逻辑） |
| Recipe 一键 / 仅填入；OTP 默认不提交 | 通过（逻辑） |
| 系统密码桥不崩溃（ad-hoc 可能不可用） | 通过（逻辑） |
| 提交后询问保存；设置可关 | 通过（逻辑） |

### 手测

1. `make run-browser` → 打开 `Resources/login-assist-test.html`  
2. 密码框右侧应出现钥匙 → 点开菜单  
3. 配置 Recipe 后可一键登录；手输 `demo`/`pass` 并登录成功后应询问保存  

### 结论

**IF-0～IF-3 已落地**；系统密码完整能力依赖正式签名 / web-browser entitlement。

---

## 反风控与会话稳定验收（AB-0～AB-4 · 2026-07-16）

> 对照 [anti-bot-session-design.md](anti-bot-session-design.md) · [anti-bot-session-development-plan.md](anti-bot-session-development-plan.md)  
> Cursor 计划：`.cursor/plans/anti-bot-session.plan.md`

### 自动化检查

| 检查项 | 命令 / 说明 | 结果 |
|--------|-------------|------|
| 编译 | `make browser` | 通过 |
| 校验 | `make verify` | 见本次验收 |
| 新模块 | `BrowserUserAgent` / `BrowserRiskHostPolicy` | 已入 Makefile |
| 无写死 UA | 源码无 `Version/18.0 Safari/605.1.15` | 已移除 |

### 功能验收

| 测试项 | 状态 | 说明 |
|--------|------|------|
| 动态 Safari 对齐 `customUserAgent` | 通过（逻辑） | `BrowserUserAgent` + `BrowserTab ensureWebView` |
| 风险域空闲休眠跳过 | 通过（逻辑） | `BrowserTabController` + Policy |
| 预算淘汰保护站末位 | 通过（逻辑） | 窗内 / 全局预算 |
| Google 等域无登录助手注入 | 通过（逻辑） | Detector JS + Native 抑制 |
| Runner 抑制域 Toast 拒绝 | 通过（逻辑） | `LoginAssistController` |
| 设置清除全部 / 当前站点 | 通过（逻辑） | `BrowsingPreferences` + Settings |
| 复制 User-Agent / VPN 提示文案 | 通过（逻辑） | 设置「隐私与数据」 |
| `login-assist-test.html` 助手仍可用 | 待手测 | 非抑制域应正常 |

### 手测

1. 设置 →「复制 User-Agent」，粘贴应含 `Version/` 与 `Safari/`  
2. 打开 Google 搜索：密码框旁无登录助手钥匙  
3. Google 标签后台闲置 >10 分钟（标签未爆预算）：尽量不整页冷重载  
4. 打开 `login-assist-test.html`：内联助手与一键登录正常  
5. 设置 → 清除网站数据 →「清除当前站点」仅影响当前 host  

### 结论

**AB-0～AB-4 代码已落地**；Google `/sorry/` 是否减少依赖出口 IP，属环境因素，App 侧信号已加固。
