# 页面爬虫（Page Scraper）— 分阶段开发计划

> 基于 [page-scraper-design.md](page-scraper-design.md)（**已确认定稿**）。  
> 侧栏 UI 优化：[page-scraper-sidebar-ui-plan.md](page-scraper-sidebar-ui-plan.md)（方案已定，待实现）。  
> 前置：trailing 侧栏槽、Chrome Actions、SBKit 文本控件、`LoginAssistScriptMessageProxy`、Keychain 用法可参考 ServerSync。  
> 状态：方案已定；**代码已接入主工程并可编译**（侧栏 / 引擎 / 导出 / helper 初版），细项验收见各阶段勾选

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 产品名 | 页面爬虫；目录 `SimpleBrowser/Scraper/`；前缀 `BrowserScraper*` |
| 入口 | chrome `pageScraper` + 侧栏；可选菜单「查看 → 页面爬虫」 |
| 侧栏槽 | `BrowserTrailingSidebarKindScraper`；与通知 / 助手 / 历史 / PagePack 互斥 |
| 点选 | `BrowserScraperElementPicker`；handler `meoScraperPick` |
| 模式 | `scalar` / `table` |
| 翻页 | none / nextButton / pageNumbers / loadMore / infiniteScroll |
| 会话 | 默认 `reuseProfile`；可选 `ephemeral` |
| 定时 | `MeoScrapeRunner` + LaunchAgent；NDJSON spill |
| 落盘 | CSV / XLSX / JSON；MySQL append/replace/upsert |
| 输入控件 | `SBTextField` / `SBSecureTextField` / `SBTextView` |

**本期按 PS-0～PS-4 推进；Link follow（列表→详情）标为 PS-5，另开迭代。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| **PS-0** | 模型 + Store + 侧栏壳 + 入口 | **初版完成** | 可开关侧栏；Recipe 落盘 CRUD |
| **PS-1** | 点选 + 抽取 + 预览 + 文件导出 | **初版完成** | 单页 Scalar/Table → CSV/XLSX/JSON |
| **PS-2** | 翻页 + 运行控制 + 日志 | **初版完成** | 四种翻页；暂停/停止；spill |
| **PS-3** | MySQL sink | **初版完成** | Keychain + mysql CLI 建表/写入 |
| **PS-4** | Helper 定时 + 会话可配置 | **初版完成** | LaunchAgent；`MeoScrapeRunner` 入 bundle |
| **PS-5** | Link follow（二期） | 未开始 | 列表 URL → 详情字段 |

---

## Phase PS-0：模型 + Store + 侧栏壳 + 入口

### 任务

1. 新建 `SimpleBrowser/Scraper/`：`BrowserScraperModels`（Recipe / Field / Pagination / Sink / Schedule / Run meta）  
2. `BrowserScraperRecipeStore`：`Application Support/MeoBrowser/Scraper/recipes/` + `index.json`；原子写盘；导入/导出单个 JSON  
3. `BrowserScraperSettings`：侧栏宽度、保留 run 数（默认 20）  
4. `BrowserTrailingSidebarSlot` 增加 `Scraper` kind 与 `setScraperVisible:animated:`  
5. `BrowserScraperSidebarController`：空壳分段 UI（本页/字段/翻页/任务/保存占位）、宽度约束、关闭  
6. `BrowserChromeActionItem` 增加 `pageScraper`（`doc.text.magnifyingglass`，tooltip「页面爬虫」，`toggles=YES`）  
7. `BrowserWindowController`：挂载侧栏、`wireChromeActionButtons`、`togglePageScraperSidebar:`、`syncChromeActionButtonStates`  
8. Makefile 纳入新 `.m`；`make browser` 通过  

### 验收

- [ ] 点击爬虫图标打开右侧栏，再开 PagePack/助手时爬虫侧栏关闭（互斥）  
- [ ] 新建并保存空 Recipe，重启 App 后仍在  
- [ ] chrome 按钮 `on` 状态与侧栏可见同步  
- [ ] 侧栏内测试输入框为 SBKit 控件，⌘C/⌘V 可用  

---

## Phase PS-1：点选 + 抽取 + 预览 + 文件导出

### 任务

1. `BrowserScraperElementPicker`：注入 hover/click；`meoScraperPick` + Proxy；container / field 模式；Esc 取消  
2. WC / Sidebar delegate：`scraperSidebarCurrentWebViewForPicking:`（对齐 Assist/PagePack）  
3. `BrowserScraperDetector`：JS 启发式返回表格/列表候选（selector、估计行数、样本列名）  
4. 默认字段推断：table thead / 首行；scalar 名称/值/链接  
5. `BrowserScraperEngine` 最小集：当前 WebView 单页 `extract`；结果写 run 目录 NDJSON + 预览缓冲  
6. 侧栏：候选列表、选择数据区、字段表编辑、预览 20 行、「复制预览」  
7. `BrowserScraperExcelWriter`：NDJSON → CSV；JSON；XLSX（真 xlsx 或 Excel 可开的 CSV/SpreadsheetML，以设计 §10 为准）  
8. 「立即运行」（单页）→ 下载目录出文件 → 可选 `NSWorkspace` 揭示  

### 验收

- [ ] 手动点选 `<table>`，预览列名与行数据正确  
- [ ] Scalar：点选节点得到默认三字段（缺链接可空），可改名/改 kind  
- [ ] 「检测数据」列出至少一种候选并可一键采用  
- [ ] 导出 CSV 与 JSON；Excel 可打开对应产物  
- [ ] 点选结束后页面无残留高亮 class  

---

## Phase PS-2：翻页 + 运行控制 + 日志

### 任务

1. `BrowserScraperPaginationDriver`：`nextButton` / `pageNumbers` / `loadMore` / `infiniteScroll`  
2. 侧栏翻页分段：类型、点选选择器、maxPages、maxRows、pageDelayMs、waitForSelector、waitTimeoutMs、滚动参数  
3. Engine 循环：抽 → spill append → 翻页 → 等待；支持 pause / cancel  
4. 去重（`dedupeKeyFieldIds`）、空行过滤、URL 绝对化  
5. 运行条：页/行计数、日志 `SBTextView` 或只读列表、「暂停」「停止」  
6. 单次 JS 抽取行数封顶 + 多批，避免超大桥接 payload  

### 验收

- [ ] nextButton：maxPages=3 时行数约为单页×3（站点结构允许时）  
- [ ] infiniteScroll：滚动后行数增加，达 maxRows 停止  
- [ ] 运行中点「停止」→ 不再翻页；已 spill 行可导出  
- [ ] 同 key 去重后导出无重复行  
- [ ] 长列表下主进程内存不明显随行数线性涨（抽样：预览缓冲有上限）  

---

## Phase PS-3：MySQL sink

### 任务

1. Keychain 存 MySQL 密码（account 与 Recipe 关联）；侧栏 `SBSecureTextField`  
2. `BrowserScraperMySQLWriter`：连接、`CREATE TABLE IF NOT EXISTS`（TEXT 列）、append / replace / upsert  
3. 侧栏保存分段：host/port/database/user/table/writeMode/upsertKeys；「测试连接」  
4. Makefile 可选 `MEO_ENABLE_MYSQL=1`；未启用时 UI 禁用并提示  
5. 失败路径：超时、鉴权失败写 run log，不崩 App  

### 验收

- [ ] 测试连接成功/失败有明确反馈  
- [ ] 两轮 append 后表行数累加  
- [ ] replace 需确认且表内容为最新一轮  
- [ ] upsert 按键更新已存在行  
- [ ] Recipe JSON 中无明文密码  

---

## Phase PS-4：Helper 定时 + 会话可配置

### 任务

1. 编 `MeoScrapeRunner` CLI（bundle `Contents/MacOS/`）：`--recipe-id=`，加载 Store，离屏/无窗 `WKWebView`，跑 Engine+Sink，exit code  
2. `BrowserScraperScheduleManager`：安装/卸载 LaunchAgent（`StartInterval`）；label `com.example.MeoBrowser.scrape.{id}`  
3. 侧栏任务分段：启用定时、间隔分钟、起止（可选）；写 plist 需用户授权场景按 macOS 惯例处理  
4. `session`：`reuseProfile` vs `ephemeral` 在 Engine/Helper 创建 DataStore 时生效  
5. 文件锁：同一 recipe 前台与 helper 互斥  
6. 可选：完成/失败系统通知 category `MEO_SCRAPER_RUN`  
7. Run 目录保留策略：超过 N 删最旧  

### 验收

- [ ] 启用间隔定时后，Activity Monitor 可见 `MeoScrapeRunner` 周期性出现并退出  
- [ ] helper 不拉起完整多窗口 UI（或仅最小化离屏）  
- [ ] 连续多次定时后主 MeoBrowser 进程内存无阶梯上涨  
- [ ] `ephemeral` 任务不使用登录 Cookie（用需登录页验证抽不到或抽到未登录态）  
- [ ] 前台正在跑时 helper 跳过并留 log  

---

## Phase PS-5（二期）：Link follow

### 任务

1. 字段标记 `isLinkFollowSource`  
2. 引擎：先收集 URL 列表（可上限），再逐 URL 打开详情抽取 detail fields  
3. 侧栏：详情字段编辑、并发度=1（稳妥）、详情延迟  
4. 与翻页组合：列表翻页 + 每页 follow  

### 验收

- [ ] 列表页抽 5 条链接 → 详情标题写入同一行扩展列  
- [ ] 详情失败单行记错误列，不中断整任务  

---

## 依赖与顺序

```text
PS-0 → PS-1 → PS-2 → PS-3
                ↘
                 PS-4（可与 PS-3 并行，但 Engine spill 须先在 PS-2 就绪）
PS-5 依赖 PS-1 字段模型 + PS-2 引擎循环
```

## 非目标（本计划不包含）

- 云端爬虫农场、代理池、验证码破解  
- 完整可视化 sitemap 画布  
- Postgres / 云存储直连  
- Chrome 扩展兼容层  

---

## 文档维护

实现每完成一阶段，将本文件对应「状态」改为完成并勾选验收项；同步更新 [page-scraper-design.md](page-scraper-design.md) 文首状态与 [professional-features-roadmap.md](professional-features-roadmap.md) §3.9 条目。
