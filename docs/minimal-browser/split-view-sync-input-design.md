# 分栏浏览 + 同步输入 — 设计方案（待评审选择）

> 状态：方案评审稿，落地待用户选择后转开发计划。日期 2026-10-13。
> 范围：单窗口内多 Pane（分栏），非多 NSWindow（已有 multi-window-design.md）。

## 1. 现状结论（基于本仓库）

- `BrowserWindowController.m` 约7300行：单 `tabController` + 单 content 区 + 每窗地址栏/标签条/侧栏。最适合插入一层 `SplitPaneController`，不重写 Tab 体系。
- `BrowserTabController/BrowserTab` 已是窗口作用域，可复用：每个 Pane 持有一个轻量 `PaneTabStrip`（复用现有类或简化版），共享 `defaultDataStore`（登录态一致，与多窗口策略相同）。
- `BrowserMenus` 已统一 FirstResponder 安装一次：分栏菜单加在「查看 > 分栏」子菜单即可，不破坏现有菜单。
- `BrowserWindowLayoutPresetStore` 目前只存窗口外框大小：可扩展存分栏预设（JSON in UserDefaults），与会话恢复正交。

## 2. 分栏模式（建议首版 6 种）

| ID | 布局 | 说明 |
|----|------|------|
| single | 单栏 | 现状，回退态 |
| LR | 左右2栏 | 1:1 默认，可拖 |
| UD | 上下2栏 | 1:1 |
| LCR | 左中右3栏 | 1:1:1 |
| UMD | 上中下3栏 | 1:1:1 |
| quad | 田字4栏 | 2x2 |
| nine | 九宫格 | 3x3，二期/按需，最耗内存 |

建议首版只做 single/LR/UD/LCR/quad；UMD/nine 列为二期选项（实现成本低但使用率低）。

## 3. 架构：Pane 容器

```
BrowserWindowController
 └─ BrowserSplitContainerView (NSStackView/NSSplitView定制)
     ├─ BrowserPaneView × N
     │   ├─ PaneChrome（地址栏+前进后退+关闭/聚焦按钮）
     │   └─ PaneContent（WKWebView 或 Launchpad/TabStrip宿主）
     └─ BrowserThinDivider × N-1（1px细线，hover高亮，拖拽改比例）
```

- 不用系统 NSSplitView 默认粗 divider：自绘 1px `separatorColor`，hover 时 2px 蓝色提示，拖拽改 `weights[]`。
- 每个 Pane 独立 URL 输入、独立历史（复用 `BrowserTab.tab` 单页即可；多标签 per pane 为二期）。
- 焦点 Pane 高亮细边框；`Cmd+1/2/3/4` 切 Pane，`Cmd+Opt+左右` 移焦点。
- 地址栏模式三态（按你的要求）：每 Pane独立 `总是显示 / 自动隐藏（hover显示）/ 隐藏`，菜单控制 + 默认自动隐藏。

## 4. 预设保存/加载

- 存 `UserDefaults: splitPresets = [{name, layoutID, weights[], urls[], chromeMode}]`。
- 菜单：「查看 > 分栏 > 保存当前为预设… / 管理预设… / ─ / 预设名√」。
- 加载=切换布局+按序 `load URL`；URL 为空则开 Launchpad。
- 限制：最多存 20 个；urls 只存当前 Pane URL（不存历史栈，首版简化）。

## 5. 同步输入：能不能按你的设想做？

你的设想：点亮同步图标 → 依次点击各栏表单 → 打字同时出现在多栏 + 回车同步。

结论：**能做，但不要用“系统键盘事件转发”，要用 JS 注入镜像方案（方案B，推荐）。**

| 方案 | 原理 | 评价 |
|------|------|------|
| A. CGEvent 键盘转发 | 把按键同时 post 到多个 WebView | 不推荐：焦点只能一个、IME/拼音崩、密码框/验证码风险、回车/快捷键语义乱 |
| B. JS镜像同步（推荐） | 主Pane输入监听 `input` 事件 → 经 ObjC 广播 → 其余Pane `evaluateJavaScript: setValue+dispatchEvent` | 可实现、支持IME最终值、支持回车同步提交、可逐表单配对、可审计 |
| C. 表单填充式同步 | 只同步“提交前的值”（类似登录助手） | 最稳但非实时，作为B的降级 |

推荐交互（B）：
1. 标签栏右侧加同步图标（⇄），点击进入“同步拾取态”（图标高亮+toast“请依次点击各栏要同步的输入框”）。
2. 各 Pane 顶部 overlay 显示序号 ①②…；点击表单即 `document.activeElement` 指纹（tag/id/name/xpath）配对。
3. 配对成功后在主栏打字 → 其余栏同指纹框实时镜像（含 `input/change` 事件触发，页面框架如 React 受控组件需加 `nativeInputValueSetter` 兼容）。
4. 回车/⌘+Enter：广播 `submit`，各栏独立提交；密码/`type=password`、otp、captcha 框默认排除并提示。
5. 状态栏显示“同步中 3/3”，Esc 或再点图标退出。

风险诚实告知：跨站/异构表单（不同站点 DOM 不同）只能按“同序号 input”启发式配对，成功率~80%；同站双栏（如两个商品页搜索框）成功率最高。建议首版限定“同选择器镜像”，异构提示用户手动重选。

## 6. 需要你选择的事项（请回复序号）

1. 首版布局：(a)LR+UD+LCR+quad[推荐] (b)再加UMD (c)再加九宫格
2. Pane内标签：(a)单页每栏[推荐，省内存] (b)每栏完整标签条（二期）
3. 地址栏默认：(a)自动隐藏[推荐] (b)总是显示
4. 同步输入：(a)JS镜像B[推荐] (b)B+C降级都做 (c)暂不做同步，只做分栏
5. 预设数量/位置：(a)菜单内20个[推荐] (b)另做预设管理窗
6. Divider：(a)1px细线[按你要求] (b)可设粗细

你回复选择后，我即按本目录规范补 `split-view-sync-input-development-plan.md`（分 MW 任务、验收、改动文件清单）并可开始实现。

## 7. 预计改动文件

- 新增：`SimpleBrowser/SplitView/BrowserSplitContainerView.{h,m}`、`BrowserPaneView.{h,m}`、`BrowserThinDivider.{h,m}`、`BrowserPaneSyncCoordinator.{h,m}`、`split-sync.js`。
- 改动：`BrowserWindowController.{h,m}`（content 宿主切换）、`BrowserMenus.m`（查看>分栏+预设+地址栏模式）、`BrowsingPreferences`（预设读写）、工具栏图标（ChromeActions）。
- 不动：Cookie/processPool（共享 defaultDataStore）、多窗口会话格式。
