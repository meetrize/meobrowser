# 登录助手 / 站点备忘 — 管理侧栏设计方案

> 目标：在浏览器右侧侧栏集中展示**当前页匹配**的登录 Recipe 与站点 Memo，并支持在侧栏内完成增删改查与一键执行；减少反复打开「登录助手与互联」设置窗的摩擦。  
> 状态：**SB-0～SB-3 已实现**（列表 + Memo/Recipe CRUD + 互斥协调 · 2026-07-27）；**登录编辑面板 UX（RE-0～RE-4）已落地**——保存竞态修复、详情高度拖拽记忆、字段并排、自定义字段 + Runner 填入；见 [assist-sidebar-recipe-editor-ux-design.md](assist-sidebar-recipe-editor-ux-design.md) / [assist-sidebar-recipe-editor-ux-development-plan.md](assist-sidebar-recipe-editor-ux-development-plan.md)  
> 前置：登录助手 V1 + 站点备忘 P1 已落地；通知收件箱侧栏壳已落地（[companion-notification-inbox-sidebar-design.md](companion-notification-inbox-sidebar-design.md)）  
> 关联：[assist-sidebar-development-plan.md](assist-sidebar-development-plan.md) · [assist-sidebar-recipe-editor-ux-design.md](assist-sidebar-recipe-editor-ux-design.md) · [assist-sidebar-recipe-editor-ux-development-plan.md](assist-sidebar-recipe-editor-ux-development-plan.md) · [auto-login-design.md](auto-login-design.md) · [site-form-memo-design.md](site-form-memo-design.md) · [site-form-memo-development-plan.md](site-form-memo-development-plan.md) · [companion-link-toolbar-mac-design.md](companion-link-toolbar-mac-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md)

---

## 0. 一句话结论

| 能力 | 结论 |
|------|------|
| 右侧侧栏展示匹配 Recipe / Memo | **可行**。复用通知侧栏的 dock 模式（挤压 WebView） |
| 侧栏内 CRUD | **可行**。数据 API 已齐；窄栏编辑需压缩 UI，密码仍走 Keychain |
| 与通知侧栏并存 | **互斥开关**（同一 trailing 槽）；远期可抽共享壳 |
| 新工具栏图标 | **不新增**（与 FormMemo P1 一致）；从钥匙菜单 / 文件菜单 / 快捷键打开 |
| 设置窗是否废弃 | **不废弃**。侧栏 = 当前站快捷管理；设置窗 = 互联 / 全局偏好 / 高级 |

**产品路径**：先做「匹配列表 + 执行 + Memo 完整 CRUD」；Recipe 凭证编辑跟进；再视需要抽通用侧栏 Host。

---

## 1. 方案定位

### 1.1 产品一句话

**助手侧栏**：当前网址相关的登录配置与表单备忘「看得见、管得了、点一下就填」——列表在侧栏，网页仍在左侧。

### 1.2 与现有能力的关系

| 能力 | 现状 | 本方案 |
|------|------|--------|
| 钥匙按钮 / ⌘⇧L / ⌘⇧M | ✅ 一键执行 | **保留**；侧栏是管理与多选上下文 |
| 助手弹出菜单 | ✅ 执行 +「管理…」 | 「管理…」**优先打开侧栏**（可保留「高级设置…」） |
| 设置窗分段（登录 / 备忘 / 互联） | ✅ 完整 CRUD | **保留**互联与全局偏好；列表编辑可与侧栏共用 Store |
| 通知收件箱侧栏 | ✅ 唯一 trailing 侧栏 | **互斥**：开助手侧栏则关通知侧栏，反之亦然 |
| `LoginRecipeStore` / `FormMemoStore` | ✅ | **唯一数据源**；侧栏只消费通知，不另存 |
| `LoginFormDetector` | ✅ | **不改**；侧栏不依赖登录表单检测 |

### 1.3 要解决的痛点

| 场景 | 痛点 | 侧栏价值 |
|------|------|----------|
| 同一站多套 Memo / 多账号 Recipe | 菜单项多、不知当前匹配哪几条 | 列表一眼看到匹配项与默认标记 |
| 微调备忘字段 / 改选择器 | 每次进设置窗、找分段、再回来 | 侧栏内就地编辑 + 点选 |
| 新站点首次配置 | 入口分散（登录助手… / 站点备忘…） | 「为当前页新建」预填 host/path |
| 对比「当前页」与「全库」 | 设置窗列表是全库，缺上下文 | 默认「匹配当前」；可切「全部」 |

### 1.4 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 右侧 dock 侧栏；展示当前 URL 匹配的 Recipe + Memo | 第二套工具栏钥匙图标 |
| 分段 / 过滤：匹配当前 \| 全部；类型：全部 / 登录 / 备忘 | 与通知收件箱同时打开两个侧栏 |
| 行内：执行（登录/填入）、设默认、删除；详情区编辑 | 在侧栏做 Companion 配对 / 短信通道 |
| Memo 字段 CRUD + 点选选择器（复用 Picker） | 进页自动灌入；放宽登录 Detector |
| Recipe 元数据 + 帐密编辑（Keychain） | 把密码明文写进 Memo JSON |
| Esc 关闭；宽度记忆；窄窗自动收起 | 云同步配置库 |

### 1.5 设计原则

1. **上下文优先**：默认只看「匹配当前页」；全库是次要模式。  
2. **执行与管理同屏**：选中一行即可填入/登录，不必先关侧栏。  
3. **人在回路**：不自动填、不自动登录（侧栏打开 ≠ 执行）。  
4. **与设置窗分工**：侧栏管「这个站的条目」；设置窗管「互联与全局」。  
5. **单槽侧栏**：与通知侧栏互斥，避免 chrome 挤爆。  
6. **SBKit**：侧栏内输入一律 `SBTextField` / `SBSecureTextField` / `SBTextView`。

---

## 2. 用户体验

### 2.1 如何打开 / 关闭

| 入口 | 行为 |
|------|------|
| 钥匙菜单 →「打开助手侧栏」 | Toggle；已开则聚焦侧栏 |
| 钥匙菜单 →「管理登录配置…」/「管理站点备忘…」 | 打开侧栏并选中对应分段 / 选中项（若有） |
| 文件 →「助手侧栏」 | Toggle（建议快捷键 **⌘⇧A**，Assist；冲突再改） |
| 文件 →「登录助手…」/「站点备忘…」 | **改为打开侧栏**对应模式；侧栏底部保留「高级设置…」进原设置窗 |
| Esc | 关闭侧栏（输入框聚焦时不抢） |
| 侧栏关闭按钮 | 关闭 |
| 窗口宽 &lt; 720 | 与通知侧栏一致，自动关闭 |

**不新增** ActionGroup 图标（避免与钥匙、铃铛抢注意力）。若日后证明入口太藏，再评估「仅有匹配时显示次要按钮」。

### 2.2 布局（侧栏内部）

宽度建议对齐通知侧栏：**320～560**，默认 **360**，独立记忆键（如 `MeoLoginAssistSidebarWidth`）。

```text
┌ 助手 ───────────────────── ✕ ┐
│ [匹配当前] [全部]              │  ← 范围
│ [全部] [登录] [备忘]           │  ← 类型过滤
│ 🔍 搜索标题 / host             │
├──────────────────────────────┤
│ ▼ 登录                         │
│   ★ Grafana · ops.ex.com       │  ← 默认
│     一键登录 · 仅填入           │
│ ▼ 站点备忘                     │
│   ★ 报障常用 · /tickets/new    │
│     填入 · 3 字段               │
│   反馈模板 · /feedback         │
├──────────────────────────────┤
│ 【详情 / 编辑】                 │
│  标题 / 主机 / 路径前缀 …       │
│  （登录：帐密；备忘：字段表）    │
│  [保存] [设为默认] [删除]       │
├──────────────────────────────┤
│ [＋ 新建登录] [＋ 新建备忘]     │
│ [高级设置…]                     │
└──────────────────────────────┘
```

空态（匹配当前且无项）：

> 当前页还没有登录配置或站点备忘。  
> [为当前页新建登录] [为当前页新建备忘]

风险域页：列表可仍显示已有配置，但执行按钮禁用并提示「本站已抑制脚本填充」（与 Runner 一致）。

### 2.3 列表行与操作

| 行类型 | 展示 | 主操作 | 次要 |
|--------|------|--------|------|
| Recipe | 标题、host、pathPrefix、默认★、模式标签 | 一键登录 | 仅填入、编辑、删除 |
| Memo | 标题、host、pathPrefix、默认★、字段数 | 填入备忘 | 编辑、删除 |

- 单击行：选中并加载详情编辑区（不立刻执行）。  
- 双击行 **或** 行内主按钮：执行（登录 / 填入）。  
- 多匹配时 ★ 表示默认；「设为默认」写回 Store（同 host 互斥，规则已有）。

### 2.4 详情编辑（CRUD）

#### 站点备忘（侧栏完整支持）

- 元数据：标题、host、pathPrefix、默认、waitTimeout（可折叠高级）。  
- 字段表：标签 / 选择器 / 启用；选中行编辑 value（`SBTextView`）。  
- 添加 / 删除 / 上移下移字段；「点选」走 `LoginElementPicker`（拾取时侧栏可 `orderBack`，与设置窗一致）。  
- 保存 → `FormMemoStore upsertMemo:`。

#### 登录配置（侧栏支持核心编辑）

- 元数据：标题、host、pathPrefix、模式、默认、自动登录、提交方式、选择器。  
- 凭证：用户名 / 密码 / 手机 → `LoginCredentialStore`（Keychain）。  
- OTP 相关选择器可编辑；**不**在侧栏做 Companion 配对。  
- 保存 → Recipe upsert + credentials upsert。

复杂互联、内联开关、保存询问等仍在「高级设置…」。

### 2.5 与钥匙单击行为的关系

| 现状 | 侧栏落地后 |
|------|------------|
| 仅 Recipe → 一键登录 | **不变** |
| 仅 Memo → 填入 | **不变** |
| 两者都有 → 弹菜单 | **不变**；菜单增加「打开助手侧栏」 |
| 侧栏已打开时再点钥匙 | 仍按上表执行；不强制关侧栏 |

侧栏是**并行管理面**，不劫持一键手势。

---

## 3. 架构

### 3.1 窗口槽位策略（关键）

当前 `contentRowStack` 只有一个 trailing 子视图（通知侧栏）。

| 方案 | 说明 | 结论 |
|------|------|------|
| **A. 互斥替换内容** | 同一 `sidebarHostView`，切换 `content = notification \| assist` | 工程干净，用户同时只需一个管理面 |
| B. 两个子视图叠放 | 两个 controller 都在 stack 里，同时只有一个 width&gt;0 | 可行但重复约束逻辑 |
| C. 允许双开 | 两栏同时挤 WebView | **不做**（窄屏不可用） |

**推荐 A**：抽出轻量 `BrowserTrailingSidebarSlot`（SB-3 已落地）协调互斥；远期可再抽 `BrowserSidebarHost` 单槽换 contentView：

```text
contentRowStack
  ├── contentContainer
  └── sidebarHost（远期）
        ├── widthConstraint / resize / Esc
        └── contentView = NotificationSidebar.view 或 AssistSidebar.view
```

首期在 WC 里通过 `BrowserTrailingSidebarSlot` 互斥；两 view 仍并列于 stack。

### 3.2 模块划分

| 建议文件 | 职责 |
|----------|------|
| `LoginAssist/AssistSidebar/AssistSidebarController.h/.m` | 侧栏 UI、列表、详情、开关动画 |
| `…/AssistSidebarSettings.h/.m` | 宽度等 UserDefaults |
| `LoginAssistController` | 提供 matched 列表、runRecipe/runMemo、打开侧栏 API |
| `BrowserWindowController` | 挂载、toggle、与通知侧栏互斥、窄窗关闭 |
| `BrowserMenus` | 「助手侧栏」菜单项 + 快捷键 |

**不**把 CRUD 再写一套 Store；继续用：

- `LoginRecipeStore` / `LoginCredentialStore`  
- `FormMemoStore` / `FormMemoRunner` / `LoginRunner`  
- `LoginElementPicker`

设置窗与侧栏通过 `*StoreDidChangeNotification` 互相同步。

### 3.3 数据流

```text
Tab URL 变化
  → LoginAssistController updateForURL:
  → matchedRecipes / matchedMemos
  → 若助手侧栏可见：AssistSidebarController reload（匹配模式）

用户在侧栏保存 / 删除
  → Store upsert/delete
  → Notification
  → Controller 刷新匹配 + 钥匙点亮
  → 侧栏列表刷新
```

「全部」模式：直接 `allRecipes` / `allMemos`，搜索过滤 title/host/pathPrefix。

### 3.4 与设置窗的边界

| 功能 | 侧栏 | 设置窗 |
|------|------|--------|
| 当前页匹配列表 | ✅ 主路径 | ❌（全库列表） |
| Memo / Recipe CRUD | ✅ | ✅（可逐步变「高级」） |
| 点选选择器 | ✅ | ✅ |
| 一键登录 / 填入 | ✅ | ❌ |
| Companion / 通知镜像 / 同步 | ❌ | ✅ |
| 内联图标 / 保存询问偏好 | ❌ | ✅ |

迁移策略：菜单「登录助手…」「站点备忘…」→ 打开侧栏；设置窗标题可改为「登录助手与互联（高级）」，侧栏底「高级设置…」进入。

---

## 4. 交互细节与边界

### 4.1 新建预填

「＋ 新建登录 / 新建备忘」：

- host：当前 URL host；`file://` → `file`  
- pathPrefix：可选填当前 path 或文件名（与设置窗「为当前标签页创建」一致）  
- 立即进入详情编辑；未保存前可用临时 ID，保存时 upsert  

### 4.2 删除

二次确认；Recipe 删除同步清 Keychain（现有 Store 行为）；Memo 仅删 JSON。

### 4.3 密码安全

- 侧栏密码框用 `SBSecureTextField`；列表行**永不**展示密码。  
- 日志只打 recipeID / memoID / host / label。  
- Memo 编辑区保留「勿存密码」提示。

### 4.4 多窗口

每窗各自开合与选中态；Store 进程单例；A 窗编辑后 B 窗侧栏经通知刷新。

### 4.5 失败反馈

执行失败沿用现有 toast / 对话框（含「打开编辑」→ 侧栏选中对应项，而不是只开设置窗）。

---

## 5. 可行性与风险

| 项 | 难度 | 说明 |
|----|------|------|
| 侧栏壳 + 互斥 | 低～中 | 可抄通知侧栏宽度 / Esc / 动画 |
| 匹配列表 + 执行 | 低 | API 现成 |
| Memo CRUD 窄栏 UI | 中 | 字段表需紧凑；可复用设置窗逻辑抽取 |
| Recipe + Keychain 编辑 | 中 | 注意模式切换与选择器启用态 |
| 抽 BrowserSidebarHost | 中 | 可二期；首期 WC 内互斥即可 |
| 双开侧栏 | — | 明确不做 |

**风险**：侧栏同时塞列表+完整编辑可能拥挤 → 用「列表为主、详情可折叠 / 或选中后展开下半区」；极复杂编辑仍跳高级设置。

---

## 6. 分阶段交付

### SB-0 — 侧栏壳 + 匹配列表 + 执行（MVP）

- `AssistSidebarController` dock + 宽度记忆 + Esc + 与通知互斥  
- 范围：匹配当前 / 全部；类型过滤；搜索  
- 行：显示 Recipe/Memo；双击或按钮 → `runRecipe` / `runMemo`  
- 入口：钥匙菜单 + 文件菜单 + ⌘⇧A  
- 空态 +「高级设置…」  
- **不做**侧栏内编辑（编辑仍进设置窗，但「管理…」先打开侧栏）

### SB-1 — 侧栏 Memo CRUD

- 详情区编辑 Memo 元数据与字段；点选；保存/删除/设默认/新建  
- 设置窗备忘分段可保留或标为同步入口  

### SB-2 — 侧栏 Recipe CRUD

- 详情区编辑 Recipe + Keychain 凭证 + 选择器  
- 失败「打开编辑」定位到侧栏对应 Recipe  

### SB-3 — 打磨（已完成）

- `BrowserTrailingSidebarSlot` 统一互斥
- 菜单 / tooltip 文案；设置窗「高级」心智
- 失败对话框「打开编辑」→ 侧栏定位
- 验收文档勾选（手工项见 development-plan）

### 明确不做（近期）

- 通知 + 助手双开  
- 新工具栏图标  
- 侧栏内 Companion  
- 自动填充 / 改 Detector  

---

## 7. 验收建议（SB-0～SB-1）

1. 打开有 Memo 的测试页 → 侧栏「匹配当前」可见对应项 → 填入成功。  
2. 同页有 Recipe + Memo → 两类分组都在；执行互不干扰。  
3. 切到无配置页 → 空态；「新建备忘」host 预填正确。  
4. 侧栏改 Memo 字段并保存 → 钥匙菜单与设置窗列表同步。  
5. 打开助手侧栏时通知侧栏关闭；再开通知则助手关闭。  
6. 输入符合 SBKit；密码不出现在列表文案。  

---

## 8. 开放问题（待拍板）

1. **快捷键 ⌘⇧A**：是否占用？备选：仅菜单、或 ⌘⇧\。  
2. **「登录助手…」菜单**：直接开侧栏，还是仍开设置窗、侧栏另列一项？建议：**开侧栏**，高级用侧栏底入口。  
3. **详情区默认展开还是选中后展开**？建议：选中行后下半区展开，节省纵向空间。  
4. **SB-0 是否包含「管理…改开侧栏」**？建议：是，否则侧栏入口过弱。  
5. **是否在钥匙点亮时 tooltip 提示「右键打开侧栏」**？可选，非必须。

---

## 9. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-27 | 初稿：定位、互斥侧栏、匹配列表 + 分阶段 CRUD、与设置窗分工 |
| 0.2 | 2026-07-27 | SB-0 落地：AssistSidebar 列表/执行/入口/互斥 |
| 0.3 | 2026-07-27 | SB-1 落地：侧栏 Memo 编辑器 + 点选 |
| 0.4 | 2026-07-27 | SB-2 落地：侧栏 Recipe 编辑器 + Keychain |

开发计划见 [assist-sidebar-development-plan.md](assist-sidebar-development-plan.md)。
