# 浏览历史与地址栏历史补全 — 设计方案

> 状态：**已实现**（Mac 本地历史 + trailing 侧栏 + AC-3）  
> 相关：[`address-bar-shortcut-autocomplete-design.md`](address-bar-shortcut-autocomplete-design.md)、[`assist-sidebar-design.md`](assist-sidebar-design.md)

---

## 1. 目标与边界

### 做

- 主帧成功导航后记录浏览历史（全局、跨窗口）
- **右侧历史侧栏**（与通知 / 助手互斥）+ 地址栏按钮 + `⌘Y`
- 地址栏输入时合并「快捷方式 + 历史」建议（AC-3）
- 设置中清除历史 / 退出时清除

### 不做（本阶段）

- 独立书签库；Companion / 云端历史同步写通；SQLite

### 原则

- 历史是访问日志；标签后退前进仍由 WebKit 负责
- 侧栏打开时**不**因地址栏聚焦而关闭（可边看历史边浏览）

---

## 2. 交互（侧栏）

### 入口

| 入口 | 行为 |
|------|------|
| 地址栏动作组 `history`（`clock`） | 切换历史侧栏 |
| 菜单「历史 → 显示全部历史」`⌘Y` | 同上 |

与通知收件箱、助手侧栏经 `BrowserTrailingSidebarSlot` **三方互斥**；窄窗（&lt; 720）时 `hideAllAnimated`。

### 侧栏结构

```
┌─ 历史记录  42          [清除] [⟩] ─┐
│  🔍 搜索标题或网址…                 │
│  [ 全部 | 今天 | 7 天 ]             │
├────────────────────────────────────┤
│  今天                               │
│  ●  RFC 9110          example  14:32│
│     example.com                     │
│  昨天                               │
│  ●  …                               │
├────────────────────────────────────┤
│  双击打开 · ⌘双击新标签 · ⌘⌫ 删除   │
└────────────────────────────────────┘
```

| 行为 | 定稿 |
|------|------|
| 单击行 | 选中 |
| 双击 / Enter | 当前标签打开 |
| ⌘双击 / ⌘Enter / 中键 | 新标签打开 |
| 右键菜单 | 打开、新标签、复制链接、复制 Markdown、删除此项、删除域名全部 |
| 「清除」菜单 | 今天 / 最近 7 天 / 全部（确认） |
| 分段 | 全部 / 今天 / 7 天（与搜索叠加） |
| Esc | 关闭侧栏 |
| 左缘拖拽 | 调宽 320～560，默认 380，持久化 |

打开侧栏时焦点落入搜索框，便于立刻过滤。

### 地址栏补全（AC-3）

- 防抖 50ms，最多 8 条；快捷方式优先 → 历史；同 URL 去重
- 历史行时钟小徽标；Enter / Tab 行为不变

---

## 3. 数据与内存

同前：`~/Library/Application Support/MeoBrowser/History/history.json`，活跃上限 500，按 URL 合并，300ms 写盘，2s 内不重复涨 visitCount。写入点：`syncFromWebView:`。

---

## 4. 模块

| 文件 | 职责 |
|------|------|
| `BrowserHistoryEntry.*` | 模型 ↔ JSON |
| `BrowserHistoryStore.*` | 单例存储 / 查询 / 清除 |
| `BrowserHistorySettings.*` | 侧栏宽度 |
| `BrowserHistorySidebarController.*` | trailing 侧栏 UI |

接线：`BrowserTrailingSidebarSlot`、`BrowserWindowController`、地址栏补全、`BrowserMenus`、设置。

---

## 5. 隐私

默认仅本地；设置「清除浏览历史…」「退出时清除浏览历史」；清除网站数据不含历史。
