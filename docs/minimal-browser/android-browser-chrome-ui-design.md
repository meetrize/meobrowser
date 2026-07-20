# Android MeoBrowser Chrome UI — 设计方案

> 目标：手机端浏览器改为「顶栏地址 + ⋮、底栏五图标」布局。  
> 状态：**UI-0～UI-3 已落地**（2026-07-20）；真机手测见 acceptance  
> 开发计划：[android-browser-chrome-ui-development-plan.md](android-browser-chrome-ui-development-plan.md)  
> 关联：[android-browser-feasibility-and-plan.md](android-browser-feasibility-and-plan.md)

---

## 1. 布局定稿

```text
┌─────────────────────────────────────┐
│ [========== 地址栏 ==========] [⋮] │  ← 顶栏（左起地址，右 ⋮）
│ ▓▓▓ 加载进度（细条）                 │
├─────────────────────────────────────┤
│                                     │
│     WebView / 新标签快捷方式网格      │
│                                     │
├─────────────────────────────────────┤
│  ◀    ▶    ⊞    [N]    ＋          │  ← 底栏
└─────────────────────────────────────┘
```

| 区域 | 内容 |
|------|------|
| 顶栏 | 地址栏 + ⋮ 溢出菜单；**无**前进/后退/刷新/互联点 |
| 顶栏标签条 | **删除**（改底栏标签面板） |
| 底栏 | 后退 · 前进 · 功能 · 标签(数字) · 新标签 |

---

## 2. ⋮ 菜单

| 项 | 行为 |
|----|------|
| 存为书签 | 当前页写入 `BookmarkStore` |
| 互联与配对 | 打开 Companion 配对页（`MainActivity`） |
| 自动同步 | 打开同步设置（开关 / 快捷方式·历史·书签） |
| 立即同步 | 按已启用项立即与 Mac 同步 |
| 设置 | 打开 `SettingsActivity` |
| 查找 | 页内查找对话框 |
| 添加到桌面 | `ShortcutManager` 固定快捷方式 |
| 分享 | 系统分享当前 URL |
| 发送到 Mac | 已连接时发 `open_url`；未连接提示 |

---

## 3. 底栏

| 按钮 | 行为 |
|------|------|
| 后退 | `WebView.canGoBack` 时可用，否则半透明禁用 |
| 前进 | `canGoForward` 同上 |
| 功能 ⊞ | 弹出功能面板 |
| 标签 [N] | 圆角矩形内显示标签数；弹出标签列表 |
| 新标签 ＋ | `addTab(about:newtab)` |

### 3.1 功能面板

半屏 BottomSheet，项：

下载 · 新建书签 · 桌面模式 · 刷新 · 全屏 · 屏幕旋转 · 字体大小  

底部「收起」dismiss。

| 项 | 实现 |
|----|------|
| 下载 | 打开设置中下载列表或 Toast 引导最近下载 |
| 新建书签 | 同存为书签 |
| 桌面模式 | 切换 `desktopUa` + reload |
| 刷新 | `reload()` |
| 全屏 | 沉浸式系统栏开关，`BrowserPrefs.fullscreen` |
| 屏幕旋转 | 竖/横/跟随循环，`BrowserPrefs.orientationMode` |
| 字体大小 | `textZoom` 85→100→125→150 循环 |

### 3.2 标签面板

- 列表：标题（可截断）+ 右侧 ✕  
- 左滑关闭（`ItemTouchHelper`）  
- 点击行：切换标签并 dismiss  
- 至少保留 1 个标签  

---

## 4. 发送到 Mac（`open_url`）

```json
{
  "v": 1,
  "type": "open_url",
  "deviceToken": "…",
  "url": "https://…",
  "title": "可选",
  "ts": 1710000000
}
```

Mac：`CompanionChannel` 鉴权后在前台窗口新开标签加载 URL，回 `open_url_ok`。

---

## 5. 验收要点

1. 顶栏仅地址 + ⋮；底栏五键可用  
2. 前进/后退随历史启用  
3. 功能面板七项 + 收起  
4. 标签数字正确；列表切换/关闭/左滑  
5. 新标签进入快捷方式页  
6. ⋮ 六项可用；发送到 Mac 在已连接时生效  
