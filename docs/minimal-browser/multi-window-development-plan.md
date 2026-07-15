# 多窗口 — 开发计划

> 基于 [multi-window-design.md](multi-window-design.md) 的分阶段实施计划。  
> 前置条件：多标签 L2、`BrowserTabController` 休眠预算、现有会话 `tabSession` 可用。  
> **状态：已实现（2026-07-15）。**  
> **Cursor Plan**：[.cursor/plans/multi-window.plan.md](../../.cursor/plans/multi-window.plan.md)

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| ⌘N | 新建浏览器窗口，内含 1 个 NTP |
| popup / `target=_blank` | **默认仍开新标签**（避免行为回归与广告刷窗） |
| 主动「在新窗口打开」 | MW-2 提供（右键或菜单）；首版可先做菜单项 + API，右键跟进 |
| 外链 `openURLs:` | 投递 **key 浏览器窗口** 的新标签；无窗则先建窗 |
| ⌘W 关最后标签 | **关闭该窗口**（与今日一致） |
| 最后一浏览器窗关闭 | App 退出（`applicationShouldTerminateAfterLastWindowClosed = YES`） |
| 会话 | MW-1 可暂只持久化「key / 第一窗」（兼容旧格式）；**MW-2 必须**完整多窗恢复 |
| 下载共享 / 全局休眠 | **MW-3**，不阻塞 MW-1/2 合并 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| Phase MW-0 | 会话 API 与菜单解耦准备 | 0.5～1 天 | Preferences 新 API 骨架；菜单改 First Responder |
| Phase MW-1 | 最小可用多窗口 | 1～2 天 | ⌘N、窗口列表、关窗清理；单窗会话仍可用 |
| Phase MW-2 | 窗口级会话 + 新窗口打开 | 1～2 天 | 重启恢复多窗；主动新窗口打开链接 |
| Phase MW-3 | 资源与体验 | 1 天 | 共享下载、全局休眠预算、验收与文档勾选 |
| Phase MW-4 | 联调验收 | 0.5 天 | `make browser`、对照验收清单 |

**合计约 4～6.5 人日。** 可先合 MW-0+MW-1（内部可用），再合 MW-2。

---

## Phase MW-0：准备层

**目标**：多实例前先拆掉「单例假设」中最危险的部分（菜单硬绑定、会话写入入口）。

### 任务清单

- [ ] **0.1** `BrowsingPreferences` 增加 `savedWindowSessions` / `saveWindowSessions:`（内部仍可先写旧 `tabSession` 单窗，或写新键但读时兼容）
- [ ] **0.2** `BrowserWindowController` 抽出 `-sessionDictionary` / `-applySessionDictionary:`（tabs / selectedIndex / pinnedCount；frame 可下一阶段）
- [ ] **0.3** `persistTabSessionNow` 改为通过 AppDelegate（或 Preferences 聚合 API）写入，避免多窗互相 `saveTabEntries` 覆盖（MW-1 前若仍单窗，行为需不变）
- [ ] **0.4** `BrowserMenus`：文件 / 标签 / 查看菜单项 `target = nil`；提供「仅安装一次」守卫（或由 AppDelegate 调安装，WindowController 不再装）
- [ ] **0.5** 「文件」菜单增加「新建窗口」⌘N，`action = @selector(newBrowserWindow:)`，实现放在 AppDelegate
- [ ] **0.6** 从 `BrowserWindowController init` 移除 `installTabMenu` / `installDownloadMenu` / `installViewMenu`；改为 AppDelegate 启动时安装一次
- [ ] **0.7** `make browser` + 手测：单窗口下 ⌘T / ⌘W / ⌘J / 缩放仍正常（First Responder 路径）

**验收（MW-0）**

- 仅一窗时行为与改造前一致
- 主菜单中 File / 标签 / 查看各出现一次

---

## Phase MW-1：最小可用

**目标**：用户可开多个浏览器窗口并独立使用标签；进程内可用，重启恢复可仍为单窗或「仅第一窗」。

### 任务清单

#### 1A — AppDelegate 窗口管理

- [ ] **1.1** `_browserWindowController` → `NSMutableArray<BrowserWindowController *> *_browserWindows`
- [ ] **1.2** `-createBrowserWindowWithSession:(nullable NSDictionary *)session`：创建、show、加入数组；NTP 或 `applySessionDictionary`
- [ ] **1.3** `-newBrowserWindow:`（⌘N）→ 空会话新窗
- [ ] **1.4** `-keyBrowserWindowController`；`openURLs:` / 设置 等路由到 key 窗
- [ ] **1.5** 窗口 `windowWillClose:` → 从数组移除；若数组空则允许 terminate
- [ ] **1.6** `applicationWillTerminate` → 持久化当前策略下的会话（见 1C）
- [ ] **1.7** `applicationDidFinishLaunching`：创建首窗（读旧单窗会话即可）

#### 1B — WindowController

- [ ] **1.8** `NSWindowDelegate`：`windowWillClose` 通知 AppDelegate
- [ ] **1.9** 关闭最后一标签关窗后，不留下「幽灵」controller（列表移除 + 取消 pending persist）
- [ ] **1.10** `NSURLCache` / 共享 WebKit 默认配置改为进程内只配置一次（避免每窗重复）

#### 1C — 会话（过渡）

- [ ] **1.11** MW-1 过渡策略（二选一，实现时写死一种）：
  - **A（推荐）**：已能收集多窗则写 `windowSession`；启动若存在多窗数据则 MW-1 就恢复（提前做部分 MW-2）
  - **B**：仍只保存 key/第一窗到旧 `tabSession`；文档标明「重启只恢复一窗」
- [ ] **1.12** 若选 B：在设计/本计划标注技术债，MW-2 必须清掉

#### 1D — 手测

- [ ] **1.13** ⌘N 开第二窗；A 窗开标签不影响 B 窗条
- [ ] **1.14** 关非最后一窗后 App 仍在；关最后一窗后退出
- [ ] **1.15** 外链打开进 key 窗口

**验收（MW-1）**

- [ ] 可同时显示 ≥2 个浏览器窗口
- [ ] 菜单快捷键作用于 key 窗口
- [ ] 无菜单项重复
- [ ] 设置窗口仍可独立打开

---

## Phase MW-2：会话与「新窗口打开」

**目标**：完整窗口级恢复；用户可主动在新窗口打开链接。

### 任务清单

#### 2A — 窗口级会话

- [ ] **2.1** `windowSession` 读写落地；启动迁移：旧 `tabSession` → 单元素 `windows`
- [ ] **2.2** 每窗字典含 `tabs` / `selectedIndex` / `pinnedCount`；可选 `frame`
- [ ] **2.3** `saveWindowSessions:` 由 AppDelegate 在 debounce / terminate / 关窗时汇总写入
- [ ] **2.4** 启动按 `windows` 数组创建 N 个 `BrowserWindowController` 并恢复 frame（非法 frame 则 cascade + center）
- [ ] **2.5** 空数组 / 损坏数据 → 回退 1 窗 NTP

#### 2B — 新窗口打开 API

- [ ] **2.6** AppDelegate `-openURLInNewBrowserWindow:(NSURL *)url`（或 session 含单 tab）
- [ ] **2.7** `BrowserWindowController` 菜单/动作「在新窗口打开当前页」或链接（至少一种用户可达路径）
- [ ] **2.8** `createWebView…`：**保持默认新标签**；若后续解析右键「Open in New Window」再调 2.6（与现有 download hijack 路径协调，勿误伤下载）
- [ ] **2.9**（可选）上下文菜单「在新窗口打开链接」— 若工作量可控则纳入，否则记后续

#### 2C — 手测

- [ ] **2.10** 两窗各若干标签 → 退出 → 重启，窗数与 URL/选中/固定标签正确
- [ ] **2.11** 旧版本仅有 `tabSession` 的 defaults → 升级后能开出原标签
- [ ] **2.12** 「在新窗口打开」得到独立窗且共享登录态（同站二次打开仍登录）

**验收（MW-2）**

- [ ] 设计稿 §7 会话相关项全部满足
- [ ] popup 默认仍为新标签（回归）

---

## Phase MW-3：资源与体验

**目标**：控制多窗内存上界；下载体验跨窗一致。

### 任务清单

- [ ] **3.1** `BrowserDownloadManager` 提升为应用级（AppDelegate 或 `+sharedManager`）；WindowController 只持有弱引用/观察者
- [ ] **3.2** ⌘J / toolbar badge：观察共享 manager；panel 挂在 key 窗口
- [ ] **3.3** 全局存活 WebView 预算（建议 12，可配置常量）；与窗口内 8 协同（先满足全局）
- [ ] **3.4** 休眠时优先非 key、非 main 窗口的闲置标签
- [ ] **3.5** `make stats-browser` 记录：1×NTP、3×NTP 窗、1 窗 3 存活页 — 写入验收小节或 acceptance 附录
- [ ] **3.6**（可选）系统「窗口」菜单标题同步为当前标签标题

**验收（MW-3）**

- [ ] 窗 A 开始的下载在窗 B 的下载面板可见
- [ ] 多窗同时打开大量标签时，存活 WebView 不超过全局上限

---

## Phase MW-4：联调与文档

### 任务清单

- [ ] **4.1** `make browser` / `make verify` 通过
- [ ] **4.2** 对照下方完整验收清单逐项勾选
- [ ] **4.3** 更新 `multi-window-design.md` 状态为已实现；勾选 roadmap M3「多窗口 + 窗口级会话」
- [ ] **4.4** 同步 `docs/README.md` 索引（若尚未加入）

---

## 完整验收清单

### 功能

- [ ] ⌘N 新建窗口（NTP）
- [ ] 多窗口独立标签条与地址栏
- [ ] ⌘T / ⌘W / ⌘⇧[ / ] / 缩放 只影响 key 窗口
- [ ] 关非最后浏览器窗，App 继续运行
- [ ] 关最后浏览器窗，App 退出
- [ ] 重启恢复多窗会话（含 selected / pinned）
- [ ] 旧 `tabSession` 迁移成功
- [ ] `target=_blank` 默认仍新标签
- [ ] 至少一种「在新窗口打开」路径可用
- [ ] 外链进入 key 窗口新标签
- [ ] 设置窗与浏览器窗互不抢会话槽

### 性能 / 体积

- [ ] 未新增框架依赖；二进制体积无明显上涨（目测/对比 build 产物即可）
- [ ] 多空窗（仅 NTP）内存远低于同等数量存活重页面
- [ ]（MW-3）全局休眠预算生效

### 回归

- [ ] 单窗口日常浏览、休眠唤醒、Launchpad、地址栏补全、下载（路径按阶段）正常
- [ ] 编辑菜单 ⌘C/V 等仍可用（`SBApplicationMenus`）

---

## 建议排期与合并策略

```
Week 1:  MW-0 → MW-1  （可合并为一次 PR：多窗口进程内可用）
Week 1–2: MW-2        （第二次 PR：会话 + 新窗口打开）
Week 2:  MW-3 → MW-4  （第三次 PR：资源打磨 + 文档）
```

若希望**一次交付完整能力**：按 MW-0→4 顺序在同一分支连续做完再合入，仍建议按阶段打 tag / 自测节点，避免会话与菜单问题纠缠。

---

## 实现时注意点（给开发者）

1. **不要**在 `BrowserWindowController init` 再装菜单。  
2. **不要**让每个窗口直接 `saveTabEntries:`；统一出口 `saveWindowSessions:`。  
3. 新窗口默认 NTP → **不要** `ensureWebView`，保持轻量。  
4. `createWebView` 收到的 `configuration` 参数：若将来真建 WebKit 子窗，再考虑使用；首版主动新窗口仍用窗内共享 configuration + defaultDataStore。  
5. 下载 hijack 与「Open in New Window」共用 WebKit 标识时，先判断下载再判断开窗（沿用现有 `consumePendingContextMenuDownloadURL` 顺序）。

---

## 参考

- [multi-window-design.md](multi-window-design.md)
- [multi-tab-design.md](multi-tab-design.md)
- [professional-features-roadmap.md](professional-features-roadmap.md)
