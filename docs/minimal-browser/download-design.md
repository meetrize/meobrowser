# 下载管理 — 交互与实现方案（V1）

> 目标：为 MeoBrowser 提供轻量、可预期的文件下载能力，默认静默写入「下载」文件夹，并用工具栏浮层面板管理进度与文件操作。  
> 状态：**V1 已实现**（2026-07-14）  
> 关联：[professional-features-roadmap.md](professional-features-roadmap.md) §3.8 · [design.md](design.md)

---

## 1. 方案定位

### 1.1 做什么（V1）

| 能力 | 说明 |
|------|------|
| 自动下载 | 附件响应 / WebKit 无法展示的 MIME → `WKNavigationResponsePolicyDownload` |
| 链接下载 | 系统右键菜单「下载链接的文件」→ `navigationAction:didBecomeDownload:` |
| 静默落盘 | **永远不问路径**；写入 `~/Downloads`，重名自动加 `-1`、`-2`… |
| 下载按钮 | 地址栏右侧 ActionGroup 首项；溢出时进「更多」菜单；进行中/完成角标 |
| 下载面板 | 锚在按钮下方的 `NSPanel`（对齐地址栏补全浮层）；⌘J 开关 |
| 列表操作 | 取消、在 Finder 中显示、用默认 App 打开；完成项可拖到 Finder |
| 关窗提示 | 仍有进行中下载时确认后再关 |

### 1.2 不做什么（V1）

- 不弹出 `NSSavePanel` / 不询问保存位置（V2 可选设置）
- 不做底部 Chrome 式 shelf、不做独立下载窗口、不做侧栏
- 不暂停 / 断点续传 UI（`resumeData` 仅保留给失败状态，不暴露）
- 不做永久下载历史库；仅内存中保留「进行中 + 近期完成」
- 不强制把可内联的 PDF 等改成下载（用户可用系统菜单下载）

### 1.3 设计原则

1. **默默进行、可感知**：不挡浏览；工具栏即状态信标。  
2. **工作流终点在 Finder**：一键显示 / 拖拽，而不是在浏览器里管理文件。  
3. **与现有 chrome 同构**：浮层模式复用地址栏补全的 `NSPanel` 语言。  
4. **键盘可达**：⌘J 打开/关闭下载面板。

---

## 2. 交互设计

### 2.1 触发与默认行为

```
导航响应为附件 / 无法展示
  或 用户右键「下载链接的文件」
        ↓
  写入 ~/Downloads（冲突自动重命名）
        ↓
  工具栏按钮进入「进行中」态；可选自动弹出面板（首次会话可关）
        ↓
  完成后角标提示；单击行 → Finder 选中；双击 /「打开」→ 默认 App
```

### 2.2 Chrome 落点

```
[ ← → ↻ ] [ ========== 地址栏 ★ ========== ] [ ↓ ⋯ ]
                                              ↑
                                   下载（右侧按钮组首项）
```

| 状态 | 视觉 |
|------|------|
| 空闲、无近期下载 | `arrow.down.circle` |
| 有进行中 | 圆形进度（或图标填充感）+ tooltip「正在下载 N 项」 |
| 有未查看的完成项 | 小红点角标；点开面板后清除 |
| 有失败项 | 感叹提示，可在列表中清除 |

### 2.3 下载面板

- 非激活浮层（`canBecomeKeyWindow == NO`），点外部 / Esc / 再按 ⌘J 关闭  
- 表头：「下载」+「清空已完成」  
- 行：文件名、来源 host、进度条/状态文案、取消或显示/打开  
- 最多约 6 行可见，其余滚动；条目上限约 50，超出剔除最旧已完成项  

### 2.4 菜单

- 「文件」或窗口相关入口可不建完整菜单；在应用菜单旁侧可用 target-action：  
  - **下载** ⌘J → 切换面板  

「链接另存为」在本产品 V1 中语义为「下载链接」且**不问路径**（系统自带菜单 + 本 Manager 落盘）。

---

## 3. 架构

```
WKWebView (NavigationDelegate)
        │ decidePolicyForNavigationResponse / didBecomeDownload
        ▼
BrowserDownloadManager  ←── WKDownloadDelegate
        │ items / notifications
        ├──────────────────┬──────────────────┐
        ▼                  ▼                  ▼
  工具栏按钮状态      BrowserDownloadPanel   关窗确认
```

| 类型 | 职责 |
|------|------|
| `BrowserDownloadItem` | 单次下载模型：状态、进度、路径、源 URL |
| `BrowserDownloadManager` | 持有列表；实现 `WKDownloadDelegate`；唯一落盘策略 |
| `BrowserDownloadPanel` | 浮层列表 UI |
| `BrowserWindowController` | 挂载导航策略、按钮、⌘J、关窗 |

模块目录：`SimpleBrowser/Downloads/`。

### 3.1 何时转下载

```objc
!navigationResponse.canShowMIMEType
|| Content-Disposition 含 attachment（忽略大小写）
```

其余主文档导航 `Allow`，由 WebKit 内联展示。

### 3.2 落盘规则

1. 目录 = 用户「下载」文件夹（`NSDownloadsDirectory`）  
2. 文件名优先 `suggestedFilename`，非法字符替换为 `_`  
3. 目标路径**必须不存在**（WebKit 要求）；已存在则 `name-1.ext`、`name-2.ext`…  
4. `completionHandler(nil)` 仅用于用户取消或无法创建目录  

---

## 4. 验收清单（V1）

- [x] zip / 常见附件一点即下到 Downloads，无对话框  
- [x] 进行中时可在面板取消；工具栏反映进度  
- [x] ⌘J 开关面板；Esc / 点外部关闭  
- [x] 「显示」在 Finder 中选中文件；「打开」用默认 App  
- [x] 完成项可拖到 Finder  
- [x] 关窗时若有进行中下载会确认  
- [x] 系统右键「下载链接的文件」进入同一列表  

### 实现文件

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/Downloads/BrowserDownloadItem.*` | 下载项模型 |
| `SimpleBrowser/Downloads/BrowserDownloadManager.*` | `WKDownloadDelegate`、落盘、`~/Downloads` |
| `SimpleBrowser/Downloads/BrowserDownloadPanel.*` | 工具栏锚点浮层列表 |
| `SimpleBrowser/BrowserWindowController.m` | 导航策略 + 按钮 + ⌘J + 关窗确认 |
| `SimpleBrowser/BrowserMenus.m` | 「文件 → 下载」⌘J |

---

## 5. V2 展望（不在本版）

- 设置：自定义目录、「下载前询问」开关  
- 完成通知（Notification Center）  
- 失败重试 / 续传 UI  
- 强制下载当前页（PDF 另存）显式入口  
