# objcdemo 文档

本目录存放项目设计与开发计划文档。

## 文档索引

| 文档 | 说明 |
|------|------|
| [minimal-browser/design.md](minimal-browser/design.md) | SimpleBrowser 最精简浏览器 — 技术方案与架构设计 |
| [minimal-browser/development-plan.md](minimal-browser/development-plan.md) | SimpleBrowser 分阶段开发计划与验收标准 |
| [minimal-browser/multi-tab-design.md](minimal-browser/multi-tab-design.md) | 多标签页（Chrome 式标题栏）设计方案 L2 |
| [minimal-browser/acceptance.md](minimal-browser/acceptance.md) | SimpleBrowser L1 验收记录 |
| [sbkit/text-input.md](sbkit/text-input.md) | SBKit 文本输入与编辑快捷键架构 |

## 构建命令

| 命令 | 说明 |
|------|------|
| `make` | 构建 SimpleWindow（默认 target） |
| `make run` | 构建并启动 SimpleWindow |
| `make browser` | 构建 SimpleBrowser |
| `make run-browser` | 构建并启动 SimpleBrowser |
| `make verify` | 检查两个 app 二进制与 Info.plist |
| `make stats` | 采样 SimpleWindow 内存占用 |
| `make stats-browser` | 采样 SimpleBrowser 内存占用 |
| `make stats-all` | 依次采样两个应用 |
| `make clean` | 清理 `build/` |

## 相关代码

- 演示应用：`SimpleWindow/`（AppKit + XIB + Makefile）
- 最简浏览器：`SimpleBrowser/`（AppKit + WKWebView + Makefile，L1 已完成）
- 共享 UI 基础库：`SBKit/`（标准菜单、文本输入控件）
