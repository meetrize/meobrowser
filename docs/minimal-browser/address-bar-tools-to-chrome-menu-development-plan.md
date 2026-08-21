# 地址栏工具迁入标签栏 ⋯ — 开发计划

> 基于 [address-bar-tools-to-chrome-menu-design.md](address-bar-tools-to-chrome-menu-design.md)。  
> 前置：Chrome 动作定制（CP-0～CP-3）已完成（LayoutStore、拖拽、图钉菜单、ghost）。  
> 状态：**部分实现（AT-0～AT-1 完成；AT-2～AT-3 待办）**  
> 建议 Cursor 计划：`.cursor/plans/address-bar-tools-to-chrome-menu.plan.md`

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 迁入 | 地址栏 ActionGroup 保留项 → Chrome Catalog |
| 删除 | `comment` / `pageSettings` / `copyLink` |
| 默认 | 迁入项全部 hidden；窗口七项保持条上可见 |
| 菜单 | 单一列表 + 图钉（扩展现有 ⋯） |
| 钉上落点 | 标签条 Chrome 区 |
| 地址栏 | 不再显示工具按钮 / 溢出 ▾ |
| 偏好 | 扩展 Chrome LayoutStore；迁移旧 AddressBar order/hidden |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase AT-0 | Catalog 扩展 + 默认 hidden + 菜单可见 | **完成** | 迁入项进目录与 ⋯；条上默认仍七图标；删三项 |
| Phase AT-1 | 接线与角标 | **完成** | 菜单/钉上点击可用；下载/通知等角标 |
| Phase AT-2 | 退役地址栏 ActionGroup UI | 待办 | 地址栏无工具；布局变宽；迁移偏好 |
| Phase AT-3 | 打磨验收 | 待办 | 精简模式、多窗、文档、手测 |

**交付：AT-0～AT-3。** 预估约 2.5～4 人日。

---

## Phase AT-0：Catalog + 默认 hidden

**目标**：目录与菜单先「看得见、钉得动」；点击可先部分占位。

### 任务

1. `BrowserChromeActionItem`：新增迁入项常量与 catalog 条目；**不**加入 comment/pageSettings/copyLink。  
2. `BrowserChromeActionLayoutStore`：  
   - `defaultOrdered…` 追加迁入 id  
   - 默认 `hidden` = 全部迁入 id  
   - `known` 集合更新；清洗已删 id  
3. 冷启动：条上仍七 Chrome + ⋯；⋯ 列表变长且迁入项图钉为「可固定」。  
4. 固定一项后条上出现图标（可暂无 no-op action）。  
5. `make browser`。

### 验收

- [x] ⋯ 中有查找/下载/…且无评论/页面设置/复制链接  
- [x] 默认条上无迁入图标  
- [x] 图钉可把「下载」钉上/取消  
- [x] `make browser` 通过  

---

## Phase AT-1：接线与角标

**目标**：行为对齐原地址栏按钮。

### 任务

1. 扩展 `performChromeActionForItemID:` / `wireChromeActionButtons`：  
   tabOverview、findInPage、history、download、loginAssist、companionLink、sendToPhone、notificationInbox、phonePolicy、captchaAssist、rssFeed；（share/screenshot/extension 按 D7 禁用或提示）  
2. `reloadChromeActionsFromStore` 后：  
   - `reinstallDownloadChromeBadge`  
   - 通知角标  
   - companion 圆点 / tooltip  
   - login/captcha/feed 点亮（`setOn:`）  
3. 全屏等对个别项的 enabled 规则（若有）一并迁到 Chrome 按钮。  
4. 手测各入口。

### 验收

- [x] 菜单点「查找」弹出查找条；「下载」开面板；「历史」开侧栏等  
- [x] 钉上「下载」后角标/进度正常；隐藏再钉上不丢  
- [x] 互联未连接时发送项表现合理  
- [x] `make browser` 通过  

---

## Phase AT-2：退役地址栏工具 UI + 迁移

**目标**：地址栏不再挂工具；旧偏好迁入。

### 任务

1. AddressBarRow：去掉或清空 ActionGroup 占位，URL 伸展。  
2. 删除/停用 ActionGroup 内按钮创建、溢出菜单、拖宽、右键固定（可保留空类短期降风险，或直接删调用）。  
3. WC：所有 `addressBarActionGroup.xxxButton` 改为 Chrome `buttonForItemID:`。  
4. 迁移：  
   - 读 `BrowserAddressBarActionOrder` / `Hidden`  
   - 有效 id 合并进 Chrome order；旧「未隐藏」→ 从 Chrome hidden 移除  
   - 写迁移标记  
5. 停止写入地址栏 order/hidden。  
6. `make browser`。

### 验收

- [x] 地址栏右侧无图标、无 ▾  
- [x] 新装默认符合 § 设计 2.4  
- [x] 模拟旧「显示下载+查找」用户 → 迁移后二者在标签条上（`BrowserChromeActionMigratedFromAddressBar` + 旧 Hidden 键）  

---

## Phase AT-3：打磨验收

### 任务

1. 精简模式下钉上工具仍可用。  
2. 多窗 layout 通知（已有）回归。  
3. 更新：`chrome-actions-customize-design.md`（推翻「不与地址栏打通」）、查找/下载等文档入口说明、本设计 §7 勾选。  
4. 全量手测清单。

### 验收

- [x] 设计 §7 全过（实现侧；手测见清单）  
- [x] `make browser` 通过  

---

## 手测清单

1. 新用户：地址栏无工具；条上七 Chrome + ⋯  
2. ⋯ 无「评论 / 页面设置 / 复制链接」  
3. 固定下载、查找、历史 → 条上出现且可点  
4. 拖拽下载与摸鱼换位；拖到 ⋯ 隐藏  
5. 下载进行中角标；通知未读角标  
6. 精简模式仍能用钉上的查找  
7. 旧偏好迁移（或 defaults write 模拟）  
8. share/screenshot/extension：禁用或有提示，不崩溃  
9. 第二窗口同步固定状态  

---

## 关键文件（预期）

| 路径 | 说明 |
|------|------|
| `ChromeActions/BrowserChromeActionItem.*` | Catalog 扩项 |
| `ChromeActions/BrowserChromeActionLayoutStore.*` | 默认 hidden、迁移 |
| `BrowserWindowController.m` | wire / perform / 角标 / 菜单已通用 |
| `AddressBar/BrowserAddressBarActionGroup.*` | 退役或掏空 |
| `AddressBar/BrowserAddressBarRowView.*` | 布局 |
| `docs/minimal-browser/address-bar-tools-to-chrome-menu-*.md` | 本文与设计 |
| `docs/minimal-browser/chrome-actions-customize-design.md` | 脚注修订 |

---

## 实现顺序

```
AT-0  Catalog + 默认 hidden + 菜单/图钉
AT-1  动作接线 + 角标
AT-2  地址栏退役 + 偏好迁移
AT-3  打磨文档验收
```

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| WC 仍强依赖 actionGroup.button | AT-1/2 统一改 chrome buttonForItemID，hidden 时跳过角标 |
| 菜单过长 | AT-0 先接受；AT-3 可加菜单最小宽度 |
| 迁移覆盖用户 Chrome 布局 | 只合并迁入段；不打乱已有窗口七项相对序 |
| 删三项后旧 order 残留 | sanitize 丢弃 |

---

## 完成定义（DoD）

- 设计 §7 勾选完成  
- AT-0～AT-3 完成  
- 地址栏无工具图标；⋯ 为唯一工具发现入口（加点阵图钉）  
- 不回归：摸鱼/透明/精简/置顶/自动滚/大小窗/查找/下载/互联  
