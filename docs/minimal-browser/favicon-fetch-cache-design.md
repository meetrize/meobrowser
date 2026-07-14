# 快捷方式 Favicon 多渠道获取与缓存 — 设计方案

> 目标：为起始页快捷方式提供**多渠道保底**的 favicon 获取能力；在地址栏星标「加入收藏」时自动拉取，并在快捷方式编辑对话框提供「自动获取」；结果**磁盘缓存、长期复用**。  
> 状态：**ICO-0～ICO-2 已完成**（2026-07-14）；ICO-3 联调/验收文档待勾。开发计划见 [favicon-fetch-cache-development-plan.md](favicon-fetch-cache-development-plan.md)  
> 前置依赖：[new-tab-launchpad-design.md](new-tab-launchpad-design.md)（NTP-0～NTP-3）、地址栏星标（`toggleBookmark:`）、`BrowserShortcutEditorSheet`  
> 路线图归位：`professional-features-roadmap.md` §3.3「Favicon 显示」P1

---

## 1. 方案定位

### 1.1 做什么

| 层级 | 名称 | 能力 |
|------|------|------|
| **ICO-1** | MVP 管道 + 星标触发 | 统一 `BrowserFaviconService`；瀑布渠道；星标加入时后台拉取并回写 `iconURLString` + 磁盘缓存 |
| **ICO-2** | 编辑对话框 + 消费统一 | 「自动获取」按钮；Launchpad / 补全 / 文件夹四宫格统一走缓存；失败保持首字母占位 |
| ICO-3 | 延后 | 标签栏 favicon；打开页面时从 `WKWebView` 顺手缓存；用户可清缓存；渠道开关 |

**本方案首版交付目标：ICO-1 + ICO-2。**

### 1.2 不做什么

- 不为每个快捷方式预建 hidden `WKWebView`（与 Launchpad 设计 §8 一致）
- 不在首次打开 App 时对全部默认快捷方式批量狂爬（避免启动风暴；可惰性：首次显示 cell 时若无缓存再拉）
- 不把第三方服务做成硬依赖：全部失败仍显示首字母占位
- 不引入独立「书签库」；星标仍 = `BrowserShortcutStore` 快捷方式
- 首版不做 SVG→位图复杂管线（若下载内容无法解码为 `NSImage`，视为该渠道失败并继续下一渠）

### 1.3 原则

1. **一次拉取，处处复用** — 按 **host**（小写、去默认端口）做主缓存键；内存 + 磁盘双层。  
2. **渠道瀑布、早停** — 任一渠成功即停止后续网络请求。  
3. **UI 不阻塞** — 星标加入立即完成；图标异步到位后刷新。  
4. **可手改优先** — 用户在编辑框手动填写的图标链接优先；「自动获取」可覆盖并回写表单。  
5. **禁 WebView 爬头** — 直取图标或轻量 `NSURLSession` 读 HTML 前缀即可。

---

## 2. 用户场景

### 2.1 地址栏星标加入

```
浏览 https://example.com/docs
  → 点击地址栏右侧 ★（空心）
  → 立即写入 BrowserShortcutStore（title/url，iconURL 可先空）
  → 星标变为实心黄；Launchpad 若可见则出现新格（可先字母占位）
  → 后台 BrowserFaviconService 按瀑布拉取
  → 成功：写磁盘缓存 + 回写该 shortcut.iconURLString（或缓存命中键）+ 通知刷新
  → 失败：保持占位，不弹错误（静默）
```

取消星标（实心 → 空心）时：**删除快捷方式项**；磁盘 favicon 缓存可保留（按 host，供再次收藏或补全复用），不必立即删文件。

### 2.2 编辑对话框「自动获取」

```
Launchpad 编辑态 → 编辑快捷方式…
  → 「图标链接」右侧有按钮「自动获取」
  → 以「网址」字段为准启动瀑布（网址无效则在 sheet 内提示）
  → 按钮进入忙碌态（禁用 + 简短文案「获取中…」）
  → 成功：iconURLField 填入可用图标 URL（或 file URL / 约定本地键）；可选小预览
  → 失败：errorLabel「未能获取图标，可手动填写」；占位策略不变
  → 用户仍需点「保存」才持久化 shortcut（与现网一致）
```

**添加快捷方式** sheet 共用同一按钮逻辑。

### 2.3 长期复用

```
曾为 github.com 拉过图标
  → 磁盘命中后不再走网络
  → Launchpad cell / 地址栏补全 / 文件夹四宫格子缩略共用同一缓存 API
  → 重启 App 后仍可从磁盘秒开
```

---

## 3. 渠道瀑布（Resolve Pipeline）

按顺序尝试，**成功即停**。任一渠：超时 / 非 2xx / 无法解码图片 / 尺寸无效 → 下一渠。

| 序号 | 渠道 ID | 策略 | 说明 |
|------|---------|------|------|
| 0 | `manual` | 调用方传入的显式 `preferredIconURL` | 用户已填图标链接时先验证下载；失败再进后续 |
| 1 | `disk` | 按 host 读本地缓存 | Silent 命中且够清晰则直接用；「自动获取」跳过磁盘强制重拉 |
| 2 | `google` | **网络优先** | `https://www.google.com/s2/favicons?domain={host}&sz=64`（实践上最清晰） |
| 3 | `site` | 站点 HTML + 约定路径 | `<link rel=icon/apple-touch-icon>` 按 sizes 降序，再 apple-touch / favicon.ico |
| 4 | `cravatar` | 国内第三方兜底 | `https://cn.cravatar.com/favicon/api/index.php?url={host}` |
| 5 | `duckduckgo` | 海外兜底 | `https://icons.duckduckgo.com/ip3/{host}.ico` |
| — | `none` | 全部失败 | completion 返回 `nil`；UI 保持首字母占位 |

### 3.1 渠道约束

| 项 | 建议 |
|----|------|
| 单渠超时 | 6～8 s（`NSURLSession` 配置） |
| 整条瀑布总预算 | ≤ 25 s；超时整体失败 |
| 并发 | 全局队列最多 **2** 条活跃瀑布（星标狂点 / 多 cell 惰性加载时排队） |
| 单次响应体上限 | 图标 **512 KB**；HTML 截断 **64 KB** |
| 允许 MIME | `image/*`；ICO 常见为 `image/x-icon` / `image/vnd.microsoft.icon` / `application/octet-stream`（有解码结果即认） |
| 禁止 | 重定向到明显非图标的超大 HTML（靠尺寸/解码失败丢弃） |

### 3.2 第三方服务说明

- 均为**非官方、无 SLA** 接口；任一侧不可用属预期，靠后续渠道与占位兜底。  
- 国内优先 `cravatar`，再海外，降低 Google 不通时的空白率。  
- 请求仅带 host（或站点 URL），不附带 Cookie / 用户浏览历史。  
- ICO-3 可做成偏好开关「允许使用第三方图标服务」。

### 3.3 HTML 解析范围（渠道 3）

只关心：

```html
<link rel="icon" href="...">
<link rel="shortcut icon" href="...">
<link rel="apple-touch-icon" href="...">
<link rel="apple-touch-icon-precomposed" href="...">
```

选型启发式（可选简化实现）：

1. 优先带 `sizes` 且接近 32～128 的 PNG/ICO；  
2. 否则第一个合法 `href`；  
3. 忽略 `data:` URL（首版可不支持）。

**不做**：完整 DOM、JS 执行、Service Worker、JSON 清单以外的复杂 discovery（Web App Manifest 列为 ICO-3）。

---

## 4. 缓存模型

### 4.1 键

```
cacheKey = lowercase(host)
```

- 从 shortcut URL / 页面 URL 解析 `NSURL.host`；忽略 `user`/`password`/`path`/`query`。  
- `www.` **保留**为键的一部分（与现网书签 URL 一致即可）；若归一化策略与 `BrowserShortcutStore` 主机展示冲突，以「URL 的 host 字面」为准并在文档中固定。  
- 无 host（非法 URL）→ 不缓存、不请求。

### 4.2 目录布局

```
~/Library/Application Support/MeoBrowser/
└── Favicons/
    ├── index.plist          # host → 元数据
    └── blobs/
        ├── <sha256前16>.png # 统一转存的显示图（建议 64×64 @2x 可视，最长边 ≤ 128）
        └── ...
```

`index.plist` 条目示例：

```xml
<!-- 逻辑结构 -->
{
  "github.com": {
    "fileName": "a1b2c3d4e5f60789.png",
    "sourceChannel": "well-known",
    "sourceURL": "https://github.com/favicon.ico",
    "updatedAt": 1720900000,
    "etag": "",           // 可选，ICO-3
    "byteSize": 2048
  }
}
```

偏好与快捷方式列表仍在 `NSUserDefaults`；**像素文件只进 Application Support**（与壁纸方案一致）。

### 4.3 内存层

| 层 | 实现 | 限制 |
|----|------|------|
| 热缓存 | `NSCache`（key=host 或绝对 icon URL） | countLimit ≈ 128；单图解码约数 KB～百 KB |
| 在途去重 | host → 等待中的 completion 数组 | 同 host 并发只发一条瀑布 |

现有 `BrowserShortcutCellView` 内私有 `BrowserShortcutIconLoader`（仅内存 URL→Image）应**收编或改调**本服务，避免双套逻辑。

### 4.4 与 `iconURLString` 的关系

| 情况 | `BrowserShortcutItem.iconURLString` | 磁盘缓存 |
|------|-------------------------------------|----------|
| 用户手动填写远程 URL | 存该 URL | 首次显示下载后按 host 落盘 |
| 自动获取成功 | 回写**可长期使用的 URL**：优先远程 `sourceURL`；若仅第三方可拿图则写第三方 URL，或写 `file://.../blobs/xxx.png`（二选一，实现锁定一种） | 必写 |
| 获取失败 | 保持 `""` | 不写失败标记也可；避免「永久黑名单」误伤（可选负缓存 TTL 见 §4.5） |

**首版推荐回写策略**：  
成功后 `iconURLString = sourceURL`（真实图标地址）；显示时始终 `BrowserFaviconService`：先 disk(host)，再 `iconURLString` GET，失败再瀑布。这样卸载缓存目录后仍可按 URL 恢复。

### 4.5 负缓存（可选，ICO-1 可简）

| 项 | 建议 |
|----|------|
| 全渠道失败 | 记录 `failedAt`，**24 h** 内星标静默路径不再重试 |
| 编辑「自动获取」 | **忽略**负缓存，强制重试 |
| 清除 | ICO-3「清除图标缓存」删 blobs + index |

### 4.6 容量

| 项 | 值 |
|----|-----|
| 单 host 一文件 | 覆盖写入 |
| 总文件数软上限 | 500；超出按 `updatedAt` LRU 删 |
| 单文件上限 | 解码前 ≤ 512 KB；落盘前缩到最长边 128 |

---

## 5. API 设计（建议）

### 5.1 `BrowserFaviconService`（单例）

```objc
typedef NS_ENUM(NSInteger, BrowserFaviconFetchReason) {
    BrowserFaviconFetchReasonSilent,    // 星标、cell 惰性：失败无 UI
    BrowserFaviconFetchReasonUserAction // 编辑「自动获取」：可提示；忽略负缓存
};

@interface BrowserFaviconService : NSObject
+ (instancetype)sharedService;

/// 显示用：优先磁盘 / 内存；没有则可选 triggerFetch
- (void)imageForPageURLString:(NSString *)pageURLString
              preferredIconURL:(nullable NSString *)iconURLString
                   triggerFetch:(BOOL)triggerFetch
                     completion:(void (^)(NSImage * _Nullable image))completion;

/// 完整瀑布；成功写入磁盘并可选回写 shortcut
- (void)fetchAndCacheForPageURLString:(NSString *)pageURLString
                      preferredIconURL:(nullable NSString *)preferredIconURL
                                reason:(BrowserFaviconFetchReason)reason
                            completion:(void (^)(NSURL * _Nullable iconURL,
                                                 NSImage * _Nullable image,
                                                 NSError * _Nullable error))completion;

- (nullable NSImage *)cachedImageForHost:(NSString *)host; // 同步，仅内存/磁盘快路径
- (void)cancelAll; // App 退出可选
@end

/// 成功写入或更新磁盘缓存后发出；object = host
extern NSNotificationName const BrowserFaviconDidUpdateNotification;
```

### 5.2 Store 协作

星标路径在 `toggleBookmark:` 新增分支：

```
addShortcutWithTitle:... iconURLString:@""
→ 立即 save + 刷新星标 UI
→ [BrowserFaviconService fetchAndCacheForPageURLString:url ... reason:Silent]
   completion(main):
     若仍存在该 URL 的 shortcut：
       update iconURLString → saveShortcuts
       post BrowserFaviconDidUpdateNotification
       launchpad / autocomplete 刷新图标
```

不改动文件夹模型；folder cell 四宫格子项仍各自按 link 的 URL/icon 走同一服务。

### 5.3 编辑 Sheet

- `图标链接` 行改为：`[SBTextField iconURLField]` + `[NSButton 自动获取]` 横向 `NSStackView`。  
- 按钮 action：`fetchAndCache... reason:UserAction`；成功填字段；可用 `NSProgressIndicator` 或标题切换表达忙碌。  
- 输入控件规范：仍仅 `SBTextField`；按钮为普通 `NSButton`。

---

## 6. 触发点与非触发点

| 触发 | 行为 |
|------|------|
| 地址栏 ★ **加入** | Silent 瀑布；回写 store |
| 编辑 / 添加 sheet「自动获取」 | UserAction 瀑布；填表单，保存后才进 store |
| Launchpad cell 配置时（可选 ICO-2） | 若 `iconURL` 空且无磁盘缓存 → Silent 惰性拉取（限流） |
| 地址栏补全行 | 只读缓存 + 已有 `iconURL`；不主动风暴第三方 |

| 不触发 | 原因 |
|------|------|
| ★ **移除** | 无需拉图标 |
| App 冷启动遍历全部 shortcut | 避免启动打满网络；依赖显示时惰性或已有缓存 |
| 文件夹本身 | 无独立 URL |

---

## 7. UI / UX 细则

### 7.1 星标

- 交互时序不变：先本地收藏成功，再后台图标。  
- 不 Toast「正在获取图标」。  
- Launchpad / 补全在通知到达后把字母占位替换为图标（已有异步 setImage 路径可复用）。

### 7.2 编辑对话框

| 元素 | 说明 |
|------|------|
| 按钮文案 | 「自动获取」；进行中「获取中…」并 `enabled = NO` |
| 成功 | 写入 `iconURLField`；可清 `errorLabel` |
| 失败 | `errorLabel` 单行提示 |
| 网址空/非法 | 不发请求，提示先修正网址 |
| 预览（ICO-2 可选） | 字段下 16×16 / 32×32 `NSImageView`，随字段或获取结果更新 |

### 7.3 占位

无图时行为与现网一致：域名首字母 + 色相哈希（Launchpad）/ 小字母（补全）。

---

## 8. 模块与文件布局

```text
SimpleBrowser/
├── Favicon/                          # 新建
│   ├── BrowserFaviconService.h/.m    # 瀑布编排、限流、通知
│   ├── BrowserFaviconCache.h/.m      # 磁盘 index + blobs、内存 NSCache
│   └── BrowserFaviconHTMLParser.h/.m # 64KB 扫描 link[rel*=icon]
├── NewTab/
│   ├── BrowserShortcutCellView.m     # 去掉私有 IconLoader，改调 Service
│   ├── BrowserShortcutEditorSheet.m  # 「自动获取」按钮
│   └── BrowserShortcutStore.m        # 可选：按 host 批量回写辅助
├── AddressBar/
│   └── BrowserShortcutSuggestionPanel.m  # 走 Service
└── BrowserWindowController.m         # toggleBookmark: 触发 fetch
```

Makefile：`BROWSER_SOURCES` 增加 `SimpleBrowser/Favicon/*.m`，`-ISimpleBrowser/Favicon`（或并入既有 `-I` 规则）。

---

## 9. 线程与错误

| 规则 | 说明 |
|------|------|
| 网络 / 解码 / 写盘 | 后台队列 |
| completion / 改 Store / 改 UI | 主线程 |
| 取消 | host 粒度；Sheet 关闭时可 cancel 该次 UserAction |
| 错误域 | `BrowserFaviconErrorDomain`：`invalidURL` / `allChannelsFailed` / `cancelled` / `decodeFailed` |

---

## 10. 风险与对策

| 风险 | 对策 |
|------|------|
| 第三方接口失效或墙 | 多渠 + 本地 well-known/html；失败占位 |
| HTML 过大 / 慢 | 64KB 截断 + 超时；不渲染 |
| 星标连点 / 多标签 | 在途去重 + 全局并发 2 |
| `iconURLString` 写 file URL 换机失效 | 首版优先写远程 `sourceURL` |
| HTTP 明文混合内容 | 允许 http 图标（内网站）；ATS 按现 App 策略 |
| ICO/SVG 解码失败 | 该渠失败，下一渠；SVG 首版可跳过 |
| 隐私 | 仅 host/图标 URL；无第三方分析 SDK |

---

## 11. 分期与验收

### ICO-1

- [x] `BrowserFaviconCache` 读写 blobs + index  
- [x] `BrowserFaviconService` 渠道 1～6 瀑布 + 限流  
- [x] 星标加入触发 Silent 拉取并回写 `iconURLString`  
- [ ] 重启后磁盘命中，不再发网络（断网可验，手测）  
- [x] 失败静默，快捷方式仍可用  

### ICO-2

- [x] 编辑 / 添加 sheet「自动获取」按钮与忙碌态  
- [x] UserAction 失败有文案；成功填入图标链接  
- [x] Launchpad cell、补全面板、文件夹四宫格统一走 Service  
- [x] 移除私有 `BrowserShortcutIconLoader`  
- [x] `make browser` 通过；acceptance 追加条目  

### ICO-3（延后）

- [ ] 标签条 favicon  
- [ ] 页面 didFinishNavigation 时顺手缓存  
- [ ] 负缓存 TTL / 清除缓存 UI  
- [ ] 第三方渠道开关  
- [ ] Web App Manifest `icons`  

---

## 12. 与既有文档的关系

| 文档 | 关系 |
|------|------|
| [new-tab-launchpad-design.md](new-tab-launchpad-design.md) §8 | 本文件承接并细化「NTP-3 favicon」未完成部分 |
| [address-bar-shortcut-autocomplete-design.md](address-bar-shortcut-autocomplete-design.md) | 补全行改为消费统一缓存，避免每行直打 `/favicon.ico` |
| [professional-features-roadmap.md](professional-features-roadmap.md) §3.3 / M2 | 「Favicon 显示」本阶段聚焦 Launchpad + 星标 + 补全；标签栏归 ICO-3 |
| [new-tab-launchpad-wallpaper-design.md](new-tab-launchpad-wallpaper-design.md) | 同为 Application Support 落盘，目录并列、职责分离 |

---

## 13. 开放问题（实现前锁定）

1. **回写 `iconURLString`**：远程 `sourceURL`（推荐）vs `file://` blobs？ → **推荐远程**。  
2. **默认快捷方式**：是否在首次显示时惰性拉取？ → **ICO-2 建议启用**，走 Silent + 限流。  
3. **取消收藏是否删 host 缓存？** → **不删**（换机无关；同机复用）。  

---

开发任务拆解见 [favicon-fetch-cache-development-plan.md](favicon-fetch-cache-development-plan.md)。
