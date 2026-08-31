# 助手侧栏 · 登录编辑面板 UX — 设计方案

> 目标：侧栏下半区「登录配置」编辑体验对齐表单备忘：选择器与填入值一一对应、可增删自定义字段；详情区高度可拖拽并记忆；修复「改帐密点保存无效」。  
> 状态：**方案定稿，待实现**  
> 前置：助手侧栏 SB-0～SB-3 已落地（[assist-sidebar-design.md](assist-sidebar-design.md)）  
> 关联：[assist-sidebar-recipe-editor-ux-development-plan.md](assist-sidebar-recipe-editor-ux-development-plan.md) · [auto-login-design.md](auto-login-design.md) · [site-form-memo-design.md](site-form-memo-design.md)

---

## 0. 一句话结论

| 需求 | 结论 |
|------|------|
| 详情区上缘拖高 + 记忆 | **可行**。仿左缘宽度把手，加水平分隔条；`AssistSidebarSettings` 持久化高度 |
| 选择器与值并排 + 自定义字段 | **可行**。UI 重排内建三项；模型增 `extraFields`（对齐 `FormMemoField`）；`LoginRunner` 执行时顺带填入 |
| 侧栏保存帐密失败 | **可修**。根因是 `upsertRecipe` 同步通知 → `reloadList` → `loadRecipe` **在写钥匙串之前**用旧凭证冲掉输入框 |

**产品路径**：先修保存（P0）→ 详情高度拖拽（P1）→ 字段并排 + 自定义字段数据/执行（P2）。

---

## 1. 现状与问题

### 1.1 布局（现状）

```text
┌ 列表 ──────────────────────────┐
│ … 登录项 …                     │
├────────────────────────────────┤  ← 固定高度 380（配方）/ 340（备忘）
│ 名称 / 主机 / 路径 / 模式        │
│ 用户名                         │  ← 值与选择器分离，难对应
│ 密码                           │
│ 手机号                         │
│ 用户选择器 [点选]               │
│ 密码选择器 [点选]               │
│ … OTP / 发码 / 提交 …           │
│ [保存] [删除]                   │
└────────────────────────────────┘
```

- 详情高度写死在 `AssistSidebarController`（`detailHeightConstraint.constant = 380/340/0`）。
- 上缘**不可**拖；仅有侧栏左缘改宽度。

### 1.2 保存失败（根因）

`AssistSidebarRecipeEditor saveClicked:` 顺序：

1. `LoginRecipeStore upsertRecipe:` → **同步** `LoginRecipeStoreDidChangeNotification`
2. `AssistSidebarController storeDidChange:` → `reloadList`
3. 对**已有** Recipe（`editingRecipeID` 非空），`reloadList` **不**走「新建保护」，直接 `showRecipeEditorLoading:` → `loadRecipe:` → 从钥匙串读**旧**凭证写入输入框  
4. 随后 `LoginCredentialStore saveCredentials:` 读到的已是被冲掉的旧/空值 → **表现为「保存无效」**

新建 Recipe 有 `editingRecipeID.length == 0` 保护，故「新建有时正常、编辑帐密必挂」与代码一致。

### 1.3 自定义字段（缺口）

| 能力 | 站点备忘 | 登录 Recipe（现状） |
|------|----------|---------------------|
| 选择器 + 值成对 | ✅ `FormMemoField` | ❌ 值与选择器分行 |
| 任意增删字段 | ✅ 「＋」 | ❌ 仅固定 username/password/phone/otp… |
| 点选 | ✅ | ✅ 仅固定选择器 |
| 执行填入 | ✅ `FormMemoRunner` | 仅固定选择器；`LoginRunner` 不认扩展字段 |

---

## 2. 目标体验

### 2.1 详情高度拖拽（需求 1）

| 项 | 定稿 |
|----|------|
| 把手位置 | 列表底与详情顶之间的**水平分隔条**（约 5～6 pt 命中区） |
| 光标 | `resizeUpDownCursor` |
| 拖动语义 | 上拖 → 详情变高（列表变矮）；下拖 → 详情变矮 |
| 钳制 | 详情高 **180～720**；列表剩余高度 ≥ **56**（仍可看见列表，详情可再拖高） |
| 记忆键 | `MeoLoginAssistSidebarDetailHeight`（`AssistSidebarSettings.detailHeight`） |
| 默认 | **380**（与现 Recipe 打开高度一致） |
| 适用范围 | Recipe / Memo 共用同一高度记忆（同一 `detailContainer`） |
| 关闭详情 | `constant = 0`；**不**改写记忆值（下次再开用上次高度） |

```text
┌ 列表（弹性） ──────────────────┐
│ …                              │
╞═══════ ↕ 拖拽改详情高度 ═══════╡  ← 新把手
│ 编辑面板（记忆高度）            │
└────────────────────────────────┘
```

### 2.2 字段并排 + 自定义字段（需求 2）

#### 内建行（固定语义，不可删）

每一行：**标签 | 选择器 + 点选 | 值输入**。

| 行 | 选择器 | 值控件 | 存哪 |
|----|--------|--------|------|
| 用户名 | `usernameSelector` | `SBTextField` | Keychain `username` |
| 密码 | `passwordSelector` | `SBSecureTextField` | Keychain `password` |
| 手机号 | `phoneSelector` | `SBTextField` | Keychain `phone` |

短信 / 混合模式下，按现有规则启用手机 / OTP / 发码行；OTP、发码、提交仍以「选择器为主」（值来自 OTP 通道或提交动作，不配静态值框）。

示意：

```text
用户名  [ CSS 选择器………… ][点选]  [ 值………… ]
密码    [ CSS 选择器………… ][点选]  [ •••••• ]
手机号  [ CSS 选择器………… ][点选]  [ 值………… ]
验证码  [ CSS 选择器………… ][点选]
发码    [ CSS 选择器………… ][点选]
提交    [ CSS 选择器………… ][点选]   + 回车提交勾选
──────── 自定义字段 ────────
标签A   [ 选择器………… ][点选]  [ 值………… ]  [−]
标签B   [ 选择器………… ][点选]  [ 值………… ]  [−]
                              [＋ 添加字段]
```

窄侧栏（~360）时允许选择器/值换行或压缩：优先保证「标签 + 值」可见，选择器可略窄；极端宽度下整行可竖排为「标签 / 选择器行 / 值行」（实现阶段用 Auto Layout 断点，默认横排）。

#### 自定义字段

| 项 | 定稿 |
|----|------|
| 模型 | `LoginRecipeExtraField`：`fieldID` / `label` / `selector` / `value` / `enabled`（结构对齐 `FormMemoField`） |
| 存储 | Recipe JSON 的 `extraFields` 数组（**值明文进 JSON**，与备忘一致；**不**进 Keychain） |
| UI | 「＋ 添加字段」；每行可改标签、点选、改值、删除 |
| 执行 | `LoginRunner` 在填完内建帐密/手机后、提交前，按序 `setValue` 填入 `enabled && selector` 的字段 |
| 与备忘关系 | **不合并** Recipe/Memo；仅复用字段模型思路与点选管线 |

不做：自定义字段加密、自定义字段参与「默认提交键」、在设置大窗完整镜像（设置窗可只读提示「请在侧栏编辑扩展字段」，或 P2 后期再对齐）。

### 2.3 保存可靠（需求 3）

| 项 | 定稿 |
|----|------|
| 保存顺序 | **先**读齐表单 → **先** `saveCredentials` → **再** `upsertRecipe`（或 upsert 时抑制列表重载编辑区） |
| 列表刷新 | `reloadList` 在「当前编辑器有未落盘脏数据 / 正在保存」时**不得** `loadRecipe` 冲表单 |
| 推荐实现 | （A）保存路径：凭证成功后再 upsert；且 `didSaveRecipe` / `storeDidChange` 用「只刷列表、保留编辑器字段」或保存后显式 `loadRecipe` 一次以确认落盘 |
| 状态文案 | 成功：「已保存。」；钥匙串失败保留错误，**不**误报 Recipe 已更新 |

推荐组合：

1. `saveClicked`：校验 → 组装 recipe/credentials → **先** `saveCredentials` → **再** `upsertRecipe` → 回调。  
2. `reloadList`：增加 `suppressEditorReload` 或「若 `recipeEditor` 可见且 `editingRecipeID` 匹配，只更新列表选中、不调用 `loadRecipe`」。  
3. 保存成功后可选一次 `loadRecipe` 做真源对齐（此时钥匙串已是新值）。

---

## 3. 数据与执行

### 3.1 `LoginRecipe` 扩展

```objc
@interface LoginRecipeExtraField : NSObject <NSCopying>
@property NSString *fieldID;
@property NSString *label;
@property NSString *selector;
@property NSString *value;
@property BOOL enabled;
@end

// LoginRecipe
@property NSArray<LoginRecipeExtraField *> *extraFields; // 默认 @[]
```

JSON 示例片段：

```json
{
  "recipeID": "…",
  "usernameSelector": "input[name=user]",
  "passwordSelector": "input[type=password]",
  "extraFields": [
    { "fieldID": "…", "label": "工号", "selector": "#emp", "value": "E001", "enabled": true }
  ]
}
```

旧文件无 `extraFields` → 读成空数组。内建 username/password/phone **仍**走 Keychain，行为不变。

### 3.2 `LoginRunner`

在现有 password / pre-OTP 填入阶段，内建字段填完后：

```text
for field in recipe.extraFields where enabled && selector.length > 0:
    waitFor(selector) → setValue(value)
```

失败策略：与备忘类似——单字段失败不阻断后续（或可配置；V1：**软失败记日志/继续**，最终仍可提交）。产品默认：**继续填其余字段并提交**（侧栏可 toast「部分自定义字段未找到」若全部失败）。

### 3.3 设置窗

V1 **不强制**改 `BrowserLoginAssistSettingsWindowController` 的 Recipe 表单。侧栏为扩展字段主编辑面；设置窗保存不得抹掉 `extraFields`（编解码走同一 `LoginRecipe` 模型即可）。

---

## 4. 架构改动面

| 模块 | 改动 |
|------|------|
| `AssistSidebarSettings` | `detailHeight` + 钳制 |
| `AssistSidebarController` | 水平分隔把手；详情高度应用/记忆；`reloadList` 不冲脏编辑器；打开详情用记忆高度 |
| `AssistSidebarRecipeEditor` | 并排行 UI；自定义字段列表；保存顺序修复；点选目标含 `extra:<fieldID>` |
| `LoginRecipe` / Store JSON | `LoginRecipeExtraField` + 编解码 |
| `LoginCredentialStore` | **原则上不改**（帐密仍 Keychain）；确认异步读与保存顺序无回归 |
| `LoginRunner` | 填入 `extraFields` |
| `AssistSidebarMemoEditor` | 仅共用详情高度；布局可不动 |
| 设置窗 Recipe 编辑 | 编解码透传 `extraFields`；UI 可后续再做 |

---

## 5. 不做

- 详情区与列表比例用「百分比」记忆（用绝对 pt 即可）  
- 自定义字段进 Keychain / 云同步专用通道  
- Recipe 与 Memo 合并成一种文档  
- 拖拽排序自定义字段（可列后续；V1 用上移下移可选，默认仅删加）  
- 为高度拖拽做撤销栈  

---

## 6. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 窄栏并排拥挤 | 选择器压缩优先；必要时断点改两行 |
| `extraFields` 含敏感值进 JSON | 文档标明；敏感项继续用内建密码行 |
| 保存顺序调整后通知仍冲表单 | `reloadList` 显式跳过编辑器重载 |
| Runner 填扩展字段拖慢登录 | 字段少；`waitFor` 复用现有超时 |

---

## 7. 验收标准（产品）

1. 编辑已有登录项：改用户名/密码 → 保存 → 再选中该项仍显示新值；一键登录用新帐密。  
2. 拖动详情上缘改高度 → 关侧栏再开、再选登录项 → 高度保持。  
3. 用户名/密码/手机：选择器与值同一视觉行，点选仍可用。  
4. 「＋」添加自定义字段 → 点选 + 填值 → 保存 → 执行登录时该字段被填入。  
5. Memo 详情打开时共用同一高度记忆；关闭详情高度归 0，记忆值不变。

---

## 8. 文档关系

| 文档 | 关系 |
|------|------|
| `assist-sidebar-design.md` | 侧栏总案；本文件细化「详情编辑」增量 |
| `assist-sidebar-development-plan.md` | SB-0～3 已完成；本增量见配套开发计划 |
| `auto-login-design.md` | Recipe / Runner 真源；`extraFields` 为扩展 |

---

## 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-08-31 | 初稿：高度拖拽、字段并排+自定义、保存竞态根因与修复策略 |
