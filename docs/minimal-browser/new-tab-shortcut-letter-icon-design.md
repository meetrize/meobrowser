# Launchpad 快捷方式自定义首字母 + 色板 — 设计方案

> 目标：在编辑快捷方式时支持「自定义色块」（固定 16 色 + 可编辑首字母），**零图片 blob**、**跨端可同步字段**，且与现有 Favicon 自动模式并存。  
> 状态：**GLY-0～GLY-4 已实现**（2026-08-19）；开发计划见 [new-tab-shortcut-letter-icon-development-plan.md](new-tab-shortcut-letter-icon-development-plan.md)  
> 前置依赖：[new-tab-launchpad-design.md](new-tab-launchpad-design.md)（NTP-0～NTP-3）、[favicon-fetch-cache-design.md](favicon-fetch-cache-design.md)（ICO）

---

## 1. 方案定位

### 1.1 做什么（P0 / GLY）

| 模式 | 名称 | 行为 |
|------|------|------|
| **默认** | 自动（`auto`） | 与现行一致：Favicon 优先 → 失败则 URL 哈希色 + 名称/域名首字母 |
| **P0 新增** | 自定义色块（`letter`） | 16 色固定色板 + 用户可改 1 个字符；**不加载 Favicon** |

编辑入口：Launchpad 右键「编辑…」→ `BrowserShortcutEditorSheet`（Mac）/ `dialog_edit_shortcut`（Android Companion）。

### 1.2 不做什么

- Emoji 选择器、预设图库、本地上传图标
- 文件夹自定义图标（仍用四宫格子 favicon / 字母）
- 在 UserDefaults 存 `NSData` / base64 图片
- 自定义色块模式的 Favicon 自动回写（`BrowserShortcutWritebackIconIfNeeded` 跳过）

### 1.3 原则

1. **数据轻量** — 每条快捷方式仅多 3 个字段（style / letter / colorIndex）。  
2. **向后兼容** — payload version 仍为 2；缺键视为 `auto`。  
3. **用户意图优先** — `letter` 模式强制展示色块，不因缓存 favicon 覆盖。  
4. **跨端一致** — Mac / Android / SyncCore / Companion 透传同一 JSON 键名。

---

## 2. 数据模型

扩展 `BrowserShortcutItem` / `ShortcutItem`（仅 `link`）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `iconStyle` | `"auto"` \| `"letter"` | 默认 `auto` |
| `iconLetter` | string | `letter` 下展示字符；空则运行时从 title/url 推导 |
| `iconColorIndex` | int 0–15 | `letter` 下色板索引；非法 clamp 为 0 |

持久化示例（`BrowserShortcutStore` payload）：

```json
{
  "iconURL": "https://example.com/favicon.ico",
  "iconStyle": "letter",
  "iconLetter": "G",
  "iconColorIndex": 3
}
```

**读写规则**

- `iconStyle != letter` → 忽略 letter/color，行为与改前完全一致。  
- 切到 `letter`：保留 `iconURL`（切回 `auto` 仍可用）；单元格不请求 Favicon。  
- 切回 `auto`：`iconLetter` / `iconColorIndex` 可保留在磁盘，便于再次切换。

同步：`SyncShortcutBridge` / `CompanionShortcutSync` payload 含上述三键；旧端忽略未知键。

---

## 3. 色板与字母

`BrowserShortcutIconPalette` / `ShortcutIconPalette`：

- **16 色**：色相均匀分布（步长 360/16），`s=0.45`、`b=0.85`（贴近原 `ColorFromURLString`）。  
- **字母**：trim → 取第一个 Unicode 字形（composed character sequence）；允许中文/数字/拉丁。  
- **默认进入自定义**：letter = 标题首字；colorIndex = `url.hash % 16`。  
- **展示字母**：`iconLetter` 非空优先，否则 `defaultLetterForTitle:urlString:`。

---

## 4. 编辑窗 UI

Mac sheet（约 480×360）：

```text
名称 / 网址
图标
  [预览 40×40]
  ( ) 自动（Favicon）   [图标链接…] [自动获取]
  ( ) 自定义色块
      字母 [ G ]
      ○○ ○○ ○○ ○○  （4×4 色板）
```

- 自动：启用链接行 + 自动获取；预览走 Favicon 缓存/URL。  
- 自定义：禁用链接行；预览 = 色板 + 字母；保存时不因空 iconURL 拦截。  
- 字母输入：`SBTextField`（Mac）/ `EditText`（Android）。

---

## 5. 显示路径

```text
configure shortcut
  ├─ iconStyle == letter → 色板色 + letterLabel，跳过 Favicon fetch/writeback
  └─ auto → 现有 BrowserFaviconService 瀑布 + 哈希字母 fallback
```

涉及视图：

- `BrowserShortcutCellView`（主格 + 文件夹子 tile）  
- `BrowserShortcutSuggestionPanel`（地址栏补全，letter 时不拉网）  
- Android `ShortcutGridAdapter` + `ShortcutIconHelper.bindFavicon`

---

## 6. 内存与体积

| 项 | 预算 |
|----|------|
| 每条记录增量 | ≈ 数十字节（3 字段字符串/整数） |
| 运行时渲染 | 复用现有 letter plate + `NSColor` / `GradientDrawable`，无解码 |
| 同步 payload | 与 iconURL 同量级，无二进制 |

---

## 7. 源码布局

```text
SimpleBrowser/NewTab/
├── BrowserShortcutIconPalette.h/.m    # 色板 / 字母工具
├── BrowserShortcutItem.h/.m           # + iconStyle / iconLetter / iconColorIndex
├── BrowserShortcutStore.h/.m          # 序列化 + add/update API
├── BrowserShortcutEditorSheet.m       # 双模式编辑 UI
└── BrowserShortcutCellView.m          # letter 渲染 + fetch 守卫

SimpleBrowser/SyncCore/SyncShortcutBridge.m
SimpleBrowser/LoginAssist/Companion/CompanionShortcutSync.m
SimpleBrowser/AddressBar/BrowserShortcutSuggestionPanel.m

companion/.../newtab/
├── ShortcutIconPalette.kt
├── ShortcutStore.kt                   # ShortcutItem 字段
├── ShortcutIconHelper.kt              # letter 跳过 prefetch/bind
├── ShortcutGridAdapter.kt
└── BrowserActivity.kt                 # editShortcut 双模式
```

---

## 8. 分期与验收

| 阶段 | 内容 | 状态 |
|------|------|------|
| GLY-0 | 模型 + Store + Palette + Makefile | 完成 |
| GLY-1 | Mac 编辑窗双模式 | 完成 |
| GLY-2 | Cell / 子 tile / 补全 / Sync | 完成 |
| GLY-3 | Android 对齐 | 完成 |
| GLY-4 | 文档 + acceptance + `make browser` | 完成 |

验收见 [acceptance.md §快捷方式自定义色块](acceptance.md)。

延后（非 P0）：Emoji 选择器、预设图库、本地上传、文件夹自定义图标。
