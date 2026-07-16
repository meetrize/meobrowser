# 反风控与会话稳定 — 开发计划

> 基于 [anti-bot-session-design.md](anti-bot-session-design.md) 的分阶段实施计划。  
> 前置：多窗口 + `defaultDataStore`、标签休眠、登录助手内联（IF）已可用。  
> **状态：AB-0～AB-4 已完成（2026-07-16）**  
> Cursor 计划：`.cursor/plans/anti-bot-session.plan.md`

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| UA 策略 | **完整 `customUserAgent`**，进程内缓存；去掉写死 `Version/18.0` |
| UA 来源 | 同进程临时 `WKWebView` 采样默认 UA，再规范为含 `Version/… Safari/…` |
| 休眠保护 | 空闲计时 **跳过** 保护 host；内存压力下 **最后** 才休眠保护标签 |
| 默认保护/抑制 host | `google.com`、`googleapis.com`、`gstatic.com`、`recaptcha.net`、`cloudflare.com`、`hcaptcha.com`、`baidu.com`（后缀匹配） |
| URL 启发式抑制 | path 含 `/sorry/`、host 含 `challenges.cloudflare` 等 → 强制抑制 |
| `accounts.google.com` | V1 **整域 `google.com` 抑制**登录助手 |
| 清除网站数据 | 确认框：**清除全部** / **清除当前站点**；保留原全清 API |
| 自定义 UA 设置 UI | **不做**（留给路线图） |
| 多 Profile | **不做** |
| 指纹伪装 | **不做** |
| 提交信息 | 用户要求 commit 时用简体中文 |

未决项若变更，先改设计稿 §9，再回写本表。

---

## 总览

| 阶段 | 名称 | 对应设计 | 状态 | 产出 |
|------|------|----------|------|------|
| Phase AB-0 | 动态 Safari 对齐 UA | §4.1 | **完成** | `BrowserUserAgent` + 接线 |
| Phase AB-1 | 风险域休眠保护 | §4.3 | **完成** | `BrowserRiskHostPolicy` + TabController |
| Phase AB-2 | 登录助手抑制 | §4.4 | **完成** | Detector 脚本 + Runner 拒绝 |
| Phase AB-3 | 按站清除 + 设置提示 | §3.2 / §4.2 | **完成** | Prefs API + Settings UI |
| Phase AB-4 | 文档与验收 | §7 | **完成** | acceptance / README / verify |

建议节奏：AB-0 → AB-1 → AB-2 可连续交付（风控主路径）；AB-3 独立；AB-4 收尾。每阶段结束执行 `make browser`。

---

## Phase AB-0：动态 Safari 对齐 UA

**目标**：消除写死 `Version/18.0 Safari/605.1.15`；所有标签使用同一、与本机 WebKit 合理对齐的 UA。

### 任务清单

- [x] **0.1** 新建 `SimpleBrowser/BrowserUserAgent.h/.m`
- [x] **0.2** `+ (NSString *)safariAlignedUserAgent`：`dispatch_once` 缓存
- [x] **0.3** 实现采样：临时 `WKWebView`（可用 offscreen / 不加入层级）读取默认 UA；若缺 `Safari/` 则补齐 `Version/x Safari/y`（从 `AppleWebKit/` 或系统版本推导的策略写进注释）
- [x] **0.4** `BrowserWindowController` `configureWebViewConfiguration:`：删除硬编码 `applicationNameForUserAgent`；改为在创建 WebView 时设置 `customUserAgent`（或 configuration 层等价路径）
- [x] **0.5** 确认 `BrowserTab` / `ensureWebView` / popup 采用路径均拿到同一 UA
- [x] **0.6** Makefile 链入 `BrowserUserAgent.m`
- [x] **0.7** `make browser`；手测：任意页 `navigator.userAgent` 含合理 `Version/` 与 `Safari/`，且无陈旧写死 18.0（除非本机确为该版本）

### 完成标准

- 源码中不再出现字面量 `Version/18.0 Safari/605.1.15`。  
- 多窗口、新标签 UA 一致。

### 实现提示

- 采样 WebView 勿泄漏到界面；用完可释放。  
- 若仅改 `applicationNameForUserAgent` 也能动态化，须在 PR/提交说明中写明为何未用 `customUserAgent`，并保证 Version 动态。

---

## Phase AB-1：风险域休眠保护

**目标**：Google 等保护站不因 10 分钟空闲被销毁 WebView；内存压力下仍可最终回收。

### 任务清单

- [x] **1.1** 新建 `SimpleBrowser/BrowserRiskHostPolicy.h/.m`
- [x] **1.2** API：`+ (BOOL)hostIsHibernationProtected:(NSString *)host`；`+ (BOOL)URLIsHibernationProtected:(NSURL *)url`
- [x] **1.3** 后缀匹配实现（`foo.google.com` → 命中 `google.com`）；nil/空安全
- [x] **1.4** 默认名单写入常量（设计稿 §4.3）；单测级可在注释或小函数中覆盖边界（`www.google.com`、`notgoogle.com` 不命中）
- [x] **1.5** `BrowserTabController` 空闲 hibernate 循环：保护 URL **continue**
- [x] **1.6** 全局/窗内预算淘汰：排序时保护标签优先级最低（最后 hibernate）
- [x] **1.7** Makefile 链入；`make browser`
- [x] **1.8** 手测：打开 Google，切到其他标签闲置 >10 分钟，Google 标签仍存活（未超预算时）

### 完成标准

- 非保护站休眠行为与改前一致。  
- 保护站空闲不被误杀；极端多标签时仍能回收。

---

## Phase AB-2：登录助手抑制

**目标**：风险域 / `/sorry/` 页无内联钥匙、不自动一键登录、Runner 拒绝执行。

### 任务清单

- [x] **2.1** `BrowserRiskHostPolicy` 增加：`hostShouldSuppressLoginAssist:`、`URLShouldSuppressLoginAssist:`（含 path 启发式 `/sorry/` 等）
- [x] **2.2** `LoginFormDetector` 嵌入 JS：若 `location` 命中抑制，则 **不**插入按钮、不 `formDetected`（或立即 teardown）
- [x] **2.3** 导航变更后：Native 在 `didFinish`（或现有刷新匹配处）若抑制，则清除 `hasDetectedLoginForm`、禁用工具栏登录强调
- [x] **2.4** `LoginAssistController` / `LoginRunner`：抑制域执行前 return + Toast 说明
- [x] **2.5** 确认全局 Pref 关闭内联时行为不变
- [x] **2.6** `make browser`；手测：`google.com/sorry/` 或普通 google 搜索页无钥匙图标；测试页 `login-assist-test.html` 仍有助手

### 完成标准

- 抑制域零注入痕迹（无 `meo-login-assist-btn`）。  
- 非抑制登录测试页功能回归通过。

### 实现提示

- 优先设计稿路径 **A**（脚本内判断），改动面小。  
- Toast 文案简体中文，一句即可。

---

## Phase AB-3：按站清除 + 设置提示

**目标**：避免用户误清全部 Cookie；补充 VPN/清除后果提示。

### 任务清单

- [x] **3.1** `BrowsingPreferences`：`+ clearWebsiteDataForHost:completion:`（`fetchDataRecordsOfTypes` → 过滤 → `removeDataOfTypes:forDataRecords:`）
- [x] **3.2** host 匹配容错：`www.` 前缀、空 host 拒绝并回调错误
- [x] **3.3** `BrowserSettingsWindowController`：清除确认改为双操作（全部 / 当前站点）；无当前 URL 时禁用「当前站点」或回退提示
- [x] **3.4** 增加简短说明 label（清除后果 + VPN 一句）
- [x] **3.5** 可选：按钮「复制当前 User-Agent」（读 `BrowserUserAgent` 或当前 WebView）
- [x] **3.6** 确认清除 **不**动 Recipe/Keychain
- [x] **3.7** `make browser`；手测：仅清当前站后其他站登录态仍在

### 完成标准

- 全清与按站清路径分明；文案可见。  
- LoginAssist 数据不受影响。

---

## Phase AB-4：文档与验收

**目标**：文档状态、索引、acceptance 与构建门禁对齐。

### 任务清单

- [x] **4.1** 更新 `anti-bot-session-design.md` / 本文件阶段状态为完成日期
- [x] **4.2** `docs/README.md` 已含条目则核对描述；`professional-features-roadmap.md`「自定义 UA」处互链「默认 UA 已对齐」
- [x] **4.3** `acceptance.md` 增加「反风控与会话稳定」手测表
- [x] **4.4** `captcha-assist-design.md` / `auto-login-design.md` 顶部关联本方案（若尚未加）
- [x] **4.5** `make browser && make verify`
- [x] **4.6** 将 `.cursor/plans/anti-bot-session.plan.md` todos 标为 completed

### 完成标准

- 文档可检索；构建通过；手测表可执行。

---

## 手测清单（汇总）

| # | 步骤 | 期望 |
|---|------|------|
| 1 | 任意 https 页控制台/书签看 `navigator.userAgent` | 含 Version + Safari；非写死过期 18.0（除非本机匹配） |
| 2 | 新窗口 + 新标签 | UA 与第一窗一致 |
| 3 | Google 搜索页 | 无登录助手内联按钮 |
| 4 | Google 标签后台 >10 min（标签总数未爆预算） | WebView 仍在或切回无明显「整站冷启动」（网络面板无整页重请优先） |
| 5 | 普通新闻站后台 >10 min | 仍可按原逻辑休眠 |
| 6 | `login-assist-test.html` | 内联助手与一键登录正常 |
| 7 | 设置 → 清除当前站点 | 仅当前 host 存储清除 |
| 8 | 设置 → 清除全部 | 全站数据清；Recipe 仍在 |

---

## 依赖与冲突

| 依赖 | 说明 |
|------|------|
| WebKit / AppKit | 仅用公开 API |
| Login Assist | AB-2 改 Detector/Controller；勿破坏 Recipe 存储 |
| 多窗口休眠预算 | AB-1 必须与 `kMaxLiveWebViewsGlobal` 逻辑兼容 |

| 冲突 | 处理 |
|------|------|
| 未来「自定义 UA」设置 | AB-0 提供默认生成器；设置覆盖时优先用户值（预留钩子即可，V1 可不做 UI） |
| Captcha Assist | 不共享抑制名单语义；Google `/sorry/` 默认人工 |
