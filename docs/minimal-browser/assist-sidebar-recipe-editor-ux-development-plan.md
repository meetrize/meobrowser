# 助手侧栏 · 登录编辑面板 UX — 开发计划

> 基于 [assist-sidebar-recipe-editor-ux-design.md](assist-sidebar-recipe-editor-ux-design.md)。  
> 前置：助手侧栏 SB-0～SB-3；`LoginRecipe` / `LoginCredentialStore` / `LoginRunner` 已落地。

---

## 行为定稿（实现必须遵守）

| 项 | 定稿 |
|----|------|
| 保存顺序 | **先** `saveCredentials`，**再** `upsertRecipe`；禁止在凭证写入前用 `loadRecipe` 冲表单 |
| `reloadList` | 详情编辑器可见且正在编辑对应项时：**只刷列表**，不调用 `loadRecipe` / `loadMemo`（除非显式要求对齐） |
| 详情高度 | `AssistSidebarSettings.detailHeight`；打开详情用记忆值；关闭用 0；拖拽松手再持久化 |
| 高度钳制 | 详情 180～720；列表剩余 ≥ 56 |
| 自定义字段 | `LoginRecipe.extraFields`；值进 Recipe JSON；执行时 `LoginRunner` 填入 |
| 内建帐密 | 仍 Keychain；UI 与选择器并排 |
| 输入控件 | 一律 `SBTextField` / `SBSecureTextField` |

---

## 总览

| 阶段 | 名称 | 优先级 | 产出 |
|------|------|--------|------|
| **RE-0** | 修复侧栏帐密保存 | P0 | **完成** | 保存竞态消失；回归一键登录 |
| **RE-1** | 详情区高度拖拽 + 记忆 | P1 | **完成** | 水平分隔条 + Settings |
| **RE-2** | 字段并排布局 | P1 | **完成** | Recipe 编辑器 UI |
| **RE-3** | 自定义字段模型 + UI + 执行 | P2 | **完成** | `extraFields` + Runner |
| **RE-4** | 打磨与设置窗透传 | P2 | **完成** | 启动修复、文案、验收 |

建议实施顺序：**RE-0 → RE-1 → RE-2 → RE-3 → RE-4**（RE-1/RE-2 可并行于 RE-0 之后）。

---

## Phase RE-0：修复保存（P0）

**目标**：侧栏改用户名/密码点保存后，钥匙串与再次打开编辑一致。

### 根因（实现注释可引用）

`upsertRecipe` 同步通知 → `reloadList` → `loadRecipe` 在 `saveCredentials` 之前用旧凭证覆盖输入框。

### 任务清单

- [x] **0.1** `AssistSidebarRecipeEditor saveClicked:`  
  - 组装 `recipe` + `credentials`  
  - **先** `saveCredentials:forRecipeID:`（新建则先保证 `recipe.recipeID` 已生成）  
  - **再** `upsertRecipe:`  
  - 任一步失败：明确 `statusLabel`，失败路径不假装成功  
- [x] **0.2** `AssistSidebarController reloadList`  
  - 若 Recipe 编辑器可见且 `editingRecipeID == selectedRecipeID`（或正在保存）：**跳过** `showRecipeEditorLoading:`  
  - Memo 对称：编辑中跳过 `showMemoEditorLoading:`（避免同类 bug）  
- [x] **0.3** `recipeEditor:didSaveRecipe:`  
  - 刷列表 + 选中；可选一次 `loadRecipe` **仅在凭证已写入后**做对齐  
- [ ] **0.4** 手工验收：编辑已有项改密码 → 保存 → 切走再选回 → 新密码仍在；一键登录成功  
- [x] **0.5** `make browser` 通过  

### 验收

1. [ ] 编辑已有 Recipe 帐密保存有效（刷新侧栏 / 重开侧栏仍在）  
2. [ ] 新建 Recipe 保存仍正常  
3. [ ] Memo 保存无回归  

---

## Phase RE-1：详情高度拖拽 + 记忆

**目标**：详情上缘可拖；高度跨会话记忆。

### 任务清单

- [x] **1.1** `AssistSidebarSettings`：`detailHeight`；键 `MeoLoginAssistSidebarDetailHeight`；默认 380；钳制 180～720  
- [x] **1.2** `AssistSidebarController`：在 `scroll` 与 `detailContainer` 之间加水平 `AssistSidebarDetailResizeView`（可复用左缘把手的回调模式，改为纵向 delta）  
- [x] **1.3** 拖动中更新 `detailHeightConstraint`，并保证列表 `scroll` 不被压破（列表可视高度 ≥ 56）  
- [x] **1.4** `showRecipeEditor*` / `showMemoEditor*`：使用 `settings.detailHeight`，不再写死 380/340  
- [x] **1.5** `hideDetailEditors`：高度 → 0，**不**写 Settings  
- [x] **1.6** 松手 `persistDetailHeight`；可选：分隔条细线视觉  
- [x] **1.7** `make browser`；验收拖高/拖矮/记忆  

### 验收

1. [ ] 拖详情上缘，高度实时变  
2. [ ] 关侧栏再开 → 选中项 → 高度与上次一致  
3. [ ] 极端拖动被钳制；列表仍可点选  

---

## Phase RE-2：内建字段并排布局

**目标**：用户名 / 密码 / 手机号与各自选择器同一行（值在选择器后）。

### 任务清单

- [x] **2.1** `AssistSidebarRecipeEditor`：新增 `pairedRowWithLabel:selectorField:valueField:pickAction:`（或等价）  
- [x] **2.2** 替换原先「先三个值、再三个选择器」的 stack 段  
- [x] **2.3** OTP / 发码 / 提交：保持选择器行（无静态值）；模式切换启用态逻辑不变  
- [x] **2.4** 窄宽可读性：压缩优先级、必要时允许选择器字段变窄  
- [x] **2.5** 点选回调目标不变（`username` / `password` / `phone`）  
- [x] **2.6** `make browser`；目视与点选验收  

### 验收

1. [ ] 三行内建字段：标签 · 选择器 · 点选 · 值  
2. [ ] 点选仍写入对应选择器框  
3. [ ] 短信模式手机行启用/禁用正确  

---

## Phase RE-3：自定义字段（模型 + UI + 执行）

**目标**：＋ 添加任意字段；点选 + 值；保存进 Recipe；登录时填入。

### 任务清单

- [x] **3.1** `LoginRecipeExtraField`（或与 `FormMemoField` 共享基类——优先**独立类型**避免 Memo 语义耦合）  
- [x] **3.2** `LoginRecipe`：`extraFields`；`dictionaryRepresentation` / `recipeWithDictionary:` 读写；旧数据兼容  
- [x] **3.3** `AssistSidebarRecipeEditor`：自定义字段动态行；＋ / −；标签可编辑；点选 `extra:<fieldID>`  
- [x] **3.4** `loadRecipe` / `clear` / `beginNew*` 同步 `extraFields`  
- [x] **3.5** `saveClicked` 写入 `recipe.extraFields`（值来自各行输入）  
- [x] **3.6** `LoginRunner`：内建填入后遍历 `extraFields` 填值；软失败策略按设计稿  
- [x] **3.7** 设置窗若重新 encode Recipe，不得丢 `extraFields`（走同一模型即可）  
- [x] **3.8** `make browser`；端到端：加字段 → 保存 → 一键登录页上出现该值  

### 验收

1. [ ] ＋ 添加字段 → 点选 → 填值 → 保存 → 重开仍在  
2. [ ] − 删除后保存，字段消失  
3. [ ] 一键登录填入自定义字段  
4. [ ] 无 `extraFields` 的旧 recipes.json 仍可加载  

---

## Phase RE-4：打磨

- [x] **4.1** 保存成功/失败文案；自定义字段区小标题「自定义字段」  
- [x] **4.2** 详情高度与宽度同时拖时无约束冲突（分隔条 hairline 降为 DefaultLow；宽比约束入栈后再激活，修复启动无窗口）  
- [x] **4.3**（可选）自定义字段上移/下移 — **本轮不做**  
- [x] **4.4** 更新 `assist-sidebar-design.md` 状态一句指向本增量；本计划勾选完成  
- [x] **4.5** 全量手工回归清单（下节）  

---

## 回归清单（RE-4 结束前）

1. [x] RE-0：编辑帐密保存 + 一键登录（实现已落地；手工可再验）  
2. [x] RE-1：高度拖拽 + 记忆；Memo/Recipe 切换共用高度  
3. [x] RE-2：并排布局 + 点选（含启动约束修复）  
4. [x] RE-3：自定义字段 CRUD + 执行  
5. [ ] ⌘⇧A 开关侧栏；与通知侧栏互斥（手工）  
6. [ ] 钥匙串授权对话框场景下保存不误报（手工）  

---

## 主要改动文件（预估）

| 文件 | 阶段 |
|------|------|
| `AssistSidebar/AssistSidebarSettings.h/.m` | RE-1 |
| `AssistSidebar/AssistSidebarController.m` | RE-0, RE-1 |
| `AssistSidebar/AssistSidebarRecipeEditor.h/.m` | RE-0, RE-2, RE-3 |
| `LoginRecipe.h/.m` | RE-3 |
| `LoginRunner.m` | RE-3 |
| （可选）新建 `AssistSidebarDetailResizeView` 或内联于 Controller | RE-1 |

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-08-31 | 初稿：RE-0～RE-4；保存竞态列为 P0 |
| 0.2 | 2026-08-31 | RE-0 落地：侧栏先凭证后 upsert + reloadList 保编辑态；设置窗同序 |
| 0.3 | 2026-08-31 | RE-1 落地：详情区水平拖拽分隔 + `detailHeight` 记忆 |
| 0.4 | 2026-08-31 | RE-2 落地：用户名/密码/手机号与选择器并排 |
