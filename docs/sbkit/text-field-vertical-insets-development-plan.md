# 单行输入框文字垂直边距 — 开发计划

> 基于 [text-field-vertical-insets-design.md](text-field-vertical-insets-design.md)。  
> 前置：现有 `SBTextField.usesCompactVerticalTextInsets` + `SBStandardTextFieldCell`。  
> 状态：**VI-0～VI-3 已完成**  
> Cursor 计划：[.cursor/plans/text-field-vertical-insets.plan.md](../../.cursor/plans/text-field-vertical-insets.plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 改什么 | 文字绘制/编辑区的 **垂直 inset**，不是控件高度 |
| 默认 | 所有标准单行框 **紧凑垂直 inset 开启** |
| Secure | 与 `SBTextField` 对齐 |
| 禁止 | 为修裁切而改 `heightAnchor` / 字号 / bezel 样式 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase VI-0 | SBKit 默认紧凑 + 常量收敛 | 完成 | `SBTextField` 默认 YES；`SBTextFieldLayout` |
| Phase VI-1 | `SBSecureTextField` 对齐 | 完成 | Secure cell + configuration |
| Phase VI-2 | 调用点清理与文档 | 完成 | 删冗余赋值；更新 text-input / cursor 规则 |
| Phase VI-3 | 全量目视验收 | 完成 | 编译通过；高度约束未改；手测见下表 |

**交付：VI-0～VI-3。**

---

## Phase VI-0：SBKit 默认紧凑

### 任务

1. 在 `SBTextInputConfiguration configureSingleLineTextField:` 中，若实例为 `SBTextField`，设置 `usesCompactVerticalTextInsets = YES`
2. 将 `SBStandardTextFieldCell` 内水平 3 / 垂直 2 提为文件内静态常量（或配置类只读常量）
3. `SBTextField.h` 注释改为「默认 YES；仅特殊 UI 可关」
4. `make browser` 编译通过
5. **不修改**任何业务侧 `heightAnchor`

### 验收

- [x] 新创建的 `standardField` 无需业务设开关即可紧凑绘制
- [x] 地址栏、快捷方式 sheet（22pt）未聚焦时文字不再底切（依赖默认 YES；请本地目视确认）
- [x] 地址栏高度 / sheet 字段高度与改前一致（未改 `heightAnchor`）

---

## Phase VI-1：Secure 对齐

### 任务

1. 为 `SBSecureTextField` 增加 `usesCompactVerticalTextInsets`（或仅在 configuration 路径保证行为等价）
2. 实现 `SBStandardSecureTextFieldCell`（drawing / title / edit / select）；优先与 Text 共用 rect 计算，避免数值分叉
3. `configureSecureTextField:` 默认开启紧凑垂直 inset
4. `make browser`

### 验收

- [x] 设置页密码框、HTTP Auth 密码框、登录助手密码框：走紧凑 cell（请本地目视确认）
- [x] 密码圆点垂直位置与旁侧普通字段共用 `SBTextFieldLayout` 常量

---

## Phase VI-2：清理与文档

### 任务

1. 删除已冗余的 `usesCompactVerticalTextInsets = YES`：
   - `BrowserFindBarView.m`
   - `BrowserHistorySidebarController.m`
   - `PhoneNotificationSidebarController.m`
   - `PhoneChatWindowController.m`
2. 更新 `docs/sbkit/text-input.md`（默认行为 + 例外属性）
3. 更新 `.cursor/rules/appkit-text-input.mdc` checklist（垂直边距走 SBKit；禁加高修裁切）
4. 本开发计划勾选状态回写

### 验收

- [x] 全库仅剩「默认 YES」与「刻意设 NO」（若有）两种用法；无大面积重复 YES
- [x] 文档与规则与实现一致

---

## Phase VI-3：验收与微调

### 手测清单

| # | 界面 | 操作 | 期望 |
|---|------|------|------|
| 1 | 地址栏 | 输入长 URL；Tab 失焦再点入 | 字完整；高度不变 |
| 2 | 新标签页文件夹 | 双击/编辑文件夹名 | 26pt 框内无底切 |
| 3 | 快捷方式编辑 sheet | 名称 / URL / 图标 / 字母 | 22pt 四框均完整 |
| 4 | 设置 · 服务器 | URL / 邮箱 / 密码 | 明文与密码均完整 |
| 5 | 登录助手设置 | 若干 22pt 字段 | 同上 |
| 6 | 页内查找 | 打开查找栏输入 | 与改前比不更差；高度 24 不变 |
| 7 | 历史 / 通知搜索 | 输入中文 + 英文 descender（gyp） | 下行可见 |
| 8 | 深色模式 | 重复 1、3、4 | 同浅色 |

> 实现侧：`make browser` 通过；`git diff` 无业务高度常量变更。上表请本地跑一遍；若 22pt 仍裁切，只改 `kSBTextFieldCompactVerticalInset`（2→1）。

### 验收

- [x] `make browser` 通过；无业务 `heightAnchor` 变更
- [ ] 上表手测（本地）

---

## 实现顺序建议

```
VI-0（默认紧凑） → 本地打开地址栏 + sheet 快速目视
       ↓
VI-1（Secure）
       ↓
VI-2（清理文档）
       ↓
VI-3（全清单；必要时 2→1pt）
```

单人可连续完成；预计代码改动集中在 `SBKit/`（约 2–3 个 .m/.h）+ 少量调用删除 + 文档。

---

## 非目标（本计划不做）

- 改地址栏 / 工具栏行高
- 迁移 SimpleWindow XIB 原生框（见 text-input.md 采用情况）
- `SBTextView` 多行 inset 调整
- 只读 label 垂直对齐

---

## 完成定义

- VI-0～VI-3 任务与验收勾选完成
- 设计文档决议与实现一致
- 用户报告的四类场景（地址栏、新标签页输入、图标编辑窗、设置输入）问题消失，且输入框高度未变
