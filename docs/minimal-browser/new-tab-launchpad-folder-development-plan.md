# Launchpad 快捷方式文件夹 — 开发计划

> 基于 [new-tab-launchpad-folder-design.md](new-tab-launchpad-folder-design.md) 的分阶段实施计划。  
> 前置条件：Launchpad NTP-0～NTP-3 已完成；现码为垂直滚动网格（无横向分页）。  
> **状态：FLD-0～FLD-3 已完成（2026-07-14）。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase FLD-0 | 数据层 | 完成 | `kind` / `folderID` + version 2 迁移 + Store API |
| Phase FLD-1 | MVP 交互 | 完成 | 拖合建夹、Overlay、打开/改名/解散 |
| Phase FLD-2 | 体验打磨 | 完成 | 合并高亮、展开动画、四宫格、深浅色 |
| Phase FLD-3 | 联调验收 | 完成 | 构建通过、文档与 acceptance 同步 |

---

## Phase FLD-0：数据层

**目标**：扩展模型与持久化，提供文件夹 CRUD，补全仅匹配 link。

### 任务清单

- [x] **0.1** `BrowserShortcutItem` 增加 `kind`、`folderID`；folder 工厂方法
- [x] **0.2** 序列化 `"kind"` / `"folderID"`；外层 `{ version: 2, shortcuts: [...] }`
- [x] **0.3** `loadShortcuts`：folder 允许空 URL；孤儿升顶层；旧数组迁移
- [x] **0.4** `topLevelShortcuts:` / `childrenOfFolderID:inShortcuts:`
- [x] **0.5** 建夹 / 移入 / 拖出 / 改名 / 解散 / 删夹 API
- [x] **0.6** `shortcutsMatchingQuery:` 跳过 folder，扁平匹配全部 link
- [x] **0.7** 夹空时自动删除文件夹

---

## Phase FLD-1：MVP 交互

**目标**：编辑态拖合建夹，单击展开 Overlay，夹内可打开与整理。

### 任务清单

#### 1A — Cell

- [x] **1.1** folder cell：半透明底板 + 最多 4 子项缩略
- [x] **1.2** 合并环高亮 API（悬停达标时）
- [x] **1.3** 编辑态 ×：文件夹走解散/删除确认

#### 1B — 顶层网格

- [x] **1.4** Collection 仅展示顶层（`folderID` 空）；全量仍存 `mutableShortcuts`
- [x] **1.5** `validateDrop` / `acceptDrop` 三分支：reorder / 建夹 / 移入
- [x] **1.6** 中心命中区 + 悬停 ≥ 400 ms 才合并；禁止嵌套
- [x] **1.7** 单击 folder → present Overlay，不导航

#### 1C — Overlay

- [x] **1.8** 新增 `BrowserShortcutFolderOverlay.h/.m`（挂 Launchpad 内）
- [x] **1.9** 遮罩关闭、Esc 优先关 Overlay
- [x] **1.10** 夹内网格：单击 / 中键打开（先 dismiss）
- [x] **1.11** 标题 `SBTextField` 就地改名
- [x] **1.12** 右键：打开 / 重命名 / 解散 / 删除全部
- [x] **1.13** 夹内拖出到遮罩外 → 回顶层
- [x] **1.14** Makefile 加入 Overlay 源文件

---

## Phase FLD-2：体验打磨

**目标**：手感接近 macOS Launchpad。

### 任务清单

- [x] **2.1** 合并悬停光环稳定（400 ms）
- [x] **2.2** 四宫格随子项变化刷新
- [x] **2.3** 展开 / 收起 scale + fade（锚点 folder cell）
- [x] **2.4** 深浅色遮罩与夹底板可读

---

## Phase FLD-3：联调与验收

### 任务清单

- [x] **3.1** `make clean && make browser`
- [x] **3.2** 对照 [设计稿 §10](new-tab-launchpad-folder-design.md#10-分期与验收) 勾选
- [x] **3.3** 更新 [acceptance.md](acceptance.md)
- [x] **3.4** 本计划各阶段勾选完成；更新 README 索引

### 发布检查

```bash
make clean && make browser && make verify
make run-browser
```

---

## 实现文件

```text
SimpleBrowser/NewTab/
├── BrowserShortcutItem.h/.m           # kind / folderID
├── BrowserShortcutStore.h/.m          # version 2 + 文件夹 API
├── BrowserShortcutCellView.h/.m       # folder 四宫格、合并环
├── BrowserLaunchpadView.h/.m          # topLevel、merge drop、present overlay
└── BrowserShortcutFolderOverlay.h/.m  # 展开层（新增）
```

---

## 延后工作（FLD-3+）

- 文件夹嵌套
- 夹内分页
- 右键「新建空文件夹」
- 拖到边缘自动翻页后再合并
- 补全副标题「工作 › GitHub」

---

## 完成定义（Definition of Done）

1. Phase FLD-0～FLD-3 任务全部勾选
2. 行为符合 [new-tab-launchpad-folder-design.md](new-tab-launchpad-folder-design.md)
3. 旧快捷方式数据无回归；夹内站点可被地址栏补全匹配
4. 无编译警告；Makefile 可独立构建
5. 文档与实现一致

**Launchpad 快捷方式文件夹已交付。**
