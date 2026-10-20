# DOM 探针（DOM Inspector）— 开发计划

> 设计方案：[dom-inspector-design.md](dom-inspector-design.md)
> 状态：**待实现**

---

## 0. 目标与约束

- 交付一个 Chrome Action「DOM 探针」，开启后 hover 显示元素属性、点击钉住到侧栏，支持分段复制。
- 约束：关闭时**零注入**；开启时不破坏页面；与页面爬虫拾取互斥；单例仲裁避免双开。
- 验收标准见每个 Task 的 Done 条件，全部通过后勾选 [acceptance.md](acceptance.md) 对应条目。

---

## Task 1. 拾取仲裁协调器（P0，前置）

**新增**：`SimpleBrowser/Developer/BrowserWebViewPickCoordinator.{h,m}`

- `+ (BOOL)beginPickInWebView:(WKWebView *)webView owner:(id)owner;`
- `+ (void)endPickForOwner:(id)owner;`
- 内部维护单例 `currentOwner`；新 owner 开始时通知旧 owner 的 `browserWebViewPickCoordinatorDidEnd:`（可选协议）。
- `BrowserScraperElementPicker` 与新 DOM 探针桥接层各自改为通过协调器申请，**移除各自的文件静态 `gScraperPick*` 互斥逻辑**。

**Done**：`⌥⌘D`（若探针先开）后再触发爬虫拾取 → 探针自动退出；反向亦然；日志无异常。

---

## Task 2. Chrome Action 注册（P0）

**改动**：
- `SimpleBrowser/ChromeActions/BrowserChromeActionItem.{h,m}`：新增 `BrowserChromeActionDOMInspectorID = @"domInspector"`，目录项 `symbolName:@"viewfinder"`（备选 `cursorarrow.rays` / `square.dashed`），`toggles:YES`，tooltip「DOM 探针」/「退出 DOM 探针」。插入到 `pageScraper` 之后。
- `SimpleBrowser/BrowserWindowController.m`：
  - `wireChromeButton:BrowserChromeActionDOMInspectorID action:@selector(toggleDOMInspector:)`（M4 前先接占位实现）。
  - `performChromeActionForItemID:` 增加分支 → `toggleDOMInspector:`。
  - `chromeActionCheckedForItemID:` 返回 `[self.domInspectorController active]`。
  - `updateChromeActionStates`（同步 on 状态处）补一行。

**Done**：工具栏出现图标，点亮/熄灭态正确，「更多」菜单里可固定/隐藏，布局排序持久化。

---

## Task 3. JS 桥接层（P0）

**新增**：`SimpleBrowser/Developer/BrowserDOMInspectorBridge.{h,m}`

- `WKUserScript` atDocumentStart 注册（绕过页面 CSP）：
  - `document.addEventListener('mouseover', onOver, {capture:true, passive:true})`
  - `mousedown` capture + `preventDefault/stopImmediatePropagation`
  - `scroll`/`resize` 监听仅用于高亮跟随（CSS outline 天然跟随，无需处理）
  - `window.__meoDomInspectorStop()` 全清理
- 脚本用独立 handler 名 `meoDomInspector`，通过 `LoginAssistScriptMessageProxy` 挂载（**复用 Task 1 的协调器**）。
- `snapshot(el, {full})` 实现设计文档 §3.3 的 payload。
- 性能：100ms trailing 去抖 + `lastElement` 比对 + rAF 构造快照 + hover 只发摘要。

**Done**：在大页面（如某电商首页）hover 无可感知掉帧；`didCommit` 后自动重注入；关闭后 `document.querySelectorAll('.meo-di-hover')` 为空且无残留监听。

---

## Task 4. 悬停高亮 + HUD 气泡（P1）

**新增**：`SimpleBrowser/Developer/BrowserDOMInspectorHUD.{h,m}`（`NSPanel` 无标题、`ignoresMouseEvents = YES`、`level = floating`）

- 内容：`BrowserDOMInspectorHUDView`（自定义绘制标题行 + 属性行）
- 跟随逻辑：包围盒下方 8px，视口边缘自动翻转/收边；`constrainedFrameRectForWindow:` 兜底
- 标题行右侧「⌗ 复制选择器」按钮——因 `ignoresMouseEvents`，此按钮需通过 `NSTrackingArea` 局部接管鼠标（或改为 HUD 不忽略鼠标但对页面区域穿透）
- 动作条：⌗选择器 / ⧉属性摘要 / ⋯（展开全部 / 固定面板 / 退出）

**Done**：hover 任意元素气泡在 100ms 内出现且不超出窗口；移动鼠标气泡平滑跟随；点击页面或按 Esc 均正确收尾。

---

## Task 5. 侧栏面板骨架（P1）

**新增**：
- `SimpleBrowser/Developer/BrowserDOMInspectorController.{h,m}`（生命周期：启动/停止、跟随当前标签 WebView、导航重注入）
- `SimpleBrowser/Developer/BrowserDOMInspectorPanel.{h,m}`（NSScrollView + NSStackView，可拖宽，接入 `BrowserTrailingSidebarSlot`）
- `SimpleBrowser/Developer/BrowserDOMInspectorPreferences.{h,m}`（面板宽度、是否拾取后自动退出、是否显示在工具栏）

**Done**：点击元素后面板滑入；显示 tagName/选择器/xpath；与爬虫侧栏互斥；标签切换/休眠时正确置灰与重建。

---

## Task 6. 属性分组与行视图（P1）

**新增**：`SimpleBrowser/Developer/BrowserDOMInspectorRowView.{h,m}`（分组头 + 名值行 + 分段行）

- 分组：身份 / 自定义属性 / 标准属性 / 几何 / 计算样式摘要 / 事件 / 文本与无障碍
- 每组可折叠，标题右侧显示项数
- 名称列等宽字体；值列支持：
  - 纯文本
  - 分段按钮行（由 Task 7 产出）
  - 超长值折叠 + `⤢` 展开
- 空值渲染为 `（空）`

**Done**：属性完整无遗漏（含 `data-*`/`aria-*`/`on*`）；分组计数正确；长值不撑爆布局。

---

## Task 7. 分段器 + 三级复制（P0 核心）

**新增**：`SimpleBrowser/Developer/BrowserDOMValueSegmenter.{h,m}`（纯数据，可单测）

```objc
typedef NS_ENUM(NSInteger, DomSegmentKind) { DomSegmentLiteral, DomSegmentIdentifier, DomSegmentBracketKey, DomSegmentJSONLeaf };
@interface DomValueSegment : NSObject
@property DomSegmentKind kind;
@property NSString *text;        // 该段原文
@property NSString *fullPath;    // 如 "data-row → row → price"
@property NSArray<NSString *> *jsonPath; // JSON 路径键链
@end
```

实现顺序 R6 → R1 → R2 → R3 → R5，递归深度 ≤2，解析失败逐级降级。

**复制交互**：
- 悬停某段 → 段背景高亮 + 右侧浮出两个角标按钮：`⧉`（复制该段原文）、`⧉⧉`（复制完整路径）
- **单击段本身 = 复制该段**（与角标一致）
- 右键段 → `NSMenu`：复制该段 / 复制完整路径 / 复制本属性完整值 / 复制该元素全部属性（JSON）/ 取消
- 复制成功 → `BrowserTransientToast`「已复制 …」+ 段闪绿 200ms

**Done**：
- `row[price]` → `row` + `[price]` 两段，各自可复制
- `{"price":39.9,"qty":2}` → 对象树，叶子可单独复制
- `a,b,c` → 三段
- `cfg[theme][colors]` → 三段且递归深度受限
- 超长值截断但完整值可整段复制
- 右键菜单四项均可用

---

## Task 8. 快捷键、右键与偏好（P2）

- `⌥⌘D` 切换探针（在主菜单与工具栏 tooltip 中体现）
- 面板内 `⌘C` 复制选择器、`⌘⇧C` 复制全部属性 JSON
- `Esc` 依次：取消分段展开 → 关面板 → 退出探针
- `BrowserDOMInspectorPreferences`：面板宽度、拾取后自动退出、默认固定到工具栏
- 设置窗 `BrowserSettingsWindowController` 增加一个 section

**Done**：快捷键全部生效且不与现有（⌘⌥I 打开 Inspector 等）冲突；偏好重启后保持。

---

## Task 9. 边界与加固（P2）

- 注入 `WKUserScript` 后 CSP 验证（至少在一个严格 CSP 站点验证可用）
- 页面自带 `mousedown` 强拦截时的降级（可选「温和模式」：不阻止默认行为，仅记录）
- 快照体积上限（200KB）截断
- 内存：`__weak` 持有 WebView、面板复用而非重建；面板关闭释放 snapshot 引用
- 单元测试：`BrowserDOMValueSegmenter` 的 R1–R6 各至少 3 例（含畸形输入、空串、纯数字、超长、嵌套数组）
- 验收清单更新 `acceptance.md`

**Done**：连续开关 50 次无内存增长（Instruments 观察）；单测全绿。

---

## 10. 实施顺序与依赖

```
Task 1 (仲裁) ──► Task 3 (桥接) ──► Task 4 (HUD)
                    │                 └─► Task 5 (面板) ──► Task 6 (行视图) ──► Task 7 (分段+复制)
                    └─► Task 2 (Action) ─────────────────────────────┘
                                                            Task 8 (快捷键/偏好) ──► Task 9 (加固)
```

建议合并为 3 个可评审提交：
1. **C1**：Task 1 + 2 + 3 + 4（能开启、能 hover、看得到摘要）
2. **C2**：Task 5 + 6 + 7（能钉住、能分段、能复制 —— 功能完整）
3. **C3**：Task 8 + 9（体验与加固）

---

## 11. 不做（明确排除）

- 不做样式编辑、不做节点树、不做 console/network
- 不做跨域 iframe 穿透
- 不做 `getEventListeners` 真实监听列表（V1 留空并标注）
- 不做写入页面属性
