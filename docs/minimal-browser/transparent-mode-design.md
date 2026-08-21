# 透明模式（Overlay Reading）— 交互与实现方案

> 目标：在标签栏 Chrome 动作区增加「透明模式」；开启后隐藏全部浏览器 UI，窗口与页面背景透明，仅保留网页文字可读；通过 macOS 菜单栏 Status Item 进出模式并支持退出应用。  
> 状态：**首版已完成（TM-0～TM-2）**  
> 开发计划：[transparent-mode-development-plan.md](transparent-mode-development-plan.md)  
> Cursor 计划：[.cursor/plans/transparent-mode.plan.md](../../.cursor/plans/transparent-mode.plan.md)  
> 关联：[tab-strip-chrome-actions-design.md](tab-strip-chrome-actions-design.md) · [multi-window-design.md](multi-window-design.md) · [multi-tab-design.md](multi-tab-design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**桌面上只留网页文字：浏览器壳全部隐去，菜单栏一键进出。**

### 1.2 典型场景

- 对照桌面其它窗口 / 壁纸阅读长文  
- 演示或录屏时只要正文，不要浏览器 chrome  
- 与「窗口置顶」组合：透明文字浮在其它 App 之上（可选叠加，见 §7）

### 1.3 做什么（V1）

| 能力 | 说明 |
|------|------|
| Chrome 入口 | 标签条右侧、**精简图标左侧**新增「透明模式」图标 |
| 全 UI 隐藏 | 标签条、地址栏、侧栏、浮层、交通灯等浏览器壳全部不可见 |
| 窗口透明 | 窗口非不透明、背景 clear；WebView 不绘制默认底色 |
| 页面「只留字」 | 注入样式：背景透明、弱化/隐藏装饰性媒体；文字保留并加可读性描边/阴影 |
| 菜单栏出口 | `NSStatusItem`（MeoBrowser 图标）：「进入/退出透明模式」切换 +「退出 MeoBrowser」 |
| 状态可逆 | 退出后恢复进入前的 chrome（含精简 / 置顶等） |
| 会话 | 每窗 `transparentMode` 写入 session（可选恢复；默认建议恢复以免惊吓） |

### 1.4 不做什么（V1）

- 不做「只透明窗口、页面外观完全不变」的半吊子模式（与「只显示文字」目标不符）  
- 不做逐站点精细 CSS 白名单（V1 用通用注入 + 可关）  
- 不做触摸栏 / 刘海额外控件  
- 不在透明态保留可点的标签条「退出」按钮（壳已隐藏；**唯一可靠出口是菜单栏**）  
- 不做跨窗口「一键全透明」以外的复杂编组（菜单栏切换作用域见 §4.3）  
- 不保证所有站点（尤其强背景图 / Canvas 游戏）视觉完美；文档标明限制

### 1.5 设计原则

1. **可逆优先**：进入前快照窗口样式与 chrome 显隐；退出严格还原。  
2. **出口不依赖壳内 UI**：透明后壳不可见 → Status Item 常驻可用。  
3. **隐藏优于销毁**：不 teardown WebView / 不卸标签数据。  
4. **文字可读**：透明后桌面花哨时，正文需描边/阴影兜底。  
5. **性能克制**：无定时器刷透明；样式注入一次 + 导航后补注；无逐帧截屏。  
6. **与现有 ChromeActions 同构**：走注册表，不新开平行按钮体系。

---

## 2. 用户场景

### 2.1 进入

```
浏览文章
  → 点标签条右侧「透明」（位于精简左侧）
  → 标签条 / 地址栏 / 侧栏 / 交通灯等全部消失
  → 窗口背景透明；页内色块/图弱化或隐藏；文字浮于桌面
  → 菜单栏出现（或已有）MeoBrowser 图标；图标可呈「开」态
```

### 2.2 退出

```
菜单栏 MeoBrowser 图标
  → 「退出透明模式」
  → 浏览器 UI 与窗口样式恢复进入前快照
  → 网页恢复正常样式（移除注入）
```

同菜单项在已退出时显示「进入透明模式」，作用于当前相关窗口（§4.3）。

### 2.3 退出应用

```
菜单栏 → 「退出 MeoBrowser」→ 正常 terminate（与 Dock ⌘Q 一致）
```

### 2.4 与精简 / 置顶

| 组合 | 行为 |
|------|------|
| 先精简再透明 | 透明时壳全隐；退出透明后仍保持精简 |
| 先透明再… | 壳已隐，无法点精简；用菜单栏退出透明后再操作 |
| 置顶 + 透明 | **允许**：透明文字压在其它窗口上；退出透明时保留置顶布尔值 |

---

## 3. UI 入口

### 3.1 标签条 Chrome 动作区顺序（定稿）

```
[…][+]  [摸鱼][透明][精简][置顶]  ░trailing
```

（摸鱼已交付，顺序为摸鱼 → 透明 → 精简 → 置顶，见 [afk-mode-design.md](afk-mode-design.md)。）

| ID | SF Symbol（关/开） | Tooltip |
|----|-------------------|---------|
| `transparentMode` | `cube.transparent` / 同符号强调色；备选 `square.on.square.dashed` | 透明模式 / 退出透明模式 |

实现：在 `BrowserTabStripChromeActionsView defaultItems` **插到 `compactMode` 之前**。

### 3.2 菜单栏 Status Item

| 项 | 定稿 |
|----|------|
| 出现时机 | **应用启动后常驻**（便于「进入」；不依赖先点标签条） |
| 图标 | AppIcon 模板化小图，或 SF Symbol `safari`/`globe` 风格；需适配 Dark/Light 菜单栏 |
| 菜单 | ① 进入透明模式 / 退出透明模式（同一项，按状态改标题或勾选）② 分隔线 ③ 退出 MeoBrowser |
| 点击 | 下拉菜单（不单击直接 toggle，避免误触；V1.1 可加 ⌥ 单击快捷） |

### 3.3 应用菜单（可选增强）

查看菜单可增加「透明模式」勾选项，与 Status Item / 图标同步（非必须 V1，建议 TM-2 顺带做）。

---

## 4. 交互细则

### 4.1 进入透明模式时隐藏清单

| 层级 | 处理 |
|------|------|
| 标题栏 accessory（标签条） | `tabStripAccessory` 移除或 `hidden` + 高度 0；交通灯 `hidden=YES` |
| 工具栏行 | `hidden=YES`（与精简一致或更彻底） |
| 侧栏 | 全部收起并 hidden |
| 查找条 / 下载面板 / 验证码 / 补全 / 标签概览 / toast | `orderOut` / hide |
| Launchpad / 证书警告等覆盖层 | 保持逻辑，但视觉上随透明策略；NTP 进入透明时给出轻量限制（见下） |
| 窗口阴影 | `hasShadow=NO`（避免不透明阴影框） |

### 4.2 窗口与 WebView 透明

```
window.opaque = NO
window.backgroundColor = clear
window.titlebarAppearsTransparent = YES（已有则可保持）
必要时临时调整 styleMask / 忽略鼠标穿透？ → V1 **不** ignoresMouseEvents（仍需滚动/点选链接）
WKWebView.drawsBackground = NO（或私有 under-page background clear，优先公开 API）
```

内容区容器 `contentContainer` layer 背景 clear。

### 4.3 「只显示文字」页面策略（定稿 D1）

注入 UserScript / 临时 CSS（`BrowserTransparentModeStyle`）：

```css
html, body, div, section, article, main, header, footer, aside, nav, span, p, li, td, th {
  background-color: transparent !important;
  background-image: none !important;
  box-shadow: none !important;
  border-color: transparent !important;
}
img, picture, video, canvas, svg, iframe {
  opacity: 0 !important; /* 或 visibility:hidden；保留布局以免文字乱跳可选 */
}
/* 可读性 */
body, p, li, h1, h2, h3, h4, h5, h6, span, a, td, th {
  text-shadow: 0 0 3px rgba(0,0,0,0.85), 0 1px 2px rgba(0,0,0,0.9) !important;
}
```

| 决策 | 定稿 |
|------|------|
| D1 媒体 | **保持显示**（不再强制隐藏图片/视频） |
| D2 文字色 | **统一可配置色**（设置 → 常规）；默认近白 + 对比描边 |
| D3 注入时机 | 进入时对当前 WebView；`didFinishNavigation` / 同文档导航后重注 |
| D4 NTP / about | **禁止进入**或进入后仅透明壳、无正文样式；菜单栏仍可退出。V1 推荐：**允许进，但无「只留字」效果（空白透明）**，Status Item 可退 |

### 4.4 Status Item 切换作用域（定稿 D5）

| 方案 | 说明 | 结论 |
|------|------|------|
| A. 仅 key 窗口 | 菜单作用于当前键盘窗口 | **V1 采用** |
| B. 全部浏览器窗 | 一次切所有窗 | V2 可选 |
| C. 「任意一窗处于透明则退出全部」 | 退出语义清晰 | 退出时：若 key 透明则退 key；若无 key 则退最近透明窗 |

**进入**：对 key `BrowserWindowController` 设 `transparentModeEnabled=YES`。  
**退出**：对 key 窗退出；若 key 非透明但其它窗透明，则退出「最近进入透明的窗口」。

### 4.5 鼠标与键盘

| 操作 | 透明态 |
|------|--------|
| 滚轮滚动页面 | ✅ |
| 点击链接 | ✅ |
| ⌘L / 地址栏 | ❌ 壳隐藏；需先退出透明 |
| ⌘W 关标签 | ✅ 仍走响应链（若菜单栏应用菜单仍在） |
| Esc | V1 **不**自动退出（避免与页内 Esc 冲突）；靠 Status Item |

### 4.6 多窗 / 全屏

- 每窗独立 `transparentModeEnabled`  
- 系统全屏：进入全屏时建议自动退出透明或禁用进入（避免 Space 异常）；定稿 **退出全屏前若在透明则保持，全屏中禁止新进透明**（实现简单：全屏时 validate 禁用）

---

## 5. 架构设计

### 5.1 模块

```
SimpleBrowser/TransparentMode/
  BrowserTransparentModeController.h/.m   // 每窗编排：进/出、快照、样式注入
  BrowserTransparentModeStyle.js          // 或 .css 字符串资源
  BrowserStatusItemController.h/.m        // App 级 NSStatusItem（单例）
```

| 类 | 职责 |
|----|------|
| `BrowserTransparentModeController` | 挂在 `BrowserWindowController`；`setEnabled:`；快照/还原 window + chrome；调用 style apply/remove |
| `BrowserStatusItemController` | 单例；菜单；转发 toggle/quit 到 AppDelegate / key WC |
| ChromeActions | 注册 `transparentMode`；WC wire |

### 5.2 状态快照（进入前）

```objc
typedef struct {
  BOOL opaque;
  NSColor *backgroundColor; // retain copy
  BOOL hasShadow;
  BOOL tabStripAccessoryVisible;
  BOOL toolbarHidden;
  BOOL compactMode;      // 不改值，仅记住
  BOOL alwaysOnTop;
  // standardWindowButton.hidden 三态
  // sidebars visibility
} BrowserTransparentModeSnapshot;
```

退出时按快照还原；**不要**在透明期间改写 `compactModeEnabled` 布尔，只是强制视觉全隐。

### 5.3 与精简模式关系

```
transparent ON  → 视觉上覆盖一切 chrome（含精简后的 ◀▶）
transparent OFF → 若 compact==YES，重新走 setCompactModeEnabled:YES 布局路径
```

实现建议：`applyChromeVisibility` 统一函数：

```
if (transparent) { hideAllChrome(); }
else if (compact) { applyCompactChrome(); }
else { applyNormalChrome(); }
```

### 5.4 样式注入 API

```objc
- (void)applyTransparentPageStyleToWebView:(WKWebView *)webView;
- (void)removeTransparentPageStyleFromWebView:(WKWebView *)webView;
```

用 `evaluateJavaScript` 插入/移除 `<style id="meo-transparent-mode">`；切标签时对选中 WebView 应用，对切走的可移除或保留（定稿：**仅当前可见 WebView 注入**；切回时再注）。

### 5.5 会话键

```
BrowserWindowSessionTransparentModeKey = @"transparentMode"
```

`sanitizedWindowSessionDictionary` 透传；恢复时在 UI 就绪后 `setTransparentModeEnabled:`。  
**产品注意**：冷启动直接进透明可能让用户「找不到窗口」——Status Item 常驻可接受；仍建议默认持久化。

---

## 6. 性能与风险

| 风险 | 缓解 |
|------|------|
| 站点 CSS 权重极高 | `!important` + 导航后重注；失败可接受 |
| 设置滑杆卡顿 / 白屏 | 偏好变更走 `refresh`（只改 stylesheet / CSS filter）；禁止反复 bootstrap、`paintAll`、resize/scroll nudge |
| 退出后字色需刷新才恢复 | Canvas 用 SVG `feColorMatrix` + `drop-shadow` 只改显示，不改像素；退出卸滤镜即恢复；并卸掉旧 `fillText` hook |
| 透明窗点击「穿透」到下层 App | V1 不 ignoresMouseEvents；需要点下层时先退出或点 Dock |
| 录屏/隐私 | 透明可能映出桌面内容；不额外处理 |
| Status Item 重复创建 | 单例 + dispatch_once |
| 与置顶 level | 透明不改 level；置顶逻辑独立 |
| WebView 白底残留 | `drawsBackground=NO` + clear 容器 |

---

## 7. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | 媒体 | **保持显示** |
| D2 | 文字色 | **统一可配置**（设置 → 常规） |
| D3 | Status Item 生命周期 | 启动常驻 |
| D4 | 菜单切换作用域 | key 窗口优先 |
| D5 | 图标位置 | 精简**左侧** |
| D6 | Esc 退出 | V1 不做 |
| D7 | 与置顶 | 允许叠加 |
| D8 | 全屏 | 全屏中禁止进入透明 |

---

## 8. 验收标准（V1）

- [x] 标签条右侧顺序：透明 → 精简 → 置顶  
- [x] 进入后：无标签条、地址栏、侧栏、交通灯；窗口可透视桌面  
- [x] 正文大致可读；大图/视频不明显抢视线  
- [x] 菜单栏 MeoBrowser：可退出透明、可进入透明、可退出 App  
- [x] 退出透明后 UI 与精简/置顶状态正确恢复  
- [x] 多窗：仅操作目标窗；其它窗不受意外影响  
- [x] `make browser` 通过；无明显滚动卡顿  

---

## 9. 后续扩展（非 V1）

- 透明度滑杆 / 只透窗口不改页面  
- ⌥ 单击 Status Item 快速 toggle  
- 全局快捷键  
- 按域名的样式配置  
- 「文字描边强度」设置项  
