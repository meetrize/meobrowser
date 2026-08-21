# 单行输入框文字垂直边距 — 设计方案

> 相关实现：`SBKit/SBTextField`、`SBSecureTextField`、`SBTextInputConfiguration`  
> 开发计划：[text-field-vertical-insets-development-plan.md](text-field-vertical-insets-development-plan.md)  
> 输入架构总览：[text-input.md](text-input.md)

---

## 1. 问题陈述

应用内多处 **单行输入框** 出现同一视觉缺陷：

- 文字相对输入框 **上边缘偏下**（上边距过大）
- 在固定高度（约 22–28 pt）下，字形 **下半部分被裁切**，显示不完整

用户明确指出的场景：

| 场景 | 控件 | 典型高度 |
|------|------|----------|
| 地址栏 | `SBTextField` | 随工具栏行高（约 28） |
| 新标签页 · 文件夹改名 | `SBTextField` | 26 |
| 图标编辑窗口（快捷方式 sheet） | `SBTextField` ×4 | **22**（最易裁切） |
| 设置界面 | `SBTextField` / `SBSecureTextField` | 系统默认或 22 |

同类问题还可能出现在：页内查找、历史/通知侧栏搜索、登录助手编辑器、HTTP 认证弹窗等所有矮高度 `SBTextField`。

**硬约束（来自需求）：**

1. 缩小文字显示的上边距，消除下方被隐藏
2. **不改变输入框本身的高度**（不改 Auto Layout 的 `heightAnchor` / 行高）
3. 覆盖本应用中 **所有** 可编辑单行输入框，而非逐页打补丁

---

## 2. 根因分析

### 2.1 AppKit 默认行为

`SBTextInputConfiguration` 将单行框配置为：

- `bezelStyle = NSTextFieldSquareBezel`
- `font = system 13pt`

系统 `NSTextFieldCell` 的 `drawingRectForBounds:` / `titleRectForBounds:` 会按 bezel 预留 **较大的垂直 inset**。在控件高度接近「字高 + 默认 inset」时：

```
┌─────────────────────────┐  ← 控件外框（高度固定，如 22）
│░░░░░░░░ 过大上边距 ░░░░░│
│     文字基线偏下…       │
│████ 下行被裁切 ████████│  ← 被 clip
└─────────────────────────┘
```

未聚焦时画在 cell 的 title rect；聚焦时 field editor 使用同一套 drawing rect。上下不对称或总可用高度不足时，用户感知为「字太靠下 + 底边被切」。

### 2.2 项目内已有能力（未默认开启）

`SBTextField` 已实现自定义 `SBStandardTextFieldCell`，并通过：

```objc
@property (nonatomic) BOOL usesCompactVerticalTextInsets; // 默认 NO
```

在开启时用紧凑 inset 覆盖系统矩形：

| 方向 | 紧凑值（现状） | 说明 |
|------|----------------|------|
| 水平 | 3 pt | 保留少量 bezel 边距 |
| 垂直 | 2 pt | 注释写明：避免 24pt 高框裁切下行 |

同时覆盖：`drawingRectForBounds:`、`titleRectForBounds:`、`editWithFrame:`、`selectWithFrame:`，以及 `syncFieldEditorFrameWithContentInsets`（编辑中同步 field editor）。

**当前仅少数调用点显式打开：**

- 页内查找 `BrowserFindBarView`
- 历史侧栏搜索
- 通知侧栏搜索
- 手机聊天输入

**未打开（与用户报告一致）：** 地址栏、快捷方式编辑 sheet、文件夹标题、设置窗、登录助手大量 `makeField`、标签总览搜索等。

### 2.3 `SBSecureTextField` 缺口

密码框仍走系统 `NSSecureTextFieldCell`，**没有** compact 垂直 inset 能力。设置页、HTTP 认证、登录助手密码框在矮高度下会复现同一问题。

### 2.4 非目标

| 排除项 | 原因 |
|--------|------|
| 只读 `NSTextField` label（`labelWithString:` / `editable = NO`） | 非输入框；裁切机制不同 |
| `SBTextView` 多行 | 使用 `textContainerInset`，本需求聚焦单行 bezel 框 |
| 加高控件 / 改字体 | 违反「不改高度」；字体统一 13pt 保持不变 |
| 业务层逐个 `usesCompact… = YES` | 易漏、与「所有输入框」目标冲突 |

---

## 3. 目标与成功标准

### 3.1 目标

在 **不改变任何输入框约束高度** 的前提下，让所有 `SBTextField` / `SBSecureTextField` 的文字在垂直方向：

- 上边距明显小于系统默认 bezel inset
- 上下大致居中或略偏上，**下行（含 g/y/p 等 descender）不被裁切**
- 聚焦 / 未聚焦 / 全选 / 有 leading·trailing content inset（地址栏）行为一致

### 3.2 成功标准

- [ ] 地址栏：未编辑与编辑中，URL 文字完整可见
- [ ] 新标签页文件夹标题输入、快捷方式编辑 sheet 四框：22–26 高度下无底切
- [ ] 设置窗 URL / 邮箱 / 密码：同上
- [ ] 其余 `standardField` 创建的单行框默认受益，无需业务再设开关
- [ ] 地址栏左右 inset（收藏/翻译按钮）、查找框 trailing inset **不受影响**
- [ ] 输入框 `heightAnchor` / 视觉外框高度与改前一致
- [ ] 深色 / 浅色、Retina 下抽检通过

---

## 4. 方案选型

### 方案 A — 默认开启紧凑垂直 inset（推荐）

在 `SBTextInputConfiguration configureSingleLineTextField:`（或 `+standardField`）中：

```objc
if ([textField isKindOfClass:[SBTextField class]]) {
    ((SBTextField *)textField).usesCompactVerticalTextInsets = YES;
}
```

并对 `SBSecureTextField` 做对称实现（自定义 cell + 同一属性或配置内默认 YES）。

| 优点 | 缺点 |
|------|------|
| 一次修复全应用；符合 SBKit「配置集中」原则 | 需确认是否存在「刻意要大 inset」的例外（当前无） |
| 不改各业务高度约束 | 默认行为变更需一轮全量目视验收 |
| 已有实现可复用，风险低 | Secure 需补齐 cell |

### 方案 B — 业务点逐个打开

在地址栏、sheet、设置等处分别 `usesCompactVerticalTextInsets = YES`。

| 优点 | 缺点 |
|------|------|
| 变更面表面小 | 必漏；与需求「所有输入框」不符；密码框仍无能力 |

### 方案 C — 改 bezel / controlSize / 字体

例如 `RoundedBezel`、缩小字号、加高控件。

| 优点 | 缺点 |
|------|------|
| 可能部分缓解 | 改高度或外观；与全局风格不一致；不推荐 |

**结论：采用方案 A。** 方案 B 仅作回归清单参考，不作为交付路径。

---

## 5. 详细设计

### 5.1 默认策略

| 项 | 定稿 |
|----|------|
| `SBTextField.usesCompactVerticalTextInsets` | **默认 YES**（`configureSingleLineTextField:` 设置） |
| 属性保留 | 仍可设为 NO，供极端自定义 UI（当前无调用方需要） |
| 垂直 inset 常量 | 保持 **2 pt** 起步；若 22pt + 13pt 仍裁切，再微调为 **1 pt**（常量集中，禁止魔法数散落） |
| 水平 inset | 保持 **3 pt**（与 leading/trailing content inset 叠加逻辑不变） |
| 控件高度 | **禁止**为修字而改任何 `heightAnchor` |

建议将 3 / 2 提为 `SBStandardTextFieldCell` 内命名常量（如 `kSBTextFieldCompactHorizontalInset` / `Vertical`），便于 Phase 验收时只改一处。

### 5.2 `SBSecureTextField` 对齐

1. 增加与 `SBTextField` 同语义的 `usesCompactVerticalTextInsets`（默认经 configuration 设为 YES）
2. 自定义 `SBStandardSecureTextFieldCell`（或共享 helper 计算 text area rect）
3. 同样覆盖 drawing / title / edit / select；密码框一般无 leading/trailing content inset，可先不做 inset 属性，保持实现更薄

共享建议：把「给定 bounds + 是否 compact → drawing rect」抽成 C 函数或小工具类，避免 Text / Secure 两套 inset 数值漂移。

### 5.3 调用点清理（可选但推荐）

以下已显式 `= YES` 的语句在默认开启后变为冗余，可删除以减噪（行为不变）：

- `BrowserFindBarView`
- `BrowserHistorySidebarController`
- `PhoneNotificationSidebarController`
- `PhoneChatWindowController`

**不要**在业务层再批量添加 `= YES`。

### 5.4 文档与规范

更新：

- `docs/sbkit/text-input.md`：说明默认紧凑垂直 inset 与例外属性
- `.cursor/rules/appkit-text-input.mdc`：checklist 增加「勿为修裁切而加高输入框；垂直边距走 SBKit」

### 5.5 风险与缓解

| 风险 | 缓解 |
|------|------|
| 个别「高」输入框文字略显贴边 | 2pt 已留边；目视后可仅调常量 |
| field editor 与未聚焦绘制不一致 | 已有 sync；验收时点进地址栏、sheet 各框 |
| Secure cell 行为差异 | 与 Text 共用 rect 计算；设置页密码框重点测 |
| 未来误关默认 | 文档写明：新框用 `standardField`，不要复制裸 `NSTextField` |

---

## 6. 影响面清单（验收用）

凡 `[SBTextField standardField]` / `[SBSecureTextField standardField]` / `makeField` 创建的可编辑单行框均在范围内，重点：

1. **地址栏** — `BrowserWindowController` + `BrowserAddressBarRowView`
2. **新标签页** — `BrowserShortcutFolderOverlay` 标题；`BrowserShortcutEditorSheet` 名称/URL/图标/字母
3. **设置** — `BrowserSettingsWindowController` 服务器 URL/邮箱/密码；登录助手设置窗全部字段
4. **侧栏 / 其它** — 查找栏、历史搜索、通知搜索、Assist 搜索与编辑器、标签总览搜索、HTTP Auth、配对/策略面板等

只读 label、按钮 title **不在**本方案修改范围。

---

## 7. 非功能要求

- 不引入新依赖；仅 Objective-C / AppKit
- `make browser` 通过
- 不改窗口布局 metrics、不改地址栏行高
- 提交信息使用简体中文（仓库规则）

---

## 8. 决议摘要

| 项 | 决议 |
|----|------|
| 根因 | Square bezel 默认垂直 inset 过大 + 矮高度裁切 |
| 手段 | SBKit 默认 `usesCompactVerticalTextInsets = YES` |
| Secure | 补齐同等 cell / 配置 |
| 高度 | 一律不动 |
| 业务补丁 | 不采用；仅清理冗余赋值 |
| 数值 | 水平 3 / 垂直 2，不足再收紧垂直为 1 |
