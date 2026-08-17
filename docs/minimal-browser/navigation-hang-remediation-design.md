# 导航卡顿 / 卡死治理 — 设计方案

> 目标：打开不可达网址、失效资源、需代理的境外资源时，**不再拖慢甚至卡死整个应用**；坏标签可单独中止/丢弃，其它标签与窗口保持可点可切。  
> 状态：**NH-0～NH-4 已实现**；NH-5 可选。开发计划见 [navigation-hang-remediation-development-plan.md](navigation-hang-remediation-development-plan.md)。  
> 关联：[design.md](design.md) · [multi-tab-design.md](multi-tab-design.md) · [multi-window-design.md](multi-window-design.md) · [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md) §3.7「崩溃/卡死恢复」  
> 代码基线：`BrowserWebView` 主文档 `timeoutInterval=12s`、`BrowserWindowController` provisional watchdog、`BrowserTab` 休眠、`BrowserNavigationErrorView`

---

## 1. 问题定义

### 1.1 用户体感

| 场景 | 典型表现 |
|------|----------|
| 地址栏打开不可达主机（DNS 失败、无路由、需代理） | 进度条/转圈长时间不结束；切换标签或点工具栏变「钝」 |
| 主文档已出，但页面狂拉境外/失效子资源 | 标签一直 `isLoading`；窗口响应尚可，但刷新/停止语义混乱 |
| 多标签同时踩坏站 | 感觉「整个 App 卡死」——多数时候是 **UI 进程被同步等待占满**，或 **WebKit 回调风暴/沉默** 叠加进度 UI |

### 1.2 根因分层（必须分清，否则会误造「多进程引擎」）

MeoBrowser 是 **AppKit UI 进程 + 系统 WebKit（Network / WebContent / GPU）**。页面文档已由 WebKit 在独立进程加载；**应用层无法也不应再自研一套浏览器多进程模型**。

卡顿/卡死应拆成三类，分别治理：

| 类型 | 含义 | 典型来源 | 应用层能做什么 |
|------|------|----------|----------------|
| **A. 真·主线程阻塞** | AppKit 事件循环停转，窗口拖不动、菜单打不开 | `dispatch_sync` 撞忙队列、钥匙串/UA 采样在主线程自旋等待、磁盘 IO 同步读 | **彻底消除**主线程上的网络/磁盘同步等待 |
| **B. 假死·加载永不结束** | UI 仍可点，但进度条/停止按钮语义错误，用户以为卡死 | provisional 未回调、watchdog 未挂上、commit 后子资源挂起、`isLoading` 幽灵态 | **导航代际 + 全覆盖超时 + 强制 stop** |
| **C. WebKit 侧僵死** | 某标签 WebContent/Network 会话异常，回调长期沉默 | 极端 TLS/代理/进程 hang | **标签级硬恢复**：`stopLoading` → 丢弃 WebView（休眠）→ 错误页 |

> **产品承诺（可验收）**：任意坏标签在约定时限内进入「可恢复的失败态」；**其它标签切换、新开标签、地址栏输入、关闭窗口不得被该标签拖死**。

### 1.3 明确不做

| 不做 | 理由 |
|------|------|
| 自研 NetworkProcess / 自建 Chromium 式多进程 | 与「原生 WebKit」定位冲突，工期与兼容性不可控 |
| 默认每个标签独立 `WKProcessPool` | 会拆散 Cookie/登录态；与现有多窗「共享 defaultDataStore」冲突 |
| 用 `NSURLProtocol` / 私有 SPI 拦截全部子资源 | 脆弱、MAS/系统升级易碎 |
| 对每个导航先完整 HEAD 再加载（默认路径） | 增加 RTT，拖慢正常站；探测应 **短超时、可选、失败不阻塞乐观加载** |
| 为「加速」关闭系统代理 / 忽略用户网络偏好 | 安全与可预期性优先 |

---

## 2. 现状基线（与代码对齐）

### 2.1 已有能力（保留并扩展）

| 能力 | 位置 | 说明 |
|------|------|------|
| 主文档请求超时夹紧 | `BrowserWebView.requestByApplyingNavigationTimeout:` | `BrowserMainFrameNavigationTimeout = 12s`（注释：默认 60s 对不可达主机过久） |
| Provisional 看门狗 | `BrowserWindowController` `scheduleProvisionalNavigationWatchdog…` | 仅在 `didStartProvisionalNavigation` 后启动；到期 `stopLoading` + 超时错误页 |
| 原生错误页 | `BrowserNavigationErrorView` | 失败不再弹 NSAlert 挡交互 |
| 标签休眠 | `BrowserTab` / `BrowserTabController` | 销毁 WebView ≈ 释放该标签 WebContent；预算 8/窗、12/全局 |
| 旁路网络超时 | Favicon 8s、Feed 4s、Sync 30s | 与主文档管道分离 |

### 2.2 关键缺口

```text
loadURL / loadRequest
        │
        ▼
   ┌─ 缺口1：此处尚无「导航代际 / 总超时」─────────────────────────┐
   │  若 WebKit 迟迟不回调 didStartProvisional，12s 看门狗永不启动   │
   └────────────────────────────────────────────────────────────────┘
        │
        ▼
didStartProvisional ──► 现有 12s provisional watchdog（有效）
        │
        ▼
didCommit ──► 取消 provisional watchdog
        │
   ┌─ 缺口2：commit 后无「文档仍 isLoading」上限 ───────────────────┐
   │  子资源/XHR 挂死 → 进度条与 tab.isLoading 长期异常               │
   └────────────────────────────────────────────────────────────────┘
        │
   ┌─ 缺口3：无「硬恢复」阶梯 ──────────────────────────────────────┐
   │  stopLoading 无效时，不会自动 hibernate 该标签 WebView           │
   └────────────────────────────────────────────────────────────────┘

另：主线程偶发 sync（UA 采样、Keychain、FaviconCache dispatch_sync）→ 类型 A
Favicon 后台 FOREVER 信号量 → 坏站风暴时占满 utility 队列 → 间接拖慢
```

### 2.3 进程现实（方案约束）

```text
┌─ MeoBrowser UI 进程（AppKit）──────────────────────────────────┐
│  窗口 / 标签栏 / 地址栏 / 错误页 / 看门狗 / 探测调度               │
│  禁止：同步等网络；禁止：为坏站阻塞其它标签逻辑                    │
└────────────────────────────┬───────────────────────────────────┘
                             │ XPC（系统）
┌────────────────────────────▼───────────────────────────────────┐
│  WebKit NetworkProcess / WebContent / GPU（系统托管）            │
│  应用可控手段：loadRequest · stopLoading · 销毁 WKWebView        │
│  （可选高级）风险标签临时独立 process pool —— 默认关闭             │
└────────────────────────────────────────────────────────────────┘
```

**「不同网页单独进程、不影响主进程」在本产品中的正确落地** =  
WebKit 已有隔离 + **UI 进程零阻塞** + **标签级超时/硬杀** + **旁路网络与主文档解耦**。  
不是再开一个「浏览器内核进程」。

---

## 3. 总体架构

### 3.1 一句话

以 **导航代际（Navigation Generation）** 为轴，叠 **四级超时阶梯 + 并行快速探测 + 主线程净化 + 旁路网络限流**；坏标签可在时限内失败或被丢弃，**绝不占用 UI 进程等待**。

### 3.2 核心组件

| 组件 | 职责 |
|------|------|
| **`BrowserNavigationSession`** | 每次 `loadURL`/`reload` 分配 `generation`；绑定 tabID、目标 URL、阶段时间戳；所有 watchdog/探测回调校验 generation |
| **`BrowserNavigationWatchdog`** | 统一调度四级超时（见 §4）；替代散落的单一 provisional `dispatch_after` |
| **`BrowserReachabilityProbe`** | 短超时、后台队列的「快速探测」；**不阻塞** WK 乐观加载（见 §5） |
| **`BrowserTabLoadIsolator`** | 硬恢复：`stopLoading` → 展示错误 → 必要时 `hibernate` 丢弃 WebView；保证其它标签不受影响 |
| **主线程审计清单** | UA / Keychain / FaviconCache 等改为纯异步或有限超时后台（见 §6） |
| **旁路网络卫士** | Favicon/Feed 等：有限并发、禁止 `DISPATCH_TIME_FOREVER`、统一 session 超时 |

### 3.3 数据流（目标态）

```text
用户提交 URL
  │
  ├─① 创建 NavigationSession(generation=N)
  ├─② 立即 schedule：总超时 T0（从 load 起算，覆盖「无 provisional」）
  ├─③ 后台启动 ReachabilityProbe（≤ Tp，可取消）
  └─④ 同时 WKWebView loadRequest（乐观加载，夹紧 timeoutInterval）
        │
        ├─ probe 明确不可达（DNS/连接拒绝）且仍未 commit
        │     → 可选「快速失败」：stopLoading + 错误页（见 §5.3 策略）
        │
        ├─ didStartProvisional → 进入阶段 P；刷新 provisional 截止时间
        ├─ didCommit → 取消 P；进入阶段 C（文档加载上限）
        ├─ didFinish / didFail → 取消全部；generation 完结
        │
        └─ 任一阶段超时 → stopLoading → 错误页
              └─ 仍僵死（可选）→ hibernate WebView + 保留 restorableURL + 错误页「已停止」
```

---

## 4. 四级超时阶梯

常量建议集中到 `BrowserNavigationTimeouts.h`（名称可微调），**可偏好覆盖，默认如下**：

| 级别 | 符号 | 默认 | 起点 | 动作 |
|------|------|------|------|------|
| **T0 总导航** | `BrowserNavigationOverallTimeout` | **15s** | `loadRequest` / `loadURL` 调用瞬间 | 覆盖「从未 provisional」；`stopLoading` + TimedOut 错误页 |
| **T1 Provisional** | `BrowserMainFrameNavigationTimeout`（已有 12s） | **12s** | `didStartProvisional` | 与现有行为对齐；可与 T0 取较早者触发 |
| **T2 Commit 后文档** | `BrowserDocumentLoadGraceTimeout` | **20s** | `didCommit` | 若 `isLoading` 仍为真：`stopLoading`，**保留已渲染文档**，仅清除加载 UI（不整页错误，除非尚无有效内容） |
| **T3 硬恢复** | `BrowserStuckWebViewHardRecoverTimeout` | **T0/T1 失败后再 +8s** 或用户点「强制停止」 | stop 后仍无任何回调 / UI 无响应指标 | `hibernate` 该标签 WebView，错误页提供「重新加载」 |

### 4.1 行为细则

1. **代际校验**：超时回调必须核对 `session.generation == tab.currentGeneration`，避免旧导航误杀新导航。  
2. **取消点**：`didCommit`（取消 T0/T1）、`didFinish`/`didFail`/`stopLoading` 用户主动停止、标签关闭、hibernate。  
3. **T2 语义**：commit 后页面往往已可交互；子资源挂死不应整页换成错误 interstitial，而应：
   - 停止网络；
   - `tab.isLoading = NO`；进度条复位；
   - 可选轻量 toast/状态栏「部分资源加载超时」（首版可仅清加载态）。  
4. **用户停止（Esc / 工具栏）**：立刻 cancel 全部 watchdog + probe；`stopLoading`；清加载 UI；若尚无 commit 则展示「已取消」或保留空白/前页。  
5. **与 hash/`__meo_hf` 幽灵 isLoading**：保留现有 `window.stop()` 与 commit 后 poll 清进度逻辑；T2 作为兜底，避免与 hash 恢复打架（hash 恢复完成后应已 clear generation 或标记 `ignoreDocumentGrace`）。

### 4.2 与「境外资源」的关系

- **主文档不可达**：T0/T1 + 探测快速失败 → 错误页（可提示检查代理，复用现有 `userFacingMessageForNavigationErrorCode:`）。  
- **主文档可达、子资源境外挂起**：T2 截断加载态，**不**为每个 img/XHR 建应用层超时（WebKit 不暴露稳定公开钩子）。  
- 若未来需要更强子资源控制：走 **内容拦截器 / 站点策略**（另案），不纳入本方案首版。

---

## 5. 快速探测机制（Reachability Probe）

### 5.1 目标

在 **≤ 1～2s** 内给出「主机是否明显不可达」的弱信号，用于：

- 更快失败（减少空等 12～15s 的体感）；
- 错误文案更准（DNS vs 连接超时 vs 可能需代理）；
- **绝不**拖慢可达站点的首字节路径。

### 5.2 推荐算法（首版）

**名称**：乐观加载 + 并行探测（Optimistic Load + Parallel Probe）

```text
主路径：立刻 WK loadRequest（零等待）
并行：在全局并发限制的 utility 队列上：

  1) 解析 host（已是 IP 则跳过 DNS）
  2) DNS：getaddrinfo / nw_connection 解析，硬限 Tp_dns = 1.0s
  3) 若方案为 https：对 host:443（或 URL.port）建 TCP（或 nw_connection），
     硬限 Tp_tcp = 1.5s；不完成完整 TLS 握手也可（TCP 通即「可达弱信号」）
  4) 总探测预算 Tp_total = 2.0s；超时 → 探测结果 = Unknown（不干预 WK）
```

实现建议优先 **Network.framework**（`nw_connection_t`）或现有可依赖的轻量 API；放在 `BrowserReachabilityProbe.m`，**禁止**在主线程 wait。

### 5.3 探测结果如何影响导航（策略开关）

| 探测结果 | 默认策略（推荐） | 激进策略（偏好可选） |
|----------|------------------|----------------------|
| **Unknown**（超时/未完成） | 不干预，等 T0/T1 | 同左 |
| **DNSFailed** | 若尚未 commit：`stopLoading` + DNS 错误页（快速失败） | 同左 |
| **ConnectRefused / Unreachable** | 若尚未 commit：快速失败 | 同左 |
| **Reachable** | 取消「快速失败」候选；WK 继续 | 同左 |
| **TLS 失败**（若做了 TLS） | 不快速失败（交给 WK 证书流程） | — |

**禁止**：探测成功才允许 `loadRequest`（会让正常站至少多 1 RTT）。  
**禁止**：探测用 `NSURLSession` 拉完整首页 HTML（浪费、易被挑战页误导）。

### 5.4 并发与取消

- 全局同时进行的 probe ≤ **4**（与 favicon 限流同级思想）。  
- 导航结束 / 代际变更 / 用户停止 → 立即 cancel connection。  
- 同一 host 短时间（如 5s）内探测结果可内存缓存，避免多标签同时打开同坏站打爆解析。

### 5.5 与系统代理

探测必须走 **系统代理设置**（`nw_parameters` 尊重 proxy / 或使用会走代理的 API）。  
否则「浏览器能开、探测说不行」或相反，会误伤。若某 API 难尊重代理：该通道降级为 Unknown，**宁可不快速失败**。

---

## 6. UI 进程净化（类型 A）

### 6.1 强制规则

1. **主线程禁止**等待网络完成（含 `semaphore_wait` FOREVER、同步 `NSURLSession`）。  
2. **主线程禁止**对可能执行磁盘/网络的串行队列 `dispatch_sync`（Favicon 缓存 IO 是高发点）。  
3. 若 API 必须同步（极少）：仅允许 **有上限** 的本地内存命中；未命中走异步回调刷新 UI。

### 6.2 已知审计点（实现阶段逐项勾掉）

| 位置 | 风险 | 治理 |
|------|------|------|
| `BrowserUserAgent.sampleDefaultUserAgent` | 主线程 runloop + semaphore 最长 ~2s | 启动预热到后台；主路径只用缓存 UA；采样失败用静态 Safari 对齐串 |
| `LoginCredentialStore` / `ServerSyncKeychain` | 主线程泵 runloop 等钥匙串 | 异步 API；UI 显示 loading/禁用按钮，不自旋 |
| `BrowserFaviconCache` `dispatch_sync(ioQueue)` | 主线程撞磁盘 | 改为 async；或仅 sync「纯内存字典」 |
| `BrowserFaviconService` `DISPATCH_TIME_FOREVER` | 坏站占满后台链 | 改为 channel 超时（已有 8s）+ wait 上限；失败继续下一渠 |

### 6.3 交互隔离（产品层）

- 标签切换、拖拽、菜单、地址栏编辑：**不得**等待任何标签的 `didFinish`。  
- 进度条 / `tab.isLoading` 仅绑定 **当前选中标签** 的 session（后台标签转圈可保留小指示，但不阻塞主线程）。  
- 错误页 per-WebView（已有），确保不弹模态挡全窗。

---

## 7. 标签级硬隔离与「类多进程」体验

### 7.1 软隔离（默认，足够大多数场景）

每个标签独立 `WKWebView` + 独立 `NavigationSession` + 独立 watchdog。  
坏标签超时只 `stopLoading` 该实例。

### 7.2 硬隔离（僵死恢复）

当 T3 触发或用户「强制停止此标签」：

1. `cancel` session / probe / watchdog  
2. `[webView stopLoading]`  
3. 从视图层级移除；`BrowserTab hibernate`（销毁 WebView，保留 `restorableURL` / 标题）  
4. 展示错误页或占位：「页面无响应，已停止。可重新加载」  
5. 重新加载 = `ensureWebView` + 新 generation + `loadURL`

这在效果上等于 **杀掉该标签的 WebContent**，而不动其它标签——即用户要的「单独进程互不影响」在 WK 模型下的可实现形态。

### 7.3 可选：风险标签独立 Process Pool（默认关）

| 项 | 说明 |
|----|------|
| 开关 | 设置「隔离高风险标签的网络进程」（默认 **OFF**） |
| 触发 | 用户手动「在隔离标签中打开」；或探测连续失败域名（可选，易误伤） |
| 代价 | Cookie/登录不共享；实现与测试成本高 |
| 首版 | **只写扩展点，不默认开启**；优先做 §4–§6 |

与现有 `WKPreferencesSetProcessSwapOnNavigationEnabled(false)`（反爬连续性）并存：隔离 pool 是「标签间」隔离，process-swap 是「同 WebView 导航间」策略，文档中注明勿混用概念。

---

## 8. 旁路网络与加载效率

| 管道 | 策略 |
|------|------|
| 主文档 | 乐观 WK 加载 + 并行探测 + 四级超时 |
| Favicon | 有限并发、有限 wait、host 级负缓存（失败 5～10min 内不重打） |
| Feed 探测 | 保持短超时；不在主文档关键路径同步等待 |
| 下载 | 已走 `WKDownload`；失败不影响导航 session |
| 同步 / Companion | 独立 session；超时已有；不得 `dispatch_sync` 回主线程等响应 |

**负缓存**：对 DNSFailed / Unreachable 的 host 记录短 TTL，地址栏再次提交同 host 时可直接错误页或缩短 T0（需在 UI 提供「仍要访问」绕过）。

---

## 9. 用户可见行为

### 9.1 工具栏

| 状态 | 按钮 |
|------|------|
| 加载中 | 显示「停止」；Esc 停止当前选中标签导航 |
| 停止后 / 错误页 | 「重新加载」 |
| 硬恢复后 | 「重新加载」重建 WebView |

### 9.2 错误文案（复用并扩展）

- 超时 / 不可达 / DNS：沿用并微调 `userFacingMessageForNavigationErrorCode:`（代理提示保留）。  
- 探测快速失败：与正式失败使用同一套文案，避免两套语气。  
- T2 截断：默认不换错误页。

### 9.3 诊断（Debug / 可选菜单）

日志字段：`tabID`、`generation`、`phase`、`url`、`probeResult`、`watchdogLevel`、`elapsed`。  
便于区分类型 A/B/C，避免再靠猜。

---

## 10. 模块与文件规划

| 文件 | 说明 |
|------|------|
| `SimpleBrowser/Navigation/BrowserNavigationTimeouts.h` | 超时常量 |
| `SimpleBrowser/Navigation/BrowserNavigationSession.h/.m` | 代际与阶段 |
| `SimpleBrowser/Navigation/BrowserNavigationWatchdog.h/.m` | 四级调度（可先放 WindowController 再抽） |
| `SimpleBrowser/Navigation/BrowserReachabilityProbe.h/.m` | 并行探测 |
| `SimpleBrowser/Navigation/BrowserTabLoadIsolator.h/.m` | 硬恢复 / hibernate 封装 |
| 修改 `BrowserWebView.m` | 保持 timeout 夹紧；load 入口登记 session |
| 修改 `BrowserWindowController.m` | 用统一 watchdog 替换仅 provisional 逻辑；停止/错误路径接 generation |
| 修改 `BrowserTab.m` / `BrowserTabController.m` | 硬恢复与 hibernate 衔接 |
| 修改 Favicon / UA / Keychain | 主线程净化（可分 PR） |
| 可选设置项 | 「导航超时」「启用快速探测」「失败 host 负缓存」 |

Makefile：增加 `Navigation/*.m` 与 `-I`（与 Developer 模块相同模式）。

---

## 11. 风险与兼容

| 风险 | 缓解 |
|------|------|
| 探测误判导致过早 stop | 默认仅 DNSFailed/Unreachable 快速失败；Reachable/Unknown 不干预；可用偏好关闭快速失败 |
| T2 过早 stop 打断 SPA | T2 仅清加载态；阈值站点可排除；hash 恢复路径标记豁免 |
| 硬恢复丢未提交表单 | 错误页文案说明；仅僵死路径自动 hibernate |
| 代理环境探测不准 | 探测尊重系统代理；失败则 Unknown |
| 与反爬 / process-swap | 不默认独立 pool；不改变现有 process-swap 关闭策略 |

---

## 12. 验收标准（方案级）

1. **不可达主机**：从提交 URL 起 ≤ **15s**（快速探测命中时更短）进入错误页；期间可切换其它标签、输入地址栏、开新标签。  
2. **主线程**：Instruments Time Profiler 下，坏站加载期间主线程无 >100ms 的同步网络/钥匙串等待（抽样）。  
3. **多标签**：标签 A 加载坏站时，标签 B 滚动/点击不出现整窗事件循环停转。  
4. **子资源挂起**：commit 后 ≤ T2 清除加载指示；页面已有内容可继续浏览。  
5. **硬恢复**：模拟 stop 无回调时，T3 或手动强制停止后该标签 WebView 销毁，其它标签 WebView 仍存活。  
6. **正常站回归**：example.com / 常用文档站首屏时间不明显劣于改动前（探测并行、不阻塞 load）。  
7. **代理提示**：需代理才能访问的失败场景，错误文案仍可读。

---

## 13. 阶段划分（摘要）

| 阶段 | 名称 | 价值 |
|------|------|------|
| **NH-0** | 导航代际 + T0 总超时 + 停止路径加固 | 堵住「无 provisional」空等；立刻改善卡死感 |
| **NH-1** | T2 文档宽限 + 加载 UI 一致性 | 解决子资源拖进度条 |
| **NH-2** | 并行快速探测 + host 负缓存 | 不可达站秒级失败 |
| **NH-3** | 硬恢复（hibernate）+ 诊断日志 | 真·标签隔离体验 |
| **NH-4** | 主线程净化 + 旁路网络限流 | 消灭类型 A 真卡顿 |
| **NH-5** |（可选）设置项 + 隔离 Process Pool 扩展点 | 高级用户 |

详细任务与工期见开发计划。

---

## 14. 决策记录

| 决策 | 结论 |
|------|------|
| 是否自建多进程浏览器 | **否**；强化 WK 标签级生命周期与 UI 零阻塞 |
| 加载是否等探测完成 | **否**；乐观加载 + 并行探测 |
| 子资源能否应用层逐个超时 | **否**（首版）；用 T2 截断加载态 |
| 默认独立 WKProcessPool | **否**；可选扩展 |
| 错误是否用模态 Alert | **否**；保持 per-tab 原生错误页 |

---

## 15. 参考代码锚点

- `SimpleBrowser/Tabs/BrowserWebView.m` — `BrowserMainFrameNavigationTimeout`、`requestByApplyingNavigationTimeout:`  
- `SimpleBrowser/BrowserWindowController.m` — `scheduleProvisionalNavigationWatchdog…`、`fireProvisionalNavigationWatchdog:`、`handleNavigationError:`  
- `SimpleBrowser/Tabs/BrowserTab.m` — hibernate / `ensureWebView` / `isLoading`  
- `SimpleBrowser/Tabs/BrowserTabController.m` — live WebView 预算  
- `SimpleBrowser/Security/BrowserNavigationErrorView.*` — 错误 interstitial  
- `SimpleBrowser/Favicon/BrowserFaviconService.m` / `BrowserFaviconCache.m` — 旁路网络与 sync 风险  
- `SimpleBrowser/BrowserUserAgent.m` — UA 采样等待  
