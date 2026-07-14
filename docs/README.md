# objcdemo 文档

本目录存放项目设计与开发计划文档。

## 文档索引

| 文档 | 说明 |
|------|------|
| [minimal-browser/design.md](minimal-browser/design.md) | MeoBrowser 最精简浏览器 — 技术方案与架构设计 |
| [minimal-browser/development-plan.md](minimal-browser/development-plan.md) | MeoBrowser 分阶段开发计划与验收标准 |
| [minimal-browser/multi-tab-design.md](minimal-browser/multi-tab-design.md) | 多标签页（Chrome 式标题栏）设计方案 L2 |
| [minimal-browser/tab-strip-adaptive-width-design.md](minimal-browser/tab-strip-adaptive-width-design.md) | 标签栏自适应宽度 — Safari 向伸缩与横向滚动 |
| [minimal-browser/new-tab-launchpad-design.md](minimal-browser/new-tab-launchpad-design.md) | 新标签页 — Launchpad 式快捷方式设计方案 |
| [minimal-browser/new-tab-launchpad-folder-design.md](minimal-browser/new-tab-launchpad-folder-design.md) | Launchpad 快捷方式文件夹 — 拖合/展开交互方案 |
| [minimal-browser/new-tab-launchpad-folder-development-plan.md](minimal-browser/new-tab-launchpad-folder-development-plan.md) | Launchpad 快捷方式文件夹 — 分阶段开发计划 |
| [minimal-browser/address-bar-shortcut-autocomplete-design.md](minimal-browser/address-bar-shortcut-autocomplete-design.md) | 地址栏快捷方式补全 — 交互与实现方案 |
| [minimal-browser/address-bar-shortcut-autocomplete-development-plan.md](minimal-browser/address-bar-shortcut-autocomplete-development-plan.md) | 地址栏快捷方式补全 — 开发计划 |
| [minimal-browser/new-tab-launchpad-development-plan.md](minimal-browser/new-tab-launchpad-development-plan.md) | Launchpad 新标签页分阶段开发计划 |
| [minimal-browser/acceptance.md](minimal-browser/acceptance.md) | MeoBrowser L1 + Launchpad 新标签页验收记录 |
| [minimal-browser/professional-features-roadmap.md](minimal-browser/professional-features-roadmap.md) | 面向技术/专业用户的功能规划与路线图 |
| [minimal-browser/download-design.md](minimal-browser/download-design.md) | 下载管理 — 交互与实现方案（V1） |
| [sbkit/text-input.md](sbkit/text-input.md) | SBKit 文本输入与编辑快捷键架构 |

## 构建命令

| 命令 | 说明 |
|------|------|
| `make` | 构建 SimpleWindow（默认 target） |
| `make run` | 构建并启动 SimpleWindow |
| `make browser` | 构建 MeoBrowser |
| `make run-browser` | 构建并启动 MeoBrowser |
| `make verify` | 检查两个 app 二进制与 Info.plist |
| `make stats` | 采样 SimpleWindow 内存占用 |
| `make stats-browser` | 采样 MeoBrowser 内存占用 |
| `make stats-all` | 依次采样两个应用 |
| `make clean` | 清理 `build/` |

## 相关代码

- 演示应用：`SimpleWindow/`（AppKit + XIB + Makefile）
- 最简浏览器：`SimpleBrowser/` 源码目录（产品名 **MeoBrowser**，AppKit + WKWebView + 多标签 + Launchpad 新标签页）
- Launchpad 新标签页：`SimpleBrowser/NewTab/`（快捷方式网格、持久化、编辑）
- 共享 UI 基础库：`SBKit/`（标准菜单、文本输入控件）
