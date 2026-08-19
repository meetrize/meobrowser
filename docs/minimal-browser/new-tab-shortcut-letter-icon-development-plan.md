# Launchpad 快捷方式自定义首字母 + 色板 — 开发计划

> 基于 [new-tab-shortcut-letter-icon-design.md](new-tab-shortcut-letter-icon-design.md) 的分阶段实施计划。  
> 前置条件：Launchpad NTP-0～NTP-3、Favicon ICO、编辑 Sheet 已可用。  
> **状态：GLY-0～GLY-4 已完成（2026-08-19）。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase GLY-0 | 模型与 Store | 完成 | `BrowserShortcutItem` 三字段 + `BrowserShortcutIconPalette` + 序列化 |
| Phase GLY-1 | Mac 编辑窗 | 完成 | 自动 / 自定义色块 + 4×4 色板 + 预览 |
| Phase GLY-2 | Mac 渲染与同步 | 完成 | Cell / 子 tile / 补全 + Sync / Companion 透传 |
| Phase GLY-3 | Android 对齐 | 完成 | `ShortcutItem` + 编辑对话框 + Grid 绑定 |
| Phase GLY-4 | 文档与验收 | 完成 | design / 本计划 / acceptance + `make browser` |

---

## Phase GLY-0：模型与 Store

**目标**：数据层与色板工具，无 UI。

### 任务清单

- [x] **0.1** `BrowserShortcutItem` 增加 `iconStyle` / `iconLetter` / `iconColorIndex` + `usesCustomLetterIcon`
- [x] **0.2** `BrowserShortcutStore` 序列化读写三键（payload v2 兼容）
- [x] **0.3** `addShortcutWithTitle:…iconStyle:iconLetter:iconColorIndex:` / `updateShortcutWithID:…`
- [x] **0.4** `updateIconURLString:` 在 `letter` 模式跳过 writeback
- [x] **0.5** 新增 `BrowserShortcutIconPalette.h/.m`
- [x] **0.6** Makefile 编入 `BrowserShortcutIconPalette.m`

---

## Phase GLY-1：Mac 编辑窗

**目标**：编辑 Sheet 支持双模式与即时预览。

### 任务清单

- [x] **1.1** 单选：自动（Favicon）/ 自定义色块
- [x] **1.2** 字母 `SBTextField` + 4×4 色钮网格
- [x] **1.3** 模式切换启用/禁用图标链接行
- [x] **1.4** 预览：Favicon 或色板+字母
- [x] **1.5** 保存写入三字段；letter 模式不因 iconURL 校验失败拦截
- [x] **1.6** `BrowserLaunchpadView` add/update 调用新 Store API

---

## Phase GLY-2：Mac 渲染与同步

**目标**：Launchpad / 补全正确展示；同步不丢字段。

### 任务清单

- [x] **2.1** `BrowserShortcutCellView` letter 路径 + 跳过 `loadIconForShortcut`
- [x] **2.2** 文件夹子 tile `configureWithShortcut:` 同样守卫
- [x] **2.3** `BrowserShortcutWritebackIconIfNeeded` 跳过 `usesCustomLetterIcon`
- [x] **2.4** `BrowserShortcutSuggestionPanel` letter 展示一致
- [x] **2.5** `SyncShortcutBridge` export/import 三字段
- [x] **2.6** `CompanionShortcutSync` record 三字段

---

## Phase GLY-3：Android 对齐

**目标**：Companion 新标签页同等能力与同步字段。

### 任务清单

- [x] **3.1** `ShortcutItem` + `ShortcutStore` JSON 三字段
- [x] **3.2** `ShortcutIconPalette.kt`（16 色 HSV 与 Mac 对齐）
- [x] **3.3** `dialog_edit_shortcut.xml` 双模式 + 色板 Grid
- [x] **3.4** `BrowserActivity.editShortcut` 逻辑
- [x] **3.5** `ShortcutGridAdapter` / `ShortcutIconHelper` letter 跳过 favicon

---

## Phase GLY-4：文档与验收

### 任务清单

- [x] **4.1** 本设计文档与开发计划
- [x] **4.2** [acceptance.md](acceptance.md) 追加 GLY 节
- [x] **4.3** `make browser` 无警告通过

### 发布检查

```bash
make clean && make browser && make verify
make run-browser
```

手测清单：

1. 新建快捷方式 → 选「自定义色块」→ 改字母/色 → 保存 → Launchpad 显示色块  
2. 重启 App → 设置仍在  
3. 编辑 → 切回「自动」→ Favicon 恢复（若有缓存）  
4. 旧快捷方式（无三字段）→ 仍走自动 Favicon / 哈希字母  
5. letter 模式：网络面板无多余 favicon 请求  
6. Android Companion：同上 + 与 Mac 同步字段不丢  

---

## 涉及文件（变更汇总）

```text
SimpleBrowser/NewTab/BrowserShortcutIconPalette.h/.m   # 新增
SimpleBrowser/NewTab/BrowserShortcutItem.h/.m
SimpleBrowser/NewTab/BrowserShortcutStore.h/.m
SimpleBrowser/NewTab/BrowserShortcutEditorSheet.m
SimpleBrowser/NewTab/BrowserShortcutCellView.m
SimpleBrowser/NewTab/BrowserLaunchpadView.m
SimpleBrowser/BrowserWindowController.m
SimpleBrowser/SyncCore/SyncShortcutBridge.m
SimpleBrowser/LoginAssist/Companion/CompanionShortcutSync.m
SimpleBrowser/AddressBar/BrowserShortcutSuggestionPanel.m
Makefile

companion/.../ShortcutIconPalette.kt                 # 新增
companion/.../ShortcutStore.kt
companion/.../ShortcutIconHelper.kt
companion/.../ShortcutGridAdapter.kt
companion/.../BrowserActivity.kt
companion/.../res/layout/dialog_edit_shortcut.xml
companion/.../res/values/strings.xml
```
