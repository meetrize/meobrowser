# 地址栏快捷方式补全 — 开发计划

> 基于 [address-bar-shortcut-autocomplete-design.md](address-bar-shortcut-autocomplete-design.md) 的分阶段实施计划。  
> 前置条件：Launchpad 新标签页 NTP-0～NTP-3 已完成（`BrowserShortcutStore`、快捷方式网格）。  
> **状态：AC-0～AC-3 已全部完成（2026-07-13）。**

---

## 行为定稿（相对设计稿 §2.3 / §3.5 的调整）

| 按键 | 定稿行为 |
|------|----------|
| **Enter** | 面板打开且有匹配 → **直接打开当前选中项**（默认第 1 项，无需先按方向键） |
| **Tab** | 面板打开且有匹配 → **仅将地址栏补全为选中项 URL**，不导航；关闭面板，焦点留在地址栏 |
| **Shift+Tab** | 同 Tab（补全不打开，不反向切焦点） |
| 无匹配时 Enter | 走现有 `loadAddressBarURL`（URL 识别或搜索引擎） |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase AC-0 | 数据层 | 完成 | `shortcutsMatchingQuery:limit:` |
| Phase AC-1 | MVP 补全 | 完成 | 面板 + 键鼠打开 |
| Phase AC-2 | 体验打磨 | 完成 | 图标、高亮、视觉效果 |
| Phase AC-3 | 联调验收 | 完成 | 构建通过、文档同步 |

---

## Phase AC-0：数据层

**目标**：在 `BrowserShortcutStore` 提供可复用的匹配 API。

### 任务清单

- [x] **0.1** `BrowserShortcutStore.h` 声明 `+shortcutsMatchingQuery:limit:`
- [x] **0.2** 实现 title / host 子串匹配（不区分大小写）
- [x] **0.3** 实现排序分：title 前缀 100 > title 子串 80 > host 前缀 60 > host 子串 40；同分按 `sortOrder`
- [x] **0.4** 结果上限 8 条

---

## Phase AC-1：MVP 补全

**目标**：地址栏输入触发建议面板，支持鼠标与键盘。

### 任务清单

#### 1A — 模块骨架

- [x] **1.1** 创建 `SimpleBrowser/AddressBar/`
- [x] **1.2** `BrowserAddressBarAutocompleteController.h/.m`（状态机、防抖、键盘）
- [x] **1.3** `BrowserShortcutSuggestionPanel.h/.m`（`NSPanel` 浮层 + 行视图）
- [x] **1.4** Makefile 增加源文件与 `-IAddressBar`

#### 1B — 面板 UI

- [x] **1.5** 面板宽度跟随地址栏；最多 8 行，超出滚动
- [x] **1.6** 每行：首字母占位图标 + 标题 + 域名
- [x] **1.7** 选中行高亮；悬停同步选中索引
- [x] **1.8** 非激活浮层，点击不抢地址栏焦点

#### 1C — 交互

- [x] **1.9** 输入 ≥1 字 + 有匹配 → 50 ms 防抖后显示面板
- [x] **1.10** 单击行 → 当前标签 `loadURL:`
- [x] **1.11** ↑/↓ 循环选中；Enter 打开选中项
- [x] **1.12** Tab / Shift+Tab → 补全 URL 到地址栏，不打开
- [x] **1.13** Esc / 失焦（150 ms）/ 无匹配 → 关闭面板
- [x] **1.14** 窗口 resize → 更新面板位置

#### 1D — 集成

- [x] **1.15** `BrowserWindowController` 创建 controller，绑定 `addressField`
- [x] **1.16** `control:textView:doCommandBySelector:` 委托方向键 / Tab / Esc / Enter
- [x] **1.17** 打开 URL 复用 `launchpadView:openURL:` / `openURLInNewTab:` 路径

---

## Phase AC-2：体验打磨

**目标**：视觉与 Launchpad 一致，支持中键新标签。

### 任务清单

- [x] **2.1** 行内匹配子串高亮（标题 + 域名）
- [x] **2.2** 异步 favicon（`iconURLString` 或站点 favicon，失败保持字母占位）
- [x] **2.3** 中键单击 → 新标签打开
- [x] **2.4** 面板 `NSVisualEffectView` 浅/深色适配
- [x] **2.5** Accessibility：`"{title}，{host}"` + 选中态

---

## Phase AC-3：联调与验收

**目标**：对照设计稿第 10 节验收（含行为定稿）。

### 任务清单

- [x] **3.1** 全量编译：`make clean && make browser`
- [x] **3.2** 手动验收（见下方清单）
- [x] **3.3** 修复 `-Wall -Wextra` 警告
- [x] **3.4** 更新 [address-bar-shortcut-autocomplete-design.md](address-bar-shortcut-autocomplete-design.md) 行为定稿
- [x] **3.5** 更新 [docs/README.md](../README.md) 索引
- [x] **3.6** 本计划各阶段勾选为完成

### 验收清单

- [x] 新标签页输入 `git`，出现 GitHub 等建议
- [x] 直接 Enter（未按方向键）打开第 1 项
- [x] Tab 补全 URL 但不导航；再 Enter 可正常打开
- [x] ↓ 选中其他项后 Enter 打开对应 URL
- [x] 单击 / 中键（新标签）正常
- [x] Esc 关闭且保留输入；⌘V 粘贴后重新匹配
- [x] 增删快捷方式后列表同步

### 发布检查

```bash
make clean && make browser && make verify
make run-browser
```

---

## 实现文件

```text
SimpleBrowser/AddressBar/
├── BrowserAddressBarAutocompleteController.h/.m
└── BrowserShortcutSuggestionPanel.h/.m

SimpleBrowser/NewTab/BrowserShortcutStore.m   # +shortcutsMatchingQuery:limit:
SimpleBrowser/BrowserWindowController.m       # 集成
```

---

## 延后工作（AC-4+）

- Launchpad 网格内搜索（复用 Store API）
- 历史 / 最常访问合并
- 拼音首字母匹配
- 设置项：Tab 行为、Enter 是否强制打开第一项

---

## 完成定义（Definition of Done）

1. Phase AC-0～AC-3 任务全部勾选
2. 行为符合本文「行为定稿」表
3. 无编译警告；Makefile 可独立构建
4. 设计文档与实现一致

**地址栏快捷方式补全已交付。**
