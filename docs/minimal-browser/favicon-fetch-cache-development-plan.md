# 快捷方式 Favicon 多渠道获取与缓存 — 开发计划

> 基于 [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md) 的分阶段实施计划。  
> 前置条件：Launchpad NTP-0～NTP-3 已完成；地址栏星标 `toggleBookmark:` 已接入 `BrowserShortcutStore`；`BrowserShortcutEditorSheet` 可编辑 `iconURLString`。  
> **状态：ICO-0～ICO-3 已完成（2026-07-14）；断网/连点等手测项见 acceptance。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase ICO-0 | 缓存与解析底座 | 完成 | `BrowserFaviconCache` + HTML 截断解析 + Makefile |
| Phase ICO-1 | 瀑布服务 + 星标触发 | 完成 | `BrowserFaviconService` 渠道 1～6；★ 加入回写 |
| Phase ICO-2 | 编辑按钮 + UI 统一消费 | 完成 | 「自动获取」；Cell/补全/四宫格走 Service |
| Phase ICO-3 | 联调验收 | 完成 | 构建通过、acceptance / 路线图同步 |

（延后能力见设计稿 §11 ICO-3，不纳入本计划勾选范围。）

---

## Phase ICO-0：缓存与解析底座

**目标**：磁盘/内存缓存与 HTML `link` 扫描可单测级复用，尚可不接 UI。

### 任务清单

- [x] **0.1** 新建目录 `SimpleBrowser/Favicon/`
- [x] **0.2** `BrowserFaviconCache.h/.m`
  - `cacheDirectoryURL` → `Application Support/MeoBrowser/Favicons/`
  - `blobs/` + `index.plist` 读写
  - API：`imageForHost:` / `storeImage:forHost:sourceURL:channel:` / `sourceURLForHost:` / `removeHost:`（测试用）
  - 落盘前将位图最长边缩至 ≤ 128（ImageIO 或锁定绘制）
- [x] **0.3** 内存 `NSCache`（host → `NSImage`），与磁盘一致优先读内存
- [x] **0.4** LRU：条目数 > 500 时按 `updatedAt` 删最旧 blob + index
- [x] **0.5** `BrowserFaviconHTMLParser.h/.m`
  - 输入：`NSData`（≤ 64 KB）+ 页面 `NSURL`
  - 输出：有序绝对图标 URL 列表（`icon` / `shortcut icon` / `apple-touch-icon*`）
  - 忽略 `data:`；相对路径 `NSURL URLWithString:relativeToURL:`
- [x] **0.6** 共享工具：`BrowserFaviconUtil`（`HostFromURLString` / `IsDecodableImageData` / PNG 缩放）
- [x] **0.7** Makefile：加入 `SimpleBrowser/Favicon/*.m` 与头文件搜索路径

### 建议自测（无 UI）

1. [x] 手工 `storeImage` → `clearMemoryCache` → `imageForHost` 能从磁盘读回  
2. [x] HTML 片段解析出绝对 icon URL（忽略 stylesheet / `data:`）  
3. [x] >64 KB data 截断后不崩

---

## Phase ICO-1：瀑布服务 + 星标触发

**目标**：统一编排渠道；地址栏 ★ 加入时 Silent 拉取并长期缓存。

### 任务清单

#### 1A — Service

- [x] **1.1** `BrowserFaviconService.h/.m` 单例
- [x] **1.2** `NSURLSession` 专用配置：单渠超时 6～8 s；禁止过度缓存干扰自测可用默认
- [x] **1.3** 渠道实现（按序，成功早停）：
  1. `disk`
  2. `well-known`（`/favicon.ico`、`/apple-touch-icon.png`、`/apple-touch-icon-precomposed.png`）
  3. `html-link`（GET 根或 pageURL，读 64 KB → Parser → GET 候选）
  4. `cravatar`
  5. `duckduckgo`
  6. `google`（`sz=64`）
- [x] **1.4** 响应体上限 512 KB；解码失败视本渠失败
- [x] **1.5** 全局并发 ≤ 2 + 同 host 在途合并（多 completion 共用一次瀑布）
- [x] **1.6** `BrowserFaviconDidUpdateNotification`（`object` 或 `userInfo[@"host"]`）
- [x] **1.7** `fetchAndCacheForPageURLString:preferredIconURL:reason:completion:`  
  - `Silent`：尊重 24 h 负缓存（`failures.plist`）  
  - `UserAction`：忽略负缓存  
  - `preferredIconURL` 非空时先验证下载该 URL，成功则当渠 0
- [x] **1.8** `imageForPageURLString:preferredIconURL:triggerFetch:completion:` 供 UI 显示

#### 1B — 星标接入

- [x] **1.9** `BrowserWindowController toggleBookmark:`  
  - **加入**分支：现有 `addShortcut…` 后调用 Silent `fetchAndCache`  
  - completion：若 shortcut 仍在 store，则 `updateIconURLString:matchingURLString:` + UI 刷新
- [x] **1.10** **移除**分支不触发 fetch；不删磁盘缓存
- [x] **1.11** 加入后立即 UI 响应，不因网络等待星标切换

#### 1C — 自测清单

- [x] **1.12** 冒烟：`example.com` 瀑布成功（cravatar）并回写磁盘；二次 fetch 磁盘命中  
- [ ] **1.13** 断网冷启动手测（ICO-2/3 联调时再勾）  
- [ ] **1.14** 虚构域名手测（失败静默）  
- [ ] **1.15** 快速连点 ★ 手测

---

## Phase ICO-2：编辑按钮 + UI 统一消费

**目标**：手动「自动获取」与各展示面统一走 Service；去掉重复加载器。

### 任务清单

#### 2A — 编辑 Sheet

- [x] **2.1** `BrowserShortcutEditorSheet`：图标行改为 `NSStackView`（预览 + `iconURLField` + 「自动获取」）
- [x] **2.2** 校验 `urlField` → UserAction fetch；忙时禁用按钮、文案「获取中…」
- [x] **2.3** 成功：`iconURLField.stringValue = sourceURL`；清错误
- [x] **2.4** 失败：`errorLabel`「未能获取图标，可手动填写」
- [x] **2.5** Sheet 关闭时 `cancelFetchForHost:`
- [x] **2.6** 字段旁 32×32 `NSImageView` 预览
- [x] **2.7** 面板尺寸调整为 460×300

#### 2B — 展示侧统一

- [x] **2.8** `BrowserShortcutCellView`：删除私有 `BrowserShortcutIconLoader`，改调 `BrowserFaviconService`（`triggerFetch=YES`）
- [x] **2.9** 监听 `BrowserFaviconDidUpdateNotification`，host 匹配时刷新
- [x] **2.10** `BrowserShortcutSuggestionPanel`：走 Service，`triggerFetch=NO`（不风暴）
- [x] **2.11** 文件夹四宫格 `BrowserShortcutFolderTileView` 同一 Service 路径

#### 2C — 数据一致性

- [x] **2.12** 惰性拉取成功后 `BrowserShortcutStore updateIconURLString:matchingURLString:`
- [x] **2.13** 清空图标链接仍可保存；显示回落首字母占位（磁盘缓存保留）

---

## Phase ICO-3：联调与验收

### 任务清单

- [x] **3.1** `make browser` 通过（verify 随发布检查）
- [x] **3.2** 对照 [设计稿 §11](favicon-fetch-cache-design.md#11-分期与验收) ICO-1 / ICO-2 勾选
- [x] **3.3** 更新 [acceptance.md](acceptance.md) 追加 Favicon 验收表
- [x] **3.4** 更新 [professional-features-roadmap.md](professional-features-roadmap.md) §3.3 / M2 Favicon 条目状态与链接
- [x] **3.5** 更新 [new-tab-launchpad-design.md](new-tab-launchpad-design.md) §8 指向本稿
- [x] **3.6** 本计划 ICO-0～ICO-2 勾选完成；ICO-3 文档项完成（手测断网/连点可后续补）

### 发布检查

```bash
make clean && make browser && make verify
make run-browser
```

手工回归：

1. ★ 加入百度 / GitHub → 图标出现且重启仍在  
2. 编辑快捷方式 →「自动获取」填入链接 → 保存 → Launchpad 显示  
3. 断网打开新标签 → 已缓存图标仍可见  
4. 补全面板左侧图标与 Launchpad 一致（同 host）  
5. 文件夹四宫格中有图标的子项显示缩略而非全字母  

---

## 实现文件

```text
新建:
  SimpleBrowser/Favicon/BrowserFaviconService.h/.m
  SimpleBrowser/Favicon/BrowserFaviconCache.h/.m
  SimpleBrowser/Favicon/BrowserFaviconHTMLParser.h/.m

修改:
  SimpleBrowser/BrowserWindowController.m
  SimpleBrowser/NewTab/BrowserShortcutEditorSheet.m
  SimpleBrowser/NewTab/BrowserShortcutCellView.m
  SimpleBrowser/AddressBar/BrowserShortcutSuggestionPanel.m
  SimpleBrowser/NewTab/BrowserShortcutStore.h/.m   # 可选辅助：updateIconURL for matching URL
  Makefile

文档:
  docs/minimal-browser/favicon-fetch-cache-design.md
  docs/minimal-browser/favicon-fetch-cache-development-plan.md
  docs/minimal-browser/acceptance.md
  docs/minimal-browser/professional-features-roadmap.md
  docs/minimal-browser/new-tab-launchpad-design.md
```

---

## 依赖关系

```
ICO-0 Cache + Parser
    └── ICO-1 Service + 星标
            └── ICO-2 Sheet 按钮 + Cell/补全统一
                    └── ICO-3 验收（文档）
```

不阻塞：壁纸 BG-*、文件夹已交付部分。  
标签栏 favicon、页面加载顺手缓存 → 设计稿延后 ICO-3，另开迭代。

---

## 预估

| 阶段 | 粗估 |
|------|------|
| ICO-0 | 0.5～1 日 |
| ICO-1 | 1～1.5 日 |
| ICO-2 | 0.5～1 日 |
| ICO-3 | 0.5 日 |
| **合计** | **约 2.5～4 日** |

---

## 完成定义（DoD）

1. `make browser` / `make verify` 通过  
2. 行为符合 [favicon-fetch-cache-design.md](favicon-fetch-cache-design.md) ICO-1 + ICO-2  
3. 无 hidden `WKWebView` 用于拉图标  
4. 快捷方式 JSON / UserDefaults 中成功项带可复用的 `iconURL`；磁盘 `Favicons/` 有对应 blob  
5. 第三方全挂时产品仍可用（字母占位）  
