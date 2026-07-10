# SimpleBrowser — 最精简浏览器技术方案

> 目标：在 macOS 上用 Objective-C + AppKit 实现一个**可用的最小浏览器**，复用系统 WebKit 引擎，不自研渲染层。
>
> 关联项目：`objcdemo` 仓库，沿用现有 Makefile 构建方式。

---

## 1. 方案定位

### 1.1 做什么

| 层级 | 名称 | 能力 |
|------|------|------|
| **L0** | 演示级 | 窗口 + `WKWebView` + 加载固定 URL |
| **L1** | 可用最小版（推荐目标） | L0 + 地址栏、前进/后退、刷新、标题同步、基础错误提示 |
| L2 | 稍完整 | L1 + 加载进度、新窗口策略、简单菜单 |
| L3 | 完整浏览器 | 多标签、书签、历史、下载等（**不在本方案范围**） |

**本方案交付目标：L1。**

### 1.2 不做什么

- 不自研 HTML/CSS/JS 渲染引擎
- 不实现多标签、书签、历史、扩展系统
- 不追求 Chrome/Safari 级别的功能完整度
- 不在第一阶段使用 XIB 布局（降低与开源 `ibtool` 的 WebView 兼容风险）

---

## 2. 技术选型

| 项目 | 选择 | 理由 |
|------|------|------|
| 语言 | Objective-C（ARC） | 与现有 `SimpleWindow` 一致 |
| UI 框架 | AppKit | 桌面 macOS 原生 |
| 渲染引擎 | `WKWebView`（WebKit） | 系统自带、Safari 同源、官方推荐 |
| 构建 | Makefile + `clang` | 与现有工程一致，无 Xcode 工程依赖 |
| UI 布局 | **纯代码**（`NSStackView`） | L0/L1 控件少，易维护；避免 XIB 编译问题 |
| 最低系统版本 | macOS 11.0 | 与现有 `Info.plist` 一致 |

### 2.1 为何不用已废弃的 WebView

`WebView`（旧 WebKit API）已废弃，应使用 `WKWebView`。新代码一律基于 WebKit 框架中的 `WK*` 类。

---

## 3. 架构设计

### 3.1 组件关系

```
┌─────────────────────────────────────────────────┐
│  NSApplication                                   │
│    └── AppDelegate                               │
│          └── BrowserWindowController             │
│                ├── 工具栏 (NSStackView)          │
│                │     ├── 后退 / 前进 / 刷新按钮   │
│                │     └── 地址栏 (NSTextField)    │
│                └── WKWebView (主内容区)          │
└─────────────────────────────────────────────────┘
         │                              │
         │  WKNavigationDelegate        │  WKUIDelegate
         ▼                              ▼
   标题、加载状态、错误处理        新窗口 / 弹窗（基础）
         │
         ▼
   系统 WebKit 进程（独立，由系统管理）
```

### 3.2 职责划分

| 类 / 模块 | 职责 |
|-----------|------|
| `main.m` | 程序入口，启动 `NSApplication` |
| `AppDelegate` | 应用生命周期；创建并显示主窗口 |
| `BrowserWindowController` | 窗口与 UI 布局；地址栏与导航按钮事件 |
| `WKWebView` | 网页加载、渲染、JS 执行（引擎侧） |
| `WKNavigationDelegate` | 导航开始/结束、标题变化、加载失败 |
| `WKUIDelegate` | `window.open`、简单 `alert/confirm`（L1 可选，L2 完善） |

### 3.3 目录结构（计划新增）

```
SimpleBrowser/
├── main.m
├── AppDelegate.h
├── AppDelegate.m
├── BrowserWindowController.h
├── BrowserWindowController.m
└── (无 XIB，L1 阶段纯代码 UI)

Makefile          # 增加 browser / run-browser 等 target
build/
└── SimpleBrowser.app
```

与 `SimpleWindow/` **并列独立**，不修改现有演示应用代码。

---

## 4. 核心实现要点

### 4.1 Makefile 变更

在链接参数中增加 WebKit：

```makefile
BROWSER_LDFLAGS := -framework Cocoa -framework Foundation -framework WebKit
```

建议 Makefile 结构：

- `make` / `make all` — 构建 `SimpleWindow`（保持现有行为）
- `make browser` — 构建 `SimpleBrowser`
- `make run-browser` — 构建并启动浏览器

### 4.2 窗口与 WebView 创建（L0）

```objc
#import <WebKit/WebKit.h>

WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
WKWebView *webView = [[WKWebView alloc] initWithFrame:contentRect configuration:config];
webView.navigationDelegate = self;
webView.UIDelegate = self;

NSURL *url = [NSURL URLWithString:@"https://example.com"];
[webView loadRequest:[NSURLRequest requestWithURL:url]];
```

### 4.3 工具栏布局（L1）

使用垂直 `NSStackView`：

1. **顶栏（水平 Stack）**：`◀` `▶` `↻` + 地址栏（`NSTextField`，回车触发加载）
2. **内容区**：`WKWebView`，设置 `autoresizingMask` 或 Auto Layout 填满剩余空间

窗口建议默认尺寸：1024 × 700。

### 4.4 地址栏 URL 规范化

用户输入需做简单处理：

| 输入 | 加载目标 |
|------|----------|
| `example.com` | `https://example.com` |
| `https://...` | 原样加载 |
| `http://...` | 原样加载 |
| 含空格 / 无点号 | 视为搜索（L1 可固定跳转 `https://duckduckgo.com/?q=...`，或仅提示格式错误） |

L1 建议：**无 scheme 时补 `https://`**；非法 URL 在状态区提示，不崩溃。

### 4.5 导航按钮状态

通过 KVO 或 `WKNavigationDelegate` 回调更新：

```objc
backButton.enabled = webView.canGoBack;
forwardButton.enabled = webView.canGoForward;
```

在 `didFinishNavigation` / `didCommitNavigation` 时同步地址栏 URL 为 `webView.URL.absoluteString`。

### 4.6 Delegate 必做回调（L1）

**WKNavigationDelegate**

- `webView:didStartProvisionalNavigation:` — 可选，更新状态「加载中」
- `webView:didFinishNavigation:` — 更新标题、地址栏、按钮状态
- `webView:didFailProvisionalNavigation:withError:` — 显示错误（`NSAlert` 或状态栏）

**WKUIDelegate（L1 最小）**

- `webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:` — 在同一 `WKWebView` 中加载新 URL，避免点击链接无反应

### 4.7 Info.plist

与 `SimpleWindow` 类似，关键项：

- `CFBundleIdentifier`: `com.example.SimpleBrowser`
- `LSMinimumSystemVersion`: `11.0`
- `NSHighResolutionCapable`: `true`

L1 无需额外网络权限描述（macOS 桌面应用默认允许出站网络）。若后续访问相机/麦克风再补充 `NS*UsageDescription`。

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| WebKit 内存占用偏高 | 空壳约几十 MB | 预期内，非泄漏；可用 `make stats` 对比 |
| 开源 `ibtool` 对 WebView 支持有限 | XIB 方案不稳定 | L1 使用纯代码 UI |
| `window.open` 无响应 | 部分站点体验差 | 实现 `WKUIDelegate` 创建 WebView 回调 |
| HTTPS 证书错误 | 部分内网站无法打开 | L1 仅提示错误；不实现「继续访问」 |
| 与 SimpleWindow 构建冲突 | Makefile 复杂度上升 | 独立 source 列表与 target，互不干扰 |

---

## 6. 验收标准（L1）

- [x] `make browser` 成功产出 `build/SimpleBrowser.app`
- [x] `make run-browser` 可启动并默认打开 `https://example.com`
- [x] 地址栏输入 URL 回车可导航
- [x] 后退 / 前进 / 刷新按钮行为正确，不可用时常灰
- [x] 窗口标题随页面 `title` 更新
- [x] 加载失败有可见提示（Alert 或状态文字）
- [x] 关闭窗口后应用退出（`applicationShouldTerminateAfterLastWindowClosed`）
- [x] 现有 `SimpleWindow` 的 `make` / `make run` 不受影响

---

## 7. 后续扩展方向（非 L1）

按优先级排列，供 L2+ 参考：

1. 顶部加载进度条（`estimatedProgress` KVO）
2. 停止加载按钮
3. 简单应用菜单（关于、退出、显示首页）
4. XIB 版工具栏（确认 `ibtool` 可用后再迁移）
5. 多标签 `NSTabView` + 多 `WKWebView` 实例

---

## 8. 参考

- [WKWebView — Apple Documentation](https://developer.apple.com/documentation/webkit/wkwebview)
- [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate)
- [WKUIDelegate](https://developer.apple.com/documentation/webkit/wkuidelegate)
- 本仓库现有实现：`SimpleWindow/`（AppDelegate、WindowController、Makefile 模式）
