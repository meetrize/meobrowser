# 网页系统通知桥（Page Notification Bridge）— 设计方案

> 目标：允许受信任网页通过 `webkit.messageHandlers.meoPageNotify` 弹出 macOS 系统通知；首要消费者为 FeedGen 阅读器自动刷新提示。  
> 状态：设计已定  
> 开发计划：[page-notification-bridge-development-plan.md](page-notification-bridge-development-plan.md)  
> 关联：FeedGen [`docs/ARTICLE_REFRESH_NOTIFY.md`](/www/wwwroot/feedgen/docs/ARTICLE_REFRESH_NOTIFY.md) · [companion-notification-mirror-design.md](companion-notification-mirror-design.md)（手机镜像，职责分离）

---

## 1. 方案定位

### 1.1 产品一句话

**网页通知桥**：在 MeoBrowser 内，允许列表中的站点可请求展示一条 macOS 系统通知；与 Companion 手机通知镜像解耦。

### 1.2 与现有能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| `PhoneNotificationPresenter` | Companion → 系统通知 | **不改**；独立 category / 开关 |
| `CallAlertPresenter` | 来电横幅 | **不改** |
| 网页 → 原生通知 | ❌ 无 | ✅ `meoPageNotify` |
| Companion 收件箱侧栏 | 手机镜像历史 | **不接入**网页通知 |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| `WKScriptMessageHandler` + 可选 `window.MeoBrowser.notify` | 任意站点无限制通知 |
| 主机允许列表 + 速率限制 + 同 tag 覆盖 | 通知点击深度链到 FeedGen 某篇文章 |
| 前台也展示横幅（便于验收） | 写入手机通知收件箱 |
| 首次投递时申请通知权限 | 复用「手机镜像」开关 |

---

## 2. 网页 API

### 2.1 Message Handler

名称：`meoPageNotify`

```js
window.webkit.messageHandlers.meoPageNotify.postMessage({
  type: 'notify',
  title: 'FeedGen',
  body: '3 条新文章',
  tag: 'feedgen-refresh',
  count: 3
});
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | string | 必须为 `"notify"`，否则忽略 |
| `title` | string | 截断至 80 字 |
| `body` | string | 截断至 200 字；空则忽略 |
| `tag` | string | 用于合并/覆盖与限流；缺省为 `default` |
| `count` | number | 可选，仅透传日志 |

### 2.2 注入便利 API（User Script）

```js
window.MeoBrowser = window.MeoBrowser || {};
window.MeoBrowser.notify = function (opts) {
  var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.meoPageNotify;
  if (!h) return false;
  opts = opts || {};
  h.postMessage({
    type: 'notify',
    title: opts.title || '',
    body: opts.body || '',
    tag: opts.tag || 'default',
    count: opts.count || 0
  });
  return true;
};
```

主框架 DocumentEnd 注入；无 handler 时脚本仍可定义，调用返回 `false`。

---

## 3. 原生架构

```
WKWebView page
  → meoPageNotify (LoginAssistScriptMessageProxy)
      → BrowserPageNotificationBridge
          → 主机允许？限流？校验载荷？
          → BrowserPageNotificationPresenter
              → UNUserNotificationCenter (category MEO_PAGE_NOTIFICATION)
```

### 3.1 文件

| 文件 | 职责 |
|------|------|
| `Privacy/BrowserPageNotificationBridge.{h,m}` | 注册 handler、注入脚本、收消息、门禁 |
| `Privacy/BrowserPageNotificationPresenter.{h,m}` | 权限申请、组装 `UNMutableNotificationContent`、deliver |
| `BrowserWindowController.m` | `installOnConfiguration:` |
| `Makefile` | 加入源文件 |

### 3.2 允许列表

- `NSUserDefaults` 键：`PageNotifyAllowedHosts`（`NSArray<NSString *>`，主机名小写）
- 默认始终允许：`localhost`、`127.0.0.1`、`::1`
- 额外：用户配置数组；未命中则静默丢弃
- 匹配：精确相等，或请求 host 为配置项的子域（`hasSuffix: .configHost`）

### 3.3 限流与合并

- 同一 `host + tag`：最短间隔 **10s**；过频则跳过
- `requestWithIdentifier`：`page-notify-{host}-{tag}`（截断 ≤180），同 id 覆盖，避免堆叠

### 3.4 前台展示

`UNUserNotificationCenterDelegate.willPresent`：Banner + Sound + List（与手机镜像一致）。  
若 `PhoneNotificationPresenter` 已占用 delegate，其现有前台展示逻辑已覆盖任意 category，网页通知仍可见。本 Presenter 在尚未有 delegate 时自行安装。

点击通知：激活 MeoBrowser 前台窗口即可（不打开 Companion 收件箱）。

---

## 4. 安全注意

- 任意网页可尝试 `postMessage`；**必须**主机允许列表，避免广告站刷通知
- 不把网页内容写入 Keychain / 收件箱
- title/body 长度截断，防止异常大字符串

---

## 5. FeedGen 对接

见 FeedGen `docs/ARTICLE_REFRESH_NOTIFY.md`。阅读器在自动刷新 `newCount > 0` 时调用桥；非 MeoBrowser 环境无 handler，仅页内 toast。
