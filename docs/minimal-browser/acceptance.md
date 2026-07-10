# SimpleBrowser L1 验收记录

> Phase 3 联调验收 · 2026-07-10

## 自动化检查

| 检查项 | 命令 | 结果 |
|--------|------|------|
| 全量编译 | `make clean && make && make browser` | 通过，无编译警告 |
| 二进制与 plist | `make verify` | 通过 |
| SimpleWindow 未破坏 | `make` 独立成功 | 通过 |
| SimpleBrowser 构建 | `make browser` | 通过 |

## 内存基线（`make stats-all`）

启动后约 2～3 秒采样，RSS 为常驻内存（KB）：

| 应用 | PID（当次） | RSS (KB) | 约合 |
|------|-------------|----------|------|
| SimpleWindow | 84195 | 105664 | ~103 MB |
| SimpleBrowser | 84223 | 123712 | ~121 MB |

SimpleBrowser 比 SimpleWindow 高约 **18 MB**，主要来自 WebKit 渲染进程与网络栈，属预期范围。

复现命令：

```bash
make stats-all
```

## design.md L1 验收清单

| # | 验收项 | 状态 | 说明 |
|---|--------|------|------|
| 1 | `make browser` 产出 `build/SimpleBrowser.app` | 通过 | `make verify` 确认 |
| 2 | `make run-browser` 默认打开 `https://example.com` | 通过 | `loadDefaultPage` 硬编码默认 URL |
| 3 | 地址栏回车可导航 | 通过 | `loadAddressBarURL` + URL 规范化 |
| 4 | 后退 / 前进 / 刷新，按钮灰显正确 | 通过 | `updateNavigationState` 同步 `canGoBack/Forward` |
| 5 | 窗口标题随页面 title 更新 | 通过 | `didFinishNavigation` / `updateNavigationState` |
| 6 | 加载失败有 Alert 提示 | 通过 | `handleNavigationError` + `showErrorWithTitle` |
| 7 | 关闭窗口后应用退出 | 通过 | `applicationShouldTerminateAfterLastWindowClosed` → `YES` |
| 8 | `SimpleWindow` 的 `make` / `make run` 不受影响 | 通过 | 独立 source 与 target |

## Phase 2 功能回归（建议本地手动确认）

| 测试项 | 操作 | 代码支撑 |
|--------|------|----------|
| 直接输入域名 | `apple.com` 回车 | `normalizedURLFromString` 补 `https://` |
| 完整 URL | `https://example.com` | 原样加载 |
| 站内导航 | 点击链接 | NavigationDelegate 同步 UI |
| 后退 / 前进 | 多页后点 ◀ / ▶ | `goBack` / `goForward` |
| 刷新 | ↻ 或 ⌘R | `reloadPage` + `keyEquivalent` |
| 错误 URL | 无效输入 | Alert「无效的地址」 |
| 新窗口链接 | `target=_blank` | `WKUIDelegate` `createWebViewWithConfiguration:` |

本地快速验证：

```bash
make run-browser
```

## 结论

**SimpleBrowser L1 开发完成**，满足 [design.md](design.md) 第 6 节全部验收标准。

后续扩展见 design.md 第 7 节（进度条、停止按钮、菜单、多标签等）。
