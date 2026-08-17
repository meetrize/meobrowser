# 导航卡顿 / 卡死治理 — 开发计划

> 基于 [navigation-hang-remediation-design.md](navigation-hang-remediation-design.md)。  
> 状态：**NH-0～NH-4 已落地（代码，2026-08-17）**；NH-5 可选。手测验收项待勾。  
> 前置：多标签、provisional 12s watchdog、`BrowserNavigationErrorView`、标签休眠已就绪。  
> 路线图：[professional-features-roadmap.md](professional-features-roadmap.md) §3.7

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 加载策略 | **乐观 WK 加载**；探测并行，**不**阻塞 `loadRequest` |
| T0 总超时 | 从 `loadURL`/`loadRequest` 起 **15s**；覆盖「从未 provisional」 |
| T1 Provisional | 保持现有 **12s**（`BrowserMainFrameNavigationTimeout`） |
| T2 Commit 后 | **20s** 仍 `isLoading` → `stopLoading` + 清加载 UI，**默认不换错误页** |
| T3 硬恢复 | stop 后仍僵死或用户强制停止 → hibernate 该标签 WebView |
| 快速失败 | 仅当探测为 DNSFailed / Unreachable **且尚未 commit** |
| 独立 Process Pool | 首版 **不做**；仅预留注释/扩展点 |
| 错误 UI | 继续 per-WebView 原生错误页；禁止 NSAlert 挡导航失败 |
| 主线程 | 新代码禁止 sync 等网络；NH-4 清存量 |

---

## 总览

| 阶段 | 名称 | 预估 | 产出 |
|------|------|------|------|
| Phase NH-0 | 代际 + T0 + 停止加固 | 1～1.5 日 | 无 provisional 也能超时；Esc/停止可靠 |
| Phase NH-1 | T2 文档宽限 + 加载态一致 | 0.5～1 日 | 子资源挂不死进度条 |
| Phase NH-2 | 并行探测 + 负缓存 | 1～1.5 日 | 不可达站快速失败 |
| Phase NH-3 | 硬恢复 + 诊断日志 | 1 日 | 坏标签可丢弃 WebView |
| Phase NH-4 | 主线程净化 + 旁路限流 | 1～2 日 | 消灭真卡顿源 |
| Phase NH-5 | 设置项（可选） | 0.5 日 | 超时/探测开关 |

**建议首版交付：NH-0 + NH-1 + NH-2 + NH-3（约 4～5 人日）。**  
NH-4 强烈建议同迭代或紧随其后；NH-5 可按需。

---

## Phase NH-0：导航代际 + T0 总超时 + 停止加固

**目标**：每次导航从 `load` 起算即有超时；用户停止立即生效；其它标签逻辑不依赖坏站回调。

**落地**：`SimpleBrowser/Navigation/`（Timeouts / Session / Watchdog）；`BrowserTab` 代际；`BrowserWindowController` 统一 T0+T1；加载中刷新钮变停止；Esc 停止。

### 任务清单

#### 0A — Session 与超时常量

- [x] **0.1** 新建 `SimpleBrowser/Navigation/BrowserNavigationTimeouts.h`
  - `BrowserNavigationOverallTimeout` = 15
  - 保留/声明 `BrowserMainFrameNavigationTimeout`（12，可仍定义在 WebView 或挪到此头并让 WebView include）
  - `BrowserDocumentLoadGraceTimeout` = 20（NH-1 再用）
  - `BrowserStuckWebViewHardRecoverDelay` = 8（NH-3 再用）
- [x] **0.2** 新建 `BrowserNavigationSession.h/.m`
  - 字段：`generation`、`tabID`、`URL`、`phase`（Idle/Loading/Provisional/Committed）、`startTime`
  - `BrowserTab`（或 WindowController）持有 `currentNavigationSession`
- [x] **0.3** Makefile：编译 `Navigation/*.m`，头文件搜索路径对齐其它子目录

#### 0B — 统一 Watchdog（先覆盖 T0 + 现有 T1）

- [x] **0.4** 新建 `BrowserNavigationWatchdog`（或先私有实现在 `BrowserWindowController`，但接口要清晰）
  - `startOverallForWebView:session:`（T0）
  - `startProvisional…`（迁入现有逻辑）
  - `cancelAllForWebView:` / `cancelAllForSession:`
  - 回调前校验 `generation`
- [x] **0.5** `BrowserTab loadURL:` / `loadRequest` 路径：创建新 session → **立刻** `startOverall`
- [x] **0.6** `didStartProvisional`：更新 phase → `startProvisional`（可与 T0 并存，谁先到谁触发）
- [x] **0.7** `didCommit` / `didFinish` / `didFail` / 错误页展示：`cancel` 相关 watchdog；完结 session
- [x] **0.8** 移除或瘦身旧 `BrowserProvisionalNavigationWatchdog` 仅 provisional 映射，避免双轨

#### 0C — 停止与错误路径

- [x] **0.9** 工具栏停止 / Esc：`cancel` session+watchdog+（预留）probe → `stopLoading` → 清 `tab.isLoading` / 进度条
- [x] **0.10** T0/T1 触发：与现 `fireProvisionalNavigationWatchdog` 一致 → TimedOut 错误页；忽略随后 Cancelled
- [x] **0.11** `beginMainFrameNavigation` 与 generation 对齐，防止子 frame 误开 T0

#### 0D — 验收 NH-0

- [ ] **0.12** 不可达主机（拔网或 `http://172.16.0.1` 类）：≤15s 出错误页，即使日志无 `didStartProvisional`
- [ ] **0.13** 加载中切到其它标签，再切回：UI 不卡；停止只影响原标签
- [ ] **0.14** 正常站（example.com）可完成加载；无误报超时
- [x] **0.15** `make browser` 通过

---

## Phase NH-1：T2 文档宽限 + 加载态一致

**目标**：主文档 commit 后，子资源挂起不再让进度条/停止按钮「永久加载中」。

**落地**：`BrowserNavigationWatchdog` T2；`didCommit` 取消 T0/T1 并启动宽限（默认 20s，`__meo_hf` 为 3s）；到期 `stopLoading` + 清加载 UI、不换错误页；停止按钮看选中标签 session。

### 任务清单

- [x] **1.1** `didCommit`：取消 T0/T1；启动 T2（`BrowserDocumentLoadGraceTimeout`）
- [x] **1.2** T2 触发：`stopLoading`；`tab.isLoading=NO`；进度条 `resetHidden`；**不**展示「无法加载页面」（已有实质内容时）
- [x] **1.3** `didFinish` / 用户停止：取消 T2
- [x] **1.4** 与 `__meo_hf` / `window.stop()` 幽灵加载：commit 后现有 poll 保留；对 hash 恢复导航设 `suppressDocumentGrace` 或短宽限，避免误 stop SPA
- [x] **1.5** 统一 `updateReloadStopButton`：仅看选中标签 session 是否活跃
- [ ] **1.6** 验收：构造慢/挂起子资源页（或本地 fixture）→ commit 后 ≤20s 加载态消失，页面仍可滚动

---

## Phase NH-2：并行快速探测 + host 负缓存

**目标**：明显不可达主机在约 2s 内快速失败；可达站零额外等待。

**落地**：`BrowserReachabilityProbe`（Network TCP、并发≤4、预算 2s；系统代理介入则跳过）；`BrowserHostNegativeCache`（TTL 8min）；错误页「仍要访问」清负缓存；开关 `MeoBrowserQuickReachabilityProbe` 默认 YES。

### 任务清单

#### 2A — Probe

- [x] **2.1** 新建 `BrowserReachabilityProbe.h/.m`
  - 输入：NSURL；输出回调：Reachable / DNSFailed / Unreachable / Unknown
  - Network.framework（或等价）；**尊重系统代理**；总预算 ≤2s
  - 可 cancel；全局并发 ≤4
- [x] **2.2** `loadURL` 时并行 `startProbe`；结果回调主线程时校验 generation + 未 commit
- [x] **2.3** DNSFailed / Unreachable → `stopLoading` + 对应错误文案（走现有 userFacing 映射）
- [x] **2.4** Unknown / Reachable → 不干预
- [x] **2.5** 偏好或编译期开关：`MeoBrowserQuickReachabilityProbe` 默认 **YES**

#### 2B — 负缓存

- [x] **2.6** 内存负缓存：host → (reason, expiry)；TTL 建议 5～10min
- [x] **2.7** 命中负缓存：可直接错误页或缩短 T0（定稿：**直接错误页** + 错误页「仍要访问」清除该 host 负缓存并重试）
- [ ] **2.8** 验收：连续打开同坏 host，第二次立即失败；正常站探测不增加可感知延迟；关开关后行为回退为纯 T0/T1

---

## Phase NH-3：硬恢复 + 诊断

**目标**：`stopLoading` 无效时仍能丢掉坏 WebView，其它标签不受影响。

**落地**：`BrowserTabLoadIsolator`；T0/T1 后若 stop 无效武装 T3（8s）；菜单「强制停止此标签」；`pendingHardRecover` 错误页 + 重新加载重建 WebView；`[MeoNav]` 诊断日志（Debug 默认开）。

### 任务清单

- [x] **3.1** `BrowserTabLoadIsolator` 或 Tab 方法：`forceAbandonWebViewWithMessage:`  
  - stop → hibernate → 错误页/占位 → 保留 `restorableURL`
- [x] **3.2** T3：T0/T1 触发后若 N 秒内仍异常（可选启发式）或菜单「强制停止此标签」→ isolator
- [x] **3.3** 重新加载：新 WebView + 新 generation + load
- [x] **3.4** Debug 日志：generation / phase / probe / watchdog level（`NSLog` 或现有日志宏；Release 可降级）
- [ ] **3.5** 验收：休眠预算下硬杀标签 A，标签 B WebView 指针仍有效且可导航；重启不要求（会话仍按 restorable）

---

## Phase NH-4：主线程净化 + 旁路限流

**目标**：消灭类型 A 真卡顿；坏站风暴不占满后台链。

**落地**：UA 启动后台预热、主路径只读缓存/fallback；Favicon 主线程禁 sync 读盘、semaphore ≤9s、负缓存 TTL 10min；钥匙串主线程预算 0.25s + ServerSync 启动预热。

### 任务清单

- [x] **4.1** `BrowserUserAgent`：启动后台预热；主路径只读缓存；失败静态 fallback；移除主线程长时间 runloop 等待
- [x] **4.2** `BrowserFaviconCache`：主线程 API 改为 async 或仅内存 hit 同步
- [x] **4.3** `BrowserFaviconService`：所有 `DISPATCH_TIME_FOREVER` 改为有上限；失败 host 短负缓存
- [x] **4.4** Keychain 包装：登录/同步相关主线程调用改为异步 completion（按调用点分批，避免大爆炸重构）
- [ ] **4.5** 验收：Instruments 下打开不可达 URL，主线程无长时间 semaphore/sync IO；多标签连开坏站时 UI 可拖动窗口

---

## Phase NH-5：设置项（可选）

- [ ] **5.1** 设置「网络」或「高级」：启用快速探测、导航超时秒数（限制合理范围 8～30）
- [ ] **5.2** 文案说明：探测失败不会在探测成功前推迟打开页面
- [ ] **5.3**（文档扩展点）隔离 Process Pool — 仅说明，不做 UI

---

## 建议实现顺序与分支策略

```text
NH-0 → NH-1 → NH-2 → NH-3   （功能主链，可同一 PR 或按阶段 PR）
              ↘ NH-4 可并行（触碰 Favicon/UA，注意冲突）
```

每阶段结束执行：

1. `make browser`  
2. 手测：坏站、正常站、代理提示、多标签切换、Esc 停止  
3. 更新本文件勾选状态

---

## 测试矩阵（发布前）

| # | 场景 | 期望 |
|---|------|------|
| T1 | `https://非存在域名.invalid` | 快速失败或 ≤15s 错误页；可切标签 |
| T2 | 未代理访问明确需代理的境外站 | 超时/错误页 + 代理相关文案；App 不卡死 |
| T3 | 本地 `python -m http.server` 正常页 | 无误超时 |
| T4 | 主文档快、子资源挂起（慢端口） | commit 后 ≤T2 清加载态 |
| T5 | 加载中 Esc | 立即停；可再输入 URL |
| T6 | 标签 A 坏站 + 标签 B 浏览 | B 流畅 |
| T7 | 硬恢复后重新加载 | 新 WebView 成功打开可达站 |
| T8 | 带 `#fragment` / `__meo_hf` 导航 | 无回归幽灵加载/误超时 |
| T9 | 多窗各一坏标签 | 两窗均可操作 |

---

## 工期与里程碑

| 里程碑 | 内容 | 合计 |
|--------|------|------|
| M1 | NH-0 + NH-1 | ~2 日 |
| M2 | + NH-2 + NH-3 | 再 ~2～2.5 日 |
| M3 | NH-4 | 再 ~1～2 日 |
| M4 | NH-5 可选 | ~0.5 日 |

**M2 完成后即可宣称「坏站不再拖死应用」的产品验收；M3 完成后类型 A 真卡顿基本清零。**
