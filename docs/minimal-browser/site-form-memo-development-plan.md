# 站点表单备忘 — 开发计划

> 基于 [site-form-memo-design.md](site-form-memo-design.md)。  
> 前置：登录助手 V1（Recipe Store / LoginRunner / LoginElementPicker / 设置窗）已落地。  
> **状态：P1 已实现（2026-07-27）；P2-0～P2-2 已实现（内联保存 · 2026-07-27）**

---

## 行为定稿（相对设计稿）

| 项 | 定稿 |
|----|------|
| 产品名（UI） | **站点备忘** |
| 与登录助手关系 | 平行数据面；共用钥匙菜单与设置窗 |
| 单击钥匙 | **仅有 Memo** → 直接填入默认 Memo；**仅有 Recipe** → 一键登录；**两者都有** → 弹菜单 |
| 多 Memo 默认 | 有 `isDefault`；无默认则取最近 `updatedAt` |
| 快捷键 | ⌘⇧M 填入站点备忘；⌘⇧L 保持一键登录 |
| 填充策略 | 只填不交；字段失败不阻断后续；部分成功可解释 |
| Detector | **不改** `LoginFormDetector`；P2 新增 **`FormMemoInlineDetector`** |
| 清除网站数据 | **不**删 Memo |
| P2 内联保存 | **聚焦 + 值非空** 显示「＋备忘」；点击合并写默认 Memo |

---

## 总览

| 阶段 | 名称 | 对应设计 | 状态 | 产出 |
|------|------|----------|------|------|
| Phase FM-0 | 数据层 | §3 | **完成** | FormMemo + Store JSON |
| Phase FM-1 | 执行引擎 | §4 | **完成** | FormMemoRunner（input/textarea） |
| Phase FM-2 | Chrome 入口 | §2.1 / §5 | **完成** | 菜单 / 点亮 / ⌘⇧M |
| Phase FM-3 | 设置 UI | §2.2 | **完成** | 同窗「站点备忘」分区 + 点选 |
| Phase FM-4 | 联调验收 | §7 P1 | **完成（编译）** | 测试页 + Makefile；手工验收见下 |
| **Phase FM-P2-0** | 内联检测 + 图标 | §7.2 | **完成** | `FormMemoInlineDetector` |
| **Phase FM-P2-1** | 点击保存写库 | §7.2.4 | **完成** | `FormMemoPageSaveCoordinator` |
| **Phase FM-P2-2** | 开关 + 验收 | §7.2.7 / §7.2.9 | **完成（编译）** | 偏好项 + 测试页扩展 |
| Phase FM-P2-3 | 整表草稿保存 | §7.2 | 可选 | 同 form 批量读取 |
| Phase FM-P2-4 | 已备忘标记 | §7 P2 | **完成** | 匹配字段旁「↓」一键填入 |

---

## Phase FM-0：数据层

- [x] **0.1** 创建目录 `SimpleBrowser/LoginAssist/FormMemo/`
- [x] **0.2** `FormMemo` / `FormMemoField` 模型
- [x] **0.3** `FormMemoStore` → `Application Support/MeoBrowser/FormMemo/memos.json`
- [x] **0.4** `memosMatchingURL:` / `defaultMemoMatchingURL:`
- [x] **0.5** `setDefaultMemoID:`
- [x] **0.6** Makefile 源文件与 include

---

## Phase FM-1：执行引擎

- [x] **1.1** `FormMemoFillResult`
- [x] **1.2** `FormMemoRunner fillFields:…`
- [x] **1.3** input + textarea `setValue`
- [x] **1.4** 非 input/textarea 失败提示
- [x] **1.5** 字段失败不阻断后续
- [x] **1.6** 风险域跟随登录助手策略

---

## Phase FM-2：Chrome 入口

- [x] **2.1** `matchedMemos` + `updateForURL:`
- [x] **2.2** 点亮：`Recipe ∪ Memo ∪ 登录检测`
- [x] **2.3** 单击钥匙分流（仅 Memo / 仅 Recipe / 两者）
- [x] **2.4** 助手菜单备忘项
- [x] **2.5** ⌘⇧M + 文件菜单
- [x] **2.6** 成功 toast / 部分失败对话框

---

## Phase FM-3：设置 UI

- [x] **3.1** 左侧分段「登录配置 | 站点备忘」
- [x] **3.2** Memo 列表 CRUD
- [x] **3.3** 标题 / host / pathPrefix / 默认 / 字段表
- [x] **3.4** 字段添加删除上下移 / 点选
- [x] **3.5** SBKit 输入控件
- [x] **3.6** `revealMemoSection` / `selectMemoID:`

---

## Phase FM-4：联调验收

- [x] **4.1** `form-memo-test.html`
- [x] **4.2** Makefile 拷贝测试页
- [ ] **4.3** 手工验收勾选（见下）
- [x] **4.4** 设计稿状态更新

### 验收清单（设计 §7）

1. [ ] 无 password 测试表单配置 2～3 字段（含 textarea），一键全部填入  
2. [ ] 故意写错一个 selector → 其余仍填入，并提示失败项  
3. [ ] 同一 host 不同 pathPrefix 的两套 Memo 互不误匹配  
4. [ ] 已有登录 Recipe 站点：菜单同时可见登录与备忘  
5. [ ] 输入框符合 SBKit 规范  

---

## Phase FM-P2-0：内联检测 + 「＋备忘」图标

- [x] **P2-0.1** `FormMemoInlineDetector.h/.m`：嵌入式 JS（`focusin` / `input` / `scroll` / `resize`）
- [x] **P2-0.2** 复用 `cssPath` 逻辑（可与 LoginFormDetector 抽共享片段或内联副本）
- [x] **P2-0.3** 显示规则：聚焦 + 非空 + 排除 password/search/OTP/登录上下文
- [x] **P2-0.4** `position:fixed` 单按钮跟焦点；风险域不注入
- [x] **P2-0.5** `WKUserScript` 注册 + `formMemoInline` message handler
- [x] **P2-0.6** `BrowserRiskHostPolicy` 与登录侧一致

---

## Phase FM-P2-1：点击保存写库

- [x] **P2-1.1** `FormMemoPageSaveCoordinator`：解析 host / pathPrefix / label
- [x] **P2-1.2** 查找或新建 default Memo；按 selector 合并字段
- [x] **P2-1.3** 首次保存确认框；长文本 / 敏感词强制确认
- [x] **P2-1.4** 成功 toast（侧栏经 Store 通知刷新；可选后续加「在侧栏编辑」）
- [x] **P2-1.5** 日志禁止打印 value 全文

---

## Phase FM-P2-2：开关 + 验收

- [x] **P2-2.1** `FormMemoPreferences`：`inlineSaveEnabled`（默认 YES）
- [x] **P2-2.2** 高级设置站点备忘分区勾选项
- [x] **P2-2.3** 扩展 `form-memo-test.html` 验收场景
- [x] **P2-2.4** Makefile；`make browser` 通过
- [ ] **P2-2.5** 手工验收（设计 §7.2.9）

### P2 验收清单

1. [ ] 测试页输入姓名 → 出现「＋」→ 保存 → 侧栏可见字段且 ⌘⇧M 可填  
2. [ ] 改字再点「＋」→ 同 selector 更新 value  
3. [ ] 登录测试页密码区无备忘「＋」  
4. [ ] 关闭开关后无图标  
5. [ ] 风险域不注入  

---

## 明确不做（本计划）

- 放宽 `LoginFormDetector`  
- 进页自动填充  
- 扩展 LoginRecipe / Keychain  
- 全站每个输入框常驻图标（P2 仅聚焦+有内容）  
- Launchpad 绑定（FM-P2-4 之后）  

---

## 建议文件布局（P2）

```text
SimpleBrowser/LoginAssist/FormMemo/
  FormMemoInlineDetector.h/.m
  FormMemoPageSaveCoordinator.h/.m
  FormMemoPreferences.h/.m          # 若尚未有独立偏好
```

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-27 | 初稿：FM-0～FM-4 任务拆分与行为定稿 |
| 0.2 | 2026-07-27 | P1 实现完成；编译通过；手工验收待勾选 |
| 0.3 | 2026-07-27 | P2 内联保存：FM-P2-0～2 任务拆分 |
| 0.4 | 2026-07-27 | P2-0～2 实现完成；编译通过；手工验收待勾选 |
