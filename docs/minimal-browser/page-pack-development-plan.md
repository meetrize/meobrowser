# 页面插件（Page Pack）— 开发计划

> 基于 [page-pack-design.md](page-pack-design.md)（**已确认定稿**）。  
> 前置：trailing 侧栏槽（通知 / 助手 / 历史）、`WKWebView` 导航回调、SBKit 文本控件、Chrome / 地址栏动作区入口惯例。  
> 状态：**PP-0～PP-MVP-D 已实现**（2026-08-21）  
> Cursor 计划：[.cursor/plans/page-pack.plan.md](../../.cursor/plans/page-pack.plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 产品名 | 页面插件；模块名 `PagePack` |
| 单元 | Pack = manifest + 多文件（`.css` / `.js`） |
| 侧栏 UX | 浏览态（本页 \| 全部 \| 发现占位）→ 点击进入编辑态全高编辑器 |
| 入口 | 独立工具栏图标 + 查看菜单 + **⌘⇧P** |
| 侧栏槽 | `BrowserTrailingSidebarKindPagePack`；与通知 / 助手 / 历史互斥 |
| 注入 | 导航按 match 动态 `evaluateJavaScript`；保存热更新当前页；不 `removeAllUserScripts` |
| JS API | 无 GM_*；`pageWorld` |
| 编辑器 | `SBTextView` 等宽 |
| 默认 match | 当前 origin + `/*` |
| 远程发现 | MVP 仅占位；PP-1 再做 Catalog |

**本期交付：PP-0 + PP-MVP（含打磨）。PP-1 / PP-2 另开计划。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| **PP-0** | 模型 + Store + Matcher | **完成** | 落盘、匹配、无 UI 可测 |
| **PP-1-MVP-A** | Injector + 导航挂钩 | **完成** | 匹配 Pack 注入 CSS/JS；热更新 API |
| **PP-1-MVP-B** | 侧栏浏览态 + 入口 + 互斥 | **完成** | 本页/全部列表、启停、新建、槽位 |
| **PP-1-MVP-C** | 侧栏编辑态 | **完成** | 多文件 Tab、元数据、保存即时生效 |
| **PP-1-MVP-D** | 打磨与验收 | **完成** | 总开关、空态、危险 match、文档 |

> 阶段编号：实现里程碑用 **PP-0 / PP-MVP-A～D**；设计文档中的产品阶段 **PP-1（远程）/ PP-2（导入）** 不在本计划任务列表内。

---

## Phase PP-0：模型 + Store + Matcher

### 任务

1. 新建 `SimpleBrowser/PagePack/`：`PagePackModels`（Pack / File / runAt / kind）  
2. `PagePackStore`：`Application Support/MeoBrowser/PagePacks/`；`index.json` + `{id}/manifest.json` + 源文件；原子写盘  
3. CRUD：创建 / update metadata / write file content / delete pack / setEnabled  
4. `PagePackMatcher`：Chrome 风格 `@match` 子集 + excludes；单测或小命令行/单元断言覆盖常见模式  
5. 新建 Pack 辅助：`defaultMatchForURL:` → `https://host/*`（含 port 时保留）  
6. Makefile 纳入新 `.m`；`make browser` 编译通过  

### 验收

- [ ] 创建含 `style.css` 的 Pack，重启进程后 index 与文件仍在  
- [ ] `https://a.example.com/x` 匹配 `https://*.example.com/*`；exclude 生效  
- [ ] 非法文件名 / 空 id 有明确错误，不写半套目录  

---

## Phase PP-MVP-A：Injector + 导航挂钩

### 任务

1. `PagePackInjector`：给定 `WKWebView` + URL，注入所有 enabled 且匹配的 Pack  
2. CSS：插入 `<style data-meo-pagepack="packId:fileName">`；热更新替换同节点  
3. JS：按 `runAt`（start / end / idle）在合适导航回调触发；同组内文件名排序；CSS 先于 JS  
4. `mainFrameOnly` 默认 YES；仅主 frame 注入  
5. 挂到 `BrowserWindowController` / Tab 导航：`didCommit` → start 类；`didFinish` → end/idle  
6. 禁用 Pack：移除其 CSS 节点；JS 不保证卸载（与设计一致）  
7. **禁止** `removeAllUserScripts`  
8. 可选：设置项或 UserDefaults `MeoPagePackEnabled` 总开关（默认 YES）；关则 Injector 空操作  
9. `make browser`  

### 验收

- [ ] 匹配站打开后 CSS 立即可见（如 `body { outline: 2px solid red }`）  
- [ ] JS `document-end` 能改 DOM  
- [ ] 不匹配站不注入  
- [ ] 登录助手 / 页内查找等现有 UserScript 仍正常  

---

## Phase PP-MVP-B：侧栏浏览态 + 入口 + 互斥

### 任务

1. `PagePackSidebarController`：浏览态 UI（分段本页 / 全部 / 发现占位、搜索、列表、行内开关、＋新建）  
2. 顶栏「本页生效 · N」随选中 tab URL 更新  
3. `BrowserTrailingSidebarSlot` 增加 `PagePack` kind；开此栏关其他  
4. 工具栏 / Chrome 动作：页面插件图标 Toggle  
5. 查看菜单「页面插件」+ **⌘⇧P**  
6. 宽度记忆 `MeoPagePackSidebarWidth`（320～560，默认 400）；Esc / 窄窗收起对齐现有侧栏  
7. 新建：预填名称 + 当前 URL 的默认 match + 默认 `style.css`（可空内容）→ 进入编辑态或先留列表（建议直接进编辑态）  
8. `make browser`  

### 验收

- [ ] ⌘⇧P / 图标打开侧栏；再开通知侧栏则页面插件关闭  
- [ ] 「本页」只显示匹配项；开关立刻影响注入（关 CSS 卸节点）  
- [ ] 「发现」显示占位文案，无崩溃  

---

## Phase PP-MVP-C：侧栏编辑态

### 任务

1. 编辑态：返回按钮、启用开关、match 摘要（可展开编辑 matches/excludes/runAt）  
2. 文件 Tab +「＋」新建 `.css`/`.js`；重命名可选（MVP 可先固定名编辑内容）  
3. 代码区：`SBTextView`、等宽、纯文本；污点「未保存」+ 丢弃 / 保存  
4. ⌘S 保存（侧栏为第一响应者路径时）  
5. 保存：写盘 → Injector 对**当前选中 tab** 热应用该 Pack  
6. 删除文件（确认）；删除整个 Pack（确认，回浏览态）  
7. 元数据字段一律 `SBTextField` / 需要时 `SBTextView`  
8. `make browser`  

### 验收

- [ ] 改 CSS 保存后当前页无刷新即可看到变化  
- [ ] 改 JS 保存后重执行；异常时「在页面中刷新」可用  
- [ ] 多文件切换不丢未保存提示（切 Tab 前提示或自动保留 buffer）  

---

## Phase PP-MVP-D：打磨与验收

### 任务

1. 空态文案与引导按钮  
2. 危险 match（如 `*://*/*`）保存/启用时警告  
3. 切 tab 时浏览态列表刷新；编辑态可选「与本页不匹配」提示  
4. 设计稿 §9 对照勾选；roadmap §3.9 可链到本设计（可选一行）  
5. 手测清单走完；Cursor plan todos 勾完  

### 验收

- [ ] 下文手测清单全部通过  
- [ ] `make browser` 无新增警告噪音（按仓库惯例）  

---

## 手测清单

1. 新建页面插件（默认 match 当前站）→ 写 CSS → 保存 → 页内立刻变样式  
2. 再加 `tweak.js`（document-end）→ 保存 → DOM 被改  
3. 关掉启用开关 → CSS 消失；刷新后 JS 副作用按预期（需刷新才干净则符合设计）  
4. 打开不匹配的其他站 → 不注入  
5. ⌘⇧P 开侧栏 → 开助手侧栏 → 页面插件关闭  
6. 重启 App → Pack 仍在且仍启用  
7. 页内查找 / 登录助手检测仍正常  
8. 「发现」占位可见  

---

## 关键文件（预期）

| 路径 | 说明 |
|------|------|
| `SimpleBrowser/PagePack/*` | 模型、Store、Matcher、Injector、Sidebar、Editor |
| `SimpleBrowser/BrowserTrailingSidebarSlot.*` | 新 kind |
| `SimpleBrowser/BrowserWindowController.*` | 入口、导航挂钩、侧栏显隐 |
| `ChromeActions` 或 AddressBar ActionGroup | 工具栏图标 |
| `Makefile` | 编译新源 |
| `docs/minimal-browser/page-pack-design.md` | 已确认 |
| `docs/minimal-browser/page-pack-development-plan.md` | 本文件 |

---

## 实现顺序

```text
PP-0  Store + Matcher
  → PP-MVP-A  Injector + 导航
  → PP-MVP-B  侧栏浏览 + 入口 + 互斥
  → PP-MVP-C  编辑态 + 保存热更新
  → PP-MVP-D  打磨手测
```

每阶段结束执行 `make browser`（或现有 watch）验证。

---

## 明确不做（本期）

- 远程 Catalog 安装 / 更新（设计 PP-1）  
- `.user.js` / UserCSS 导入、GM_*、isolated world 选项（设计 PP-2）  
- Monaco / 语法高亮  
- 云同步 Pack  
- iframe 默认注入（保持 mainFrameOnly）  

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-08-21 | 初稿；决策按推荐全部定稿；待 PP-0 开工 |
| 0.2 | 2026-08-21 | PP-0～PP-MVP 落地：Store/Injector/侧栏/⌘⇧P/扩展图标 |
