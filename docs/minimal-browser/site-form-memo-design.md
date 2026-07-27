# 站点表单备忘（多字段填入）— 设计方案

> 目标：为常用工作站点的**普通表单**提供按 URL 关联的常用文本一键填入；保存的是 **Site Memo（字段列表）**，与登录 Recipe 平行，不演化成通用 Autofill / 密码管理器。  
> 状态：**P1 已实现**（多字段填入 · 2026-07-27）；**P2-0 内联保存已实现**（聚焦＋备忘 · 2026-07-27）  
> 前置：登录助手 V1 已落地（[auto-login-design.md](auto-login-design.md) · 点选拾取 `LoginElementPicker` · 填充引擎 `LoginRunner`）  
> 范围：本文件定稿 **P1**；P0 焦点粘贴仅作可选降级路径，不单独交付。后续可选 P2 见 §7。  
> 关联：[site-form-memo-development-plan.md](site-form-memo-development-plan.md) · [assist-sidebar-design.md](assist-sidebar-design.md) · [login-form-inline-design.md](login-form-inline-design.md) · [anti-bot-session-design.md](anti-bot-session-design.md) · [professional-features-roadmap.md](professional-features-roadmap.md) · [design.md](design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**站点表单备忘（Site Form Memo）**：对「你自己配置过的网址」把一组常用文本按 CSS 选择器写入页面字段；本质是 **网址 ↔ 字段备忘**，不是猜表单、也不是存密码。

与登录助手的分工：

| | 登录助手（已有） | 站点表单备忘（本方案） |
|--|------------------|------------------------|
| 解决什么 | 怎么登录 | 这个网址的表单常用什么文本 |
| 数据 | Recipe + Keychain 帐密 | Memo + 明文字段值（本地 JSON） |
| 触发 | 有 Recipe / 检测到登录表单 | **有匹配 Memo 即可**（不依赖 password） |
| 提交 | 可填可提交 / OTP | **默认只填不提交** |

### 1.2 要解决的痛点

| 用户场景 | 痛点 | 备忘价值 |
|----------|------|----------|
| 工单 / CRM / 内部后台反复填「姓名、工号、部门、备注」 | 每天复制粘贴或重打 | 一键按字段写入 |
| 非登录多步表单（申请、报障、配置向导） | 登录助手因无 password 不出现 | 按 host/path 单独配置 |
| 同一站不同 path 字段不同（`/apply` vs `/feedback`） | 全局一段文本不够用 | `pathPrefix` 区分多套 Memo |
| 含长备注的 `textarea` | 现有 Runner 偏 `input` | 明确支持 textarea |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 按 host（+ 可选 pathPrefix）配置多字段 `{label, selector, value}` | 启发式扫描全站「任意表单」并自动出入口 |
| 点选拾取选择器 + 手工改 CSS | 猜测 label ↔ 字段映射（P1） |
| 工具栏/菜单「填入站点备忘」；有匹配则点亮 | 静默自动填、进页即灌字段 |
| 明文 Memo 存 Application Support JSON | 把普通备忘塞进 LoginRecipe / Keychain |
| 复用 Picker + 泛化 fill（input/textarea） | 自动提交、OTP、Companion、系统密码互通 |
| 与登录助手共用钥匙菜单入口（子项） | 另起一套完整密码管理器 UI |
| 风险域策略可复用（可选抑制） | 承诺 Shadow DOM / 跨域 iframe 全覆盖 |

### 1.4 设计原则

1. **显式优于聪明**：必须先有 Memo；不靠「检测到 form」才可用。  
2. **人在回路**：默认用户点击「填入」；不做进页自动灌入（P1）。  
3. **与登录助手解耦**：平行数据面与执行 API；共享 chrome 入口，不污染帐密语义。  
4. **失败可解释**：某字段选择器未命中时说明哪一项失败，其余可继续填（见 §4.3）。  
5. **只填不交**：备忘场景默认 `shouldSubmit = NO`，避免误提交工单。  
6. **本地优先**：不云同步；清除网站数据不删 Memo。

### 1.5 可行性总评

| 能力 | 可行性 | 说明 |
|------|--------|------|
| URL 匹配（host / pathPrefix） | **高** | 直接复用 `LoginRecipe.matchesURL:` 规则 |
| 多字段 fill + textarea | **高** | 扩展现有 `setValue` / `waitFor` 即可 |
| 点选拾取 | **高** | 复用 `LoginElementPicker` |
| 设置 UI（CRUD） | **高** | 对齐登录助手设置窗分区模式 |
| 普通表单自动检测 + 内联图标 | **中（P2）** | 误报多；**P2 采用「聚焦+有内容」策略，见 §7.2** |
| 从当前表单草稿一键保存为 Memo | **中高（P2）** | 读 DOM 现值 + `cssPath`；P2-0 单字段，P2-1 可扩整表 |

**结论**：P1 只做「Memo CRUD + 匹配点亮 + 多字段一键填入」即可交付核心价值；内联与草稿保存留给 P2。

---

## 2. 用户体验总览

### 2.1 Chrome 落点

继续使用现有登录助手钥匙按钮与菜单，**不新增工具栏图标**（减少 chrome 噪音）。

```
[ ← → ↻ ] [ ========== 地址栏 ★ ========== ] [ ↓  …  key.horizontal  … ]
                                                    ↑
                              有 Recipe 和/或 Memo 时点亮；菜单区分登录 vs 备忘
```

| 状态 | 视觉 / 行为 |
|------|-------------|
| 无 Recipe、无 Memo | 钥匙保持现有「仅检测登录表单可点」逻辑；无备忘相关项 |
| 仅有 Memo | **点亮**；单击可直接「填入站点备忘」，或打开含备忘项的菜单 |
| 有 Recipe + Memo | 点亮；菜单同时提供一键登录与「填入站点备忘」 |
| 正在填入备忘 | 短暂禁用重复点击；失败 toast / 对话框 |

建议菜单结构（增量）：

```
┌ 登录助手 ─────────────────────┐
│ 用系统密码填充…                │  ← 已有（登录）
│ 一键登录 / 仅填入…             │  ← 已有
│ 填入站点备忘：xxx              │  ← 新增；多 Memo 时为子菜单
│ 管理站点备忘…                  │  ← 新增；跳转设置分区
│ ───────────────────────────── │
│ 保存当前为登录配置…            │  ← 已有
│ 管理登录配置…                  │  ← 已有
└───────────────────────────────┘
```

快捷键（建议，可拍板）：

| 快捷键 | 行为 |
|--------|------|
| ⌘⇧L | **保持**一键登录（不改语义） |
| ⌘⇧M | 当前页「填入站点备忘」（无匹配则提示去配置） |

文件菜单可增加「填入站点备忘」与「站点备忘…」（打开设置分区），与「一键登录 / 登录助手…」并列。

### 2.2 设置界面（必做）

在现有「登录助手与互联」设置窗增加分区 **「站点备忘」**（或同窗 Tab），避免再开一个 WC。

| 区块 | 内容 |
|------|------|
| Memo 列表 | 标题 / host / pathPrefix / 字段数 / 更新时间 |
| 编辑 Memo | 标题、host、pathPrefix、字段表（label / selector / value） |
| 字段操作 | 添加行、删除行、对某行「在页面中点选」、上移下移（填充顺序） |
| 空态 | 「为当前标签页创建」预填 host；说明与登录配置的区别 |

输入框一律 `SBTextField` / `SBTextView`（多行 value 可用 `SBTextView`）；选择器用只读 `SBTextField` +「点选」按钮。

### 2.3 与登录助手 / Launchpad 的关系

| 关系方 | 约定 |
|--------|------|
| 登录 Recipe | **数据隔离**；同一 host 可同时有 Recipe 与 Memo |
| 内联钥匙（LoginFormDetector） | P1 **不改**检测启发式；备忘不依赖内联图标 |
| Launchpad | 可选后续：「打开后填入备忘」；P1 不做 |
| 风险域（Anti-bot） | 填充执行走与 Runner 相同的 host 抑制（可选，默认跟随登录助手策略） |

---

## 3. 核心模型：Site Memo

### 3.1 数据结构（概念）

```text
SiteMemo
  memoID          // UUID
  title           // 展示名，如「报障常用」
  host            // 精确 host（可去 www. 匹配，规则对齐 LoginRecipe）
  pathPrefix?     // 可选；如 "/tickets/new"
  fields: [MemoField...]
  updatedAt

MemoField
  fieldID         // 稳定 id，便于编辑与失败回报
  label           // 人类可读，如「工号」
  selector        // CSS，由点选或手写
  value           // 要填入的文本（可含换行）
  enabled         // 默认 true；可临时跳过某字段
```

**匹配规则**（与 `LoginRecipe.matchesURL:` 对齐）：

1. scheme 为 http(s) 或 file（file 时 host 约定为 `file` / `localhost`）。  
2. host 精确匹配；比较前可规范化去掉前导 `www.`。  
3. 若配置了 `pathPrefix`，则 `url.path` 必须以该前缀开头。  
4. 同一 URL 可匹配多条 Memo：工具栏子菜单列出；「填入」默认用列表中标记为默认的一条，否则最近更新的一条。

**不做**（P1）：regex match、query 参数匹配、按表单 `action` 匹配。

### 3.2 持久化

| 数据 | 存储 |
|------|------|
| Memo 元数据 + 全部字段 value | `~/Library/Application Support/MeoBrowser/FormMemo/memos.json` |
| 密码 / OTP | **不存**；敏感登录继续走 LoginAssist Keychain |

JSON 示意：

```json
{
  "version": 1,
  "memos": [
    {
      "memoID": "…",
      "title": "报障常用",
      "host": "ops.example.com",
      "pathPrefix": "/tickets/new",
      "fields": [
        {
          "fieldID": "…",
          "label": "工号",
          "selector": "input[name=\"employeeId\"]",
          "value": "E12345",
          "enabled": true
        },
        {
          "fieldID": "…",
          "label": "现象描述",
          "selector": "#description",
          "value": "……",
          "enabled": true
        }
      ],
      "updatedAt": 0
    }
  ]
}
```

清除「网站数据」**不**删 Memo；设置页提供「删除该备忘」。

### 3.3 为何不扩展 LoginRecipe

| 若塞进 LoginRecipe | 问题 |
|--------------------|------|
| 固定 username/password 槽 | 无法表达任意字段 |
| Keychain 三字段 | 普通备注不该进钥匙串语义 |
| 保存提示要求帐密 | 与备忘保存冲突 |
| 自动登录 / OTP | 误触发风险 |

因此 **平行模型**，代码上可共享「URL 匹配工具函数」，但类型与 Store 分离。

---

## 4. 执行引擎

### 4.1 流程

```
当前 URL → memosMatchingURL
        → 用户选 Memo（或默认）
        → FormMemoRunner.fill(fields)
        → 按 fields 顺序：waitFor(selector) → setValue(el, value)
        → 汇总成功/失败字段 → UI 反馈
```

默认：**不** click 提交、**不** pressEnter 提交。

### 4.2 填充实现要点

在 `LoginRunner` 旁新增精简 `FormMemoRunner`（或给 `LoginRunner` 增加无登录语义的 API），避免再绑 `LoginCredentials`：

```objc
+ (void)fillFields:(NSArray<MemoField *> *)fields
         inWebView:(WKWebView *)webView
       waitTimeout:(NSInteger)timeoutMs
        completion:(void (^)(FormMemoFillResult *result))completion;
```

页面侧 JS（概念）：

1. `waitFor(css)`：短轮询，超时记该字段失败。  
2. `setValue(el, value)`：  
   - `HTMLInputElement`：沿用现有 native value setter + `input`/`change`。  
   - `HTMLTextAreaElement`：对 `HTMLTextAreaElement.prototype` 同样处理。  
   - 其他（`contenteditable` / `select`）：**P1 不做**；选中则失败并提示「仅支持 input/textarea」。  
3. 字段间顺序按 Memo 中数组顺序；前一字段失败**不阻断**后续（可配置，默认继续）。

### 4.3 失败与部分成功

| 结果 | UI |
|------|----|
| 全部成功 | 短暂成功反馈（tooltip / 状态） |
| 部分失败 | 对话框或 toast：「已填入 N 项；失败：工号、部门（选择器未找到）。打开编辑？」 |
| 全部失败 | 明确「未找到任何目标字段」+ 打开编辑 |
| 风险域抑制 | 与登录助手一致文案，说明本站已抑制脚本填充 |

### 4.4 技术风险与对策

| 风险 | 对策 |
|------|------|
| SPA 晚渲染 | `waitFor` + 超时（默认 8s，可 Memo 级覆盖） |
| 选择器改版失效 | 部分成功回报 + 点选重绑 |
| 站点忽略 programmatic input | 派发 `input`/`change`；仍失败则提示手填 |
| iframe / Shadow DOM | P1 仅主 frame（与登录检测一致）；文档写明限制 |
| 误提交 | 默认不提交；不提供「填入并提交」直到有明确需求 |

---

## 5. 架构（落到现有代码）

```
BrowserWindowController
  └─ LoginAssistController（扩展菜单 / 点亮条件）
        ├─ LoginRecipeStore / LoginCredentialStore / LoginRunner   ← 不变
        ├─ FormMemoStore (JSON)                                   ← 新增
        ├─ FormMemoRunner (多字段 fill)                           ← 新增
        └─ LoginElementPicker（复用点选）

BrowserLoginAssistSettingsWC
  └─ 新增「站点备忘」分区：列表 + 编辑 + 点选绑定
```

| 建议新增文件 | 职责 |
|--------------|------|
| `SimpleBrowser/LoginAssist/FormMemo/FormMemo.h/.m` | 模型编解码、`matchesURL:` |
| `.../FormMemoField.h/.m` | 单字段（可放同文件） |
| `.../FormMemoStore.h/.m` | `memos.json` 读写 |
| `.../FormMemoRunner.h/.m` | 多字段 waitFor + setValue |
| 设置 UI 增量 | 在 `BrowserLoginAssistSettingsWindowController` 加分区 |

| 建议修改 | 改动性质 |
|----------|----------|
| `LoginAssistController` | 匹配 Memo、菜单项、⌘⇧M、点亮 OR 条件 |
| `BrowserMenus` | 文件菜单项 |
| `LoginRunner` 内嵌 JS | **可选**：抽出共享 `setValue`；或 Memo Runner 自带副本，避免大改登录路径 |
| `LoginFormDetector` | **P1 不改** |
| `LoginRecipe` / Keychain | **不改** |

复用：`LoginAssistScriptMessageProxy`、风险域 `BrowserRiskHostPolicy`、设置窗 `NSStackView` 布局、ActionGroup 状态刷新时机（导航完成 / 切换标签）。

---

## 6. 安全与隐私

1. Memo 默认视为**非高敏感**工作文本，明文 JSON 本地存储；设置文案提示「勿存放密码，密码请用登录助手」。  
2. 若用户把密码写入 Memo value：不阻止，但 UI 引导改用登录助手。  
3. 日志禁止打印字段 value 全文（可打 label / fieldID / host）。  
4. 不上传、不云同步、不进 Companion 通道。  
5. 与「清除网站数据」边界写入设置说明。  
6. 填充仍受风险域策略约束时，与登录助手一致，避免在强风控页乱注值。

---

## 7. 分阶段交付

### P1 — 多字段填入（本方案必做）

- `FormMemo` / `FormMemoStore` CRUD  
- 设置窗「站点备忘」分区（列表 + 编辑 + 点选）  
- `FormMemoRunner`：input + textarea，只填不交，部分成功回报  
- 工具栏钥匙菜单：「填入站点备忘」/「管理站点备忘…」  
- 点亮条件：匹配 Memo **或** 原有登录逻辑  
- ⌘⇧M + 文件菜单项  
- 本地测试页（可仿 `login-assist-test.html` 做无 password 多字段页）

**验收**：

1. 对无 password 的测试表单配置 2～3 个字段（含一个 textarea），一键全部填入。  
2. 故意写错一个 selector → 其余仍填入，并提示失败项。  
3. 同一 host 不同 `pathPrefix` 的两套 Memo 互不误匹配。  
4. 已有登录 Recipe 站点：菜单同时可见登录与备忘，互不破坏一键登录。  
5. 输入框符合 SBKit 规范。

### P0（不单独交付，可选降级）

仅「命名片段 → 填入当前焦点字段」：若 P1 排期吃紧，可先做焦点粘贴验证需求，但**默认仍以 P1 为目标**，避免两套半成品并存过久。

### P2 — 体验增强（已拍板 §7.2）

- **FM-P2-0**：聚焦字段 + 有内容 → 右侧「＋备忘」内联保存（**默认形态**）  
- **FM-P2-1**（可选）：同 `<form>`「保存本表已填字段」  
- 已配置字段旁淡色「已备忘」标记 / 点一下填入 → **已实现**：匹配备忘字段旁显示「↓」，点击填入整份 Memo  
- Memo 级「填入后聚焦某字段」  
- Launchpad「打开后填入备忘」  
- `select` / 简单 `contenteditable` 支持  

### 7.2 P2 内联保存 — 设计定稿（2026-07-27）

> 用户诉求：像登录助手那样在表单旁有入口，但避免「每个框常驻图标」导致全站误报。  
> **结论**：单独 `FormMemoInlineDetector`；**不改** `LoginFormDetector`。

#### 7.2.1 一句话

用户在 **input / textarea** 里输入内容并聚焦时，字段右侧出现 **「＋备忘」**；点击后把 `{ selector, label, value }` **合并写入**当前 URL 对应的站点备忘，无需打开侧栏手工加点选。

#### 7.2.2 与登录内联钥匙的分工

| | 登录内联（已有） | 备忘内联（P2） |
|--|------------------|----------------|
| 脚本 | `LoginFormDetector` | **`FormMemoInlineDetector`**（新） |
| 出现条件 | 检测到 password + 帐号 | **焦点在字段 + 值非空**（见下） |
| 图标 | 🔑 每登录上下文一枚 | **＋** 跟焦点走，无内容则隐藏 |
| 作用域 | 登录表单 | 普通 `input` / `textarea` |
| 保存目标 | Recipe + Keychain | `FormMemo` JSON |

同一字段不同时显示两把图标：若命中登录上下文（password 邻近），**备忘内联让位**，仍走钥匙菜单 / 侧栏。

#### 7.2.3 显示规则（方案 A，已定稿）

**显示「＋备忘」当且仅当**：

1. 全局开关开启（设置 / 偏好，默认 **开**）；  
2. 当前页未命中 `BrowserRiskHostPolicy` 抑制；  
3. 焦点在 `input`（text/email/tel/number/url 等）或 `textarea`；  
4. `value.trim().length >= 1`（可配置最小长度，默认 1）；  
5. 字段 **可见、未 disabled、非 readonly**；  
6. **排除**：`type` ∈ `password|hidden|search|file|checkbox|radio|submit|button|reset`；OTP / 验证码字段（与登录 Detector 同正则）；已被登录内联接管的登录上下文字段；  
7. 可选：排除 `autocomplete` 含 `cc-` / `card` 等支付类（与登录侧一致保守）。

**不显示**（避免噪音）：

- 未聚焦的字段（即使页面上有很多输入框）；  
- 空字段；  
- 页面 `contenteditable`、`<select>`（留给 P2 后续）。

图标布局：贴在 **当前焦点字段右侧内缘**（`position: fixed` + `getBoundingClientRect`，随 scroll/resize 更新）；约 18×18 CSS px；`z-index` 高于页面内容、低于 Native 菜单。

#### 7.2.4 点击保存流程

```text
用户点「＋备忘」
  → JS postMessage { action: saveField, selector, label, value, url }
  → Native FormMemoPageSaveCoordinator
       1. 解析 host；pathPrefix = 当前 path 去掉 query（与手工新建 Memo 一致，可空）
       2. 查找 defaultMemoMatchingURL:；无则新建 Memo（title 默认「{host} 备忘」）
       3. 按 selector 合并：已存在 → 更新 value；不存在 → append FormMemoField
       4. label 优先：邻近 label 文案 > placeholder > aria-label > name/id
       5. FormMemoStore save；updatedAt 刷新
  → toast「已保存到站点备忘」+ 可选「在侧栏编辑」
```

**确认策略（定稿）**：

| 场景 | 行为 |
|------|------|
| 首次在本机保存备忘 | 轻量确认：「将「{label}」保存到站点备忘？（明文本地存储）」 |
| 同 host 已保存过 | **直接合并**，仅 toast |
| value 长度 > 500 或疑似敏感（正则 `身份证|password|密码` 等） | 强制确认 |

不做静默全网扫描；**必须用户点图标**才写入。

#### 7.2.5 合并与 Memo 粒度

| 规则 | 定稿 |
|------|------|
| 目标 Memo | 当前 URL 的 **默认 Memo**；无默认则 **新建一条** 并设为 default |
| pathPrefix | 新建时预填当前 path（不含 query）；用户可在侧栏改 |
| 字段去重 | **selector 字符串完全相等** → 覆盖 value；否则追加 |
| 同页多 form | P2-0 只保存 **当前焦点字段**；P2-1 再加「保存本表」 |
| 与侧栏 CRUD | 完全同一 `FormMemoStore`；保存后 `FormMemoStoreDidChangeNotification` 刷新侧栏 |

#### 7.2.6 架构

```text
WKWebView
  ├─ LoginFormDetector.js          # 不改 password 门槛
  └─ FormMemoInlineDetector.js     # 新 UserScript
         focusin / input / scroll / resize
         → 定位「＋」按钮
         → saveField message

LoginAssistController / 新 Coordinator
  └─ FormMemoPageSaveCoordinator   # 合并写库 + 确认框 + toast

FormMemoStore（已有）
AssistSidebarController（已有，监听 store 变更）
```

消息通道：复用 `LoginAssistScriptMessageProxy`，新增 handler 名 `formMemoInline`（与 `loginAssistPick` 并列）。

#### 7.2.7 设置与开关

在「登录助手与互联（高级）」或助手侧栏底栏增加勾选项：

- **「输入时显示保存到站点备忘」**（默认开）  
- 与「登录表单内联图标」开关 **独立**（互不影响）

#### 7.2.8 风险与应对

| 风险 | 应对 |
|------|------|
| 搜索框误存 | 排除 `type=search`；仅聚焦且有内容 |
| 选择器漂移 | 先存 `cssPath`；填不进时侧栏点选修正（P1 已有） |
| 敏感信息明文 | 确认框 + 设置文案；不阻止但引导密码走登录助手 |
| 与登录钥匙叠层 | 登录上下文内不显示备忘「＋」 |
| CSP / iframe | 与 LoginFormDetector 相同：主 frame 尽力注入；失败则仅菜单/侧栏 |

#### 7.2.9 验收（P2-0）

1. `form-memo-test.html`：在姓名字段输入 → 出现「＋」→ 点击 → 侧栏可见新字段且 ⌘⇧M 可填入。  
2. 同一字段改字再点「＋」→ value 更新，不重复两条。  
3. 登录测试页：密码框旁只有钥匙，无备忘「＋」。  
4. 关闭开关后无注入、无保存。  
5. 风险域页面不注入。

开发计划见 [site-form-memo-development-plan.md](site-form-memo-development-plan.md) Phase FM-P2。

### 明确不做（近期）

- 全网 Autofill 启发式  
- 与 iCloud 密码 / 系统通讯录合并  
- 云同步 Memo 库  
- 默认进页自动填充  

---

## 8. 相对「扩登录助手」原设想的调整

| 原设想 | 建议调整 | 原因 |
|--------|----------|------|
| 登录助手直接支持普通表单 | **平行 Site Memo**，菜单挂在同一钥匙下 | 保持 Recipe/Keychain 语义干净 |
| 放宽检测器去掉 password 门槛 | **P1 不改 Detector**；有 Memo 即入口 | 避免全站误报钥匙 |
| 把备注塞进 username 等槽位 | **fields[] 任意列表** | 真实表单字段数不固定 |
| 填完自动提交 | **默认只填** | 工单/申请误提交成本高 |
| 先做焦点粘贴再做多字段 | **直接 P1** | 与产品目标一致；Picker/Runner 已具备 |

---

## 9. 开放问题（待拍板）

1. **默认单击钥匙**：仅有 Memo 时，单击直接填入还是弹出菜单？建议：**直接填入默认 Memo**（与「仅有 Recipe 时一键登录」对称）；同时有两者时弹出菜单。  
2. **多 Memo 默认项**：是否需要 `isDefault`？建议：**要**，与 Recipe 一致。  
3. **⌘⇧M**：是否占用？若冲突再改为菜单-only。  
4. **value 是否允许引用「当前剪贴板」**：P1 不做；避免隐式行为。  
5. **设置窗**：同窗分区 vs 独立 WC？建议：**同窗分区**，降低入口分散。

---

## 10. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-27 | 初稿：定位、与登录助手解耦、P1 多字段模型/执行/架构/验收 |
| 0.2 | 2026-07-27 | P1 落地：FormMemo Store/Runner、设置分区、⌘⇧M、测试页 |
| 0.3 | 2026-07-27 | P2 内联保存定稿：聚焦+有内容「＋备忘」、FormMemoInlineDetector |
| 0.4 | 2026-07-27 | P2-0 落地：InlineDetector + PageSaveCoordinator + 偏好开关 |

开发计划见 [site-form-memo-development-plan.md](site-form-memo-development-plan.md)。
