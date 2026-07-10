# SimpleBrowser 新标签页（Launchpad）开发计划

> 基于 [new-tab-launchpad-design.md](new-tab-launchpad-design.md) 的分阶段实施计划。  
> 前置条件：多标签 L2a～L2c 已完成（`BrowserTabController`、`about:newtab` 会话恢复）。  
> **状态：NTP-0～NTP-3 已全部完成（2026-07-10）。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase NTP-0 | 架构接入 | 完成 | Launchpad 与 WebView 叠放切换 |
| Phase NTP-1 | MVP 网格 | 完成 | 默认快捷方式 + 单击/中键打开 |
| Phase NTP-2 | 可定制 | 完成 | 增删改、拖拽、分页、持久化 |
| Phase NTP-3 | 联调验收 | 完成 | 通过验收清单、文档同步 |

---

## Phase NTP-0：架构接入

**目标**：建立 Launchpad 视图与现有标签体系的显隐切换，替换 HTML 占位路径。

### 任务清单

- [x] **0.1** 创建目录 `SimpleBrowser/NewTab/`
- [x] **0.2** 添加 `BrowserShortcutItem.h/.m`（模型骨架）
- [x] **0.3** 添加 `BrowserShortcutStore.h/.m`
- [x] **0.4** 添加 `BrowserLaunchpadView.h/.m` 空壳
- [x] **0.5** 修改 `BrowserWindowController`
- [x] **0.6** 修改 `BrowserTab.loadNewTabPage`
- [x] **0.7** Makefile 增加 `NewTab/*.m` 源文件

---

## Phase NTP-1：MVP 网格

**目标**：7×5 网格展示默认快捷方式，支持单击与中键打开。

### 任务清单

#### 1A — 网格 UI

- [x] **1.1** 添加 `BrowserShortcutCellView.h/.m`
- [x] **1.2** `BrowserLaunchpadView` 内嵌 `NSCollectionView`
- [x] **1.3** 窗口 resize 时网格居中、间距自适应
- [x] **1.4** 悬停放大动画（1.05，150 ms）

#### 1B — 数据与交互

- [x] **1.5** `BrowserShortcutStore` 提供 8～12 个默认站点
- [x] **1.6** 单击 cell → delegate → `BrowserTab.loadURL:`
- [x] **1.7** 中键单击 → `BrowserTabController addTabWithURL:`
- [x] **1.8** 新标签页时禁用后退/前进

#### 1C — 清理占位

- [x] **1.9** 删除 `BrowserNewTabPage`（NTP-3 移除源文件）
- [x] **1.10** `syncFromWebView` 在 `isNewTabPage` 时不误改状态

---

## Phase NTP-2：可定制

**目标**：用户可管理快捷方式，支持排序、分页与持久化。

### 任务清单

#### 2A — 持久化

- [x] **2.1** `BrowserShortcutStore` 完整 CRUD
- [x] **2.2** 保存至 `NSUserDefaults`
- [x] **2.3** 首次启动写入默认列表；之后读写用户数据
- [x] **2.4** 添加/编辑/删除后立即持久化

#### 2B — 编辑 UI

- [x] **2.5** 添加快捷方式 sheet（`SBTextField`）
- [x] **2.6** URL 校验
- [x] **2.7** 编辑模式：cell 抖动动画
- [x] **2.8** 编辑模式下 cell 左上角删除按钮
- [x] **2.9** 末尾「➕」cell 进入添加 flow
- [x] **2.10** 右键菜单
- [x] **2.11** `Esc` 退出编辑模式

#### 2C — 拖拽与分页

- [x] **2.12** 编辑模式下拖拽 reorder
- [x] **2.13** 超过 35 个自动分页
- [x] **2.14** 横向 scroll / 触控板滑动切换页
- [x] **2.15** 底部分页指示器（圆点）
- [ ] **2.16** 拖到边缘自动翻页（**延后至 NTP-4+**）

---

## Phase NTP-3：联调与验收

**目标**：对照 [new-tab-launchpad-design.md 第 11 节](new-tab-launchpad-design.md#11-验收标准ntp-1--ntp-2) 完成验收。

### 任务清单

- [x] **3.1** 全量编译：`make clean && make && make browser`
- [x] **3.2** 多标签回归：⌘T / ⌘W / ⌘⇧[ / ⌘⇧] / 会话恢复（代码路径审查 + 构建通过）
- [x] **3.3** 手动验收表（见 [acceptance.md](acceptance.md) Launchpad 节）
- [x] **3.4** 修复 `-Wall -Wextra` 警告
- [x] **3.5** 更新 `docs/README.md` 索引
- [x] **3.6** 更新 `docs/minimal-browser/acceptance.md` 追加 NTP 记录

### 发布检查

```bash
make clean && make && make browser && make verify
make run-browser
```

---

## 延后工作（NTP-4+）

- Favicon 异步拉取与磁盘缓存
- 文件夹合并与展开
- Launchpad 内搜索框
- 「最常访问」动态推荐区
- 从当前页面「添加到快捷方式」菜单项
- 拖到边缘自动翻页（2.16）
- 单元测试与 UI 自动化

---

## 完成定义（Definition of Done）

1. [new-tab-launchpad-design.md 第 11 节](new-tab-launchpad-design.md#11-验收标准ntp-1--ntp-2) 全部勾选通过
2. `BrowserNewTabPage` 已删除，Launchpad 为默认新标签页
3. 多标签与会话恢复行为不退化
4. 无编译警告；Makefile 可独立构建
5. 文档与实现一致

**Launchpad 新标签页 MVP 已交付。**
