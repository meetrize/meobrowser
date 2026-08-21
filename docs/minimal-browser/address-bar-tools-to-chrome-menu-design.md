# 地址栏工具迁入标签栏 ⋯ — 统一图钉目录

> 目标：将地址栏右侧 ActionGroup **全部**工具并入标签栏 ⋯ 的「文字 + 图钉」模型；与现有 Chrome 动作（摸鱼 / 透明 / …）同一套拖拽、固定、隐藏；**默认不在条上显示**（仅菜单可见）；并删除「评论 / 页面设置 / 复制链接」。  
> 状态：**已实现（AT-0～AT-3）**
> 开发计划：[address-bar-tools-to-chrome-menu-development-plan.md](address-bar-tools-to-chrome-menu-development-plan.md)  
> 关联：[chrome-actions-customize-design.md](chrome-actions-customize-design.md) · `BrowserAddressBarActionGroup` · `BrowserChromeActionLayoutStore`

---

## 1. 需求理解

### 1.1 现状（两套工具区）

```
标签条：  […][+]  [摸鱼][透明][精简][置顶][自动滚][速度][缩放][⋯]
地址栏：  ◀ ▶ ↻ │ URL … │ [概览][查找][历史][下载][登录][互联]…[溢出▾]
```

| 区 | 能力 | 定制 |
|----|------|------|
| 标签栏 Chrome 区 | 窗口壳（摸鱼/透明/精简/置顶/自动滚/速度/缩放） | 已可拖改序、拖进 ⋯、图钉固定 |
| 地址栏 ActionGroup | 页面/站点工具（查找、下载、互联…） | 另有一套 order/hidden + 宽度溢出 |

痛点：两套入口、两套偏好；地址栏图标挤占 URL 宽度；精简模式会整行藏掉 ActionGroup。

### 1.2 产品一句话

**地址栏右侧工具全部进入标签栏 ⋯ 统一目录：菜单行为与现有 Chrome 项相同（点标题执行、右侧图钉固定）；默认隐藏；去掉评论 / 页面设置 / 复制链接；地址栏不再挂工具图标。**

### 1.3 功能拆解

| # | 能力 | 说明 |
|---|------|------|
| F1 | Catalog 合并 | 原 ActionGroup 保留项并入 `BrowserChromeActionItem` 目录（与摸鱼等同一 Catalog） |
| F2 | 默认隐藏 | 迁入项 **默认 `hidden`**；冷启动条上仍只有现有七个 Chrome 图标 + ⋯（或用户已定制的 Chrome 布局） |
| F3 | 同一菜单行为 | ⋯ 单一列表列出 **全部** 可定制项（含迁入项）；图钉 / 点标题 / 拖拽 / 拖到 ⋯ 规则不变 |
| F4 | 钉到条上 | 图钉固定后出现在标签栏右侧 Chrome 区（⋯ 左侧），可与摸鱼等混排拖拽 |
| F5 | 地址栏清空工具 | ActionGroup 不再展示工具按钮；URL 区可更宽；相关溢出/右键固定逻辑退役或空壳 |
| F6 | 删除三项 | 从目录与任何菜单/偏好中移除：`comment`（评论）、`pageSettings`（页面设置）、`copyLink`（复制链接） |
| F7 | 态与角标 | 下载角标、通知未读、互联圆点、登录/验证码点亮等在「钉在条上」时仍可用；仅在菜单时用勾选/文案表达开态 |

### 1.4 明确不做（V1）

| 不做 | 原因 |
|------|------|
| 钉上后仍画在地址栏右侧 | 与「迁入标签栏」冲突；统一落点 = 标签条 Chrome 区 |
| 保留地址栏独立溢出 ▾ 作为主入口 | 主入口改为标签栏 ⋯；避免双 ⋯ |
| 菜单再拆「窗口 / 页面」两段强制分区 | 延续 customize 定稿：单一列表；顺序由用户 order 决定（可用默认序把窗口项放前） |
| 实现分享/截图/扩展的完整产品能力 | 若目录中保留占位，点击可 no-op 或轻提示；本需求不强制做功能 |
| 每窗独立工具布局 | 仍 App 级 LayoutStore + 通知 |

---

## 2. 目录与删除范围

### 2.1 删除（不再出现）

| 旧 id | 标题 | 处理 |
|-------|------|------|
| `comment` | 评论 | **删除**（目录、偏好清洗、无迁移） |
| `pageSettings` | 页面设置 | **删除** |
| `copyLink` | 复制链接 | **删除** |

### 2.2 迁入 Catalog 的地址栏项（默认 hidden）

| itemID | 标题 | Symbol（参考） | 开态/角标 | 点击（复用现 WC） |
|--------|------|----------------|-----------|-------------------|
| `tabOverview` | 标签概览 | `square.grid.2x2` | — | 现概览 |
| `findInPage` | 查找 | `magnifyingglass` | — | ⌘F / 查找条 |
| `history` | 历史 | `clock` | — | 历史侧栏 |
| `download` | 下载 | `arrow.down.circle` | 角标/进度环 | 下载面板 |
| `loginAssist` | 登录助手 | `key.horizontal` | 点亮 | 登录助手 |
| `companionLink` | 互联 | `link` | 状态圆点 | 互联 UI |
| `sendToPhone` | 发送到手机 | `iphone.and.arrow.forward` | 未连接可灰 | 发送 |
| `notificationInbox` | 手机通知 | `bell` | 未读角标 | 通知侧栏 |
| `phonePolicy` | 号码策略 | `phone.badge.waveform` | — | 策略面板 |
| `captchaAssist` | 验证码助手 | `checkerboard.rectangle` | 点亮 | 验证码助手 |
| `rssFeed` | RSS | `dot.radiowaves.up.forward` | 点亮 | Feed |
| `share` | 分享 | `square.and.arrow.up` | — | 现网若未接线：占位/轻提示 |
| `screenshot` | 截图 | `camera` | — | 同上 |
| `extension` | 扩展 | `puzzlepiece.extension` | — | 同上 |

> 是否保留 share / screenshot / extension：用户未要求删除，**V1 保留在目录**（默认 hidden）。若点击无实现，菜单/条上可灰显或 toast「即将推出」，避免空按钮无反馈。

### 2.3 已有 Chrome 项（不变，默认可见）

`afkMode` / `transparentMode` / `compactMode` / `alwaysOnTop` / `autoScroll` / `scrollSpeed` / `windowLayout` + 固定 `moreMenu`。

### 2.4 默认 order / hidden（定稿）

**order（建议）：**

```
[七个窗口 Chrome 项…] +
[tabOverview, findInPage, history, download, loginAssist, companionLink,
 sendToPhone, notificationInbox, phonePolicy, captchaAssist, rssFeed,
 share, screenshot, extension]
```

**hidden 默认：**

- 七个窗口项：**不在** hidden（保持现网条上七图标）  
- 全部迁入的地址栏项：**全部在** hidden  

用户可用图钉把「下载」「查找」等钉到标签条。

---

## 3. 交互与信息架构

### 3.1 条上（标签栏右侧）

```
[+]  [已固定图标按 order…][⋯]
```

- 默认与现网 Chrome 七图标一致。  
- 钉上「下载」后示例：`[摸鱼]…[缩放][下载][⋯]`（相对序遵从全局 order）。  
- 拖拽改序、拖到 ⋯、阴影 ghost：**同一套**现有 Chrome 拖拽逻辑。  
- ⋯ 仍不可拖、永在最右。

### 3.2 ⋯ 菜单

```
  摸鱼模式                         📌/unpin
  …
  窗口缩小                         …
  标签概览                         …   ← 默认 unpin（可固定）
  查找                             …
  历史                             …
  下载                             …
  …
```

- **单一列表**，无强制 separator（若项过多难扫，后续可加「分组标题」非 V1）。  
- 点标题 = `performChromeActionForItemID:` 扩展分支。  
- 点图钉 = LayoutStore hidden 翻转。  
- 开关类（摸鱼、自动滚等）继续勾选；下载等非开关无勾选。

### 3.3 地址栏行

```
◀ ▶ ↻ │            URL 输入框（更宽）            │
```

- **不再**渲染 ActionGroup 工具按钮与 ▾ 溢出。  
- 地址栏与内容区之间的「拖宽 ActionGroup」手势可删除或改为仅调其他布局（V1：**删除 ActionGroup 宽度拖拽**）。  
- 精简模式：地址栏行仍隐藏；但用户钉在标签条上的「查找/下载」**仍可见**（比旧模型更合理）。

### 3.4 角标与附属 UI

| 能力 | 钉在条上 | 仅在菜单 |
|------|----------|----------|
| 下载角标 / 进度环 | 挂在对应 Chrome 按钮上（reload 后重装） | 菜单标题可带「(N)」或不显示角标（V1：菜单可不带角标，条上有即可） |
| 通知未读 | 同下载 | 同上 |
| 互联圆点 | 小圆点叠在按钮上或改 tint | 菜单用标题后缀「· 已连接」可选 |
| 登录/验证码/RSS 点亮 | `setOn:` / tint | 菜单勾选或标题态 |

---

## 4. 数据与迁移

### 4.1 单一 LayoutStore（扩展）

继续使用 `BrowserChromeActionLayoutStore`：

| Key | 变化 |
|-----|------|
| `BrowserChromeActionOrder` | 含窗口项 + 迁入项全序 |
| `BrowserChromeActionHidden` | 默认含全部迁入项 id |

### 4.2 旧地址栏偏好

| 旧 Key | 处理 |
|--------|------|
| `BrowserAddressBarActionOrder` | 迁移一次：把仍有效的 id 接到 Chrome order 末尾（或按旧序插入迁入段）；然后可停止读写 |
| `BrowserAddressBarActionHidden` | 迁移：旧「显示」的项从 Chrome hidden 中移除（用户曾固定的工具钉到标签条）；旧隐藏保持 hidden；`comment`/`pageSettings`/`copyLink` 丢弃 |
| 迁移标记 | 如 `BrowserChromeActionMigratedFromAddressBar` = YES，避免重复迁移 |

无旧键：走 §2.4 默认。

### 4.3 id 清洗

未知 id、已删三项：从 order/hidden 剔除。

---

## 5. 技术设计

### 5.1 模块职责

| 模块 | 变更 |
|------|------|
| `BrowserChromeActionItem` | Catalog 增迁入项；删三项相关常量（若曾存在） |
| `BrowserChromeActionLayoutStore` | 默认 order/hidden；迁移 API；已知 id 集合扩大 |
| `BrowserTabStripChromeActionsView` | 无协议变更；渲染更多可见按钮；角标由 WC 挂载 |
| `BrowserWindowController` | `performChromeAction…` / `wireChromeActionButtons` / `sync…` 覆盖迁入项；角标重装；⋯ 菜单已统一无需分段 |
| `BrowserAddressBarActionGroup` | **退役工具按钮**：可缩成空视图或删除，AddressBarRow 只留 URL；去掉溢出菜单与 pin/hide |
| `BrowserAddressBarRowView` | 布局改为无 ActionGroup 宽（或 width=0） |
| Makefile | 无强制新文件；若抽 `BrowserChromeActionCatalog` 可选用 |

### 5.2 接线策略

```text
wireChromeActionButtons:
  对每个可见 buttonForItemID:
    绑定既有 selector（从原 addressBarActionGroup.*Button 搬家）

reloadChromeActionsFromStore 之后:
  重装 download badge / progress
  重装 notification badge
  刷新 companion 圆点
  刷新 login/captcha/feed 点亮
```

保留 `addressBarActionGroup` 属性短期可变为 nil；所有 `self.addressBarActionGroup.downloadButton` 改为 `chromeActionsView buttonForItemID:download`（注意 hidden 时 button 为 nil，角标只在可见时安装）。

### 5.3 精简 / 透明

- 精简：不藏标签条 Chrome 区 → 钉上的查找/下载仍可用。  
- 透明藏壳：与现 Chrome 图标相同显隐规则。

### 5.4 风险

| # | 风险 | 缓解 |
|---|------|------|
| R1 | 菜单过长（~20 项） | 默认可滚动；后续分组；V1 可接受 |
| R2 | 条上钉太多挤标签 | 用户自控；提醒可拖回 ⋯；后续窄窗自动溢出 |
| R3 | 角标在按钮重建后丢失 | reload 末尾统一 `reinstallChromeActionBadges` |
| R4 | 双偏好不一致 | 一次性迁移 + 停写地址栏键 |
| R5 | 占位项误导 | share/screenshot/extension 未实现则禁用或提示 |
| R6 | 右键「固定到地址栏」入口消失 | 由 ⋯ 图钉取代；文档说明 |

---

## 6. 决策记录

| ID | 议题 | 定稿 |
|----|------|------|
| D1 | 钉上落点 | **标签条 Chrome 区**，不是地址栏 |
| D2 | 地址栏工具按钮 | **移除** |
| D3 | 默认可见 | 迁入项 **全部 hidden**；窗口七项保持可见 |
| D4 | 删除项 | comment / pageSettings / copyLink |
| D5 | 菜单形态 | 延续单一列表 + 图钉 |
| D6 | 偏好 | 扩展 Chrome LayoutStore；迁移后弃用地址栏 order/hidden 读写 |
| D7 | share 等占位 | **保留目录**，未实现则禁用或提示 |
| D8 | 地址栏拖宽 | V1 删除 ActionGroup 拖宽 |
| D9 | 角标 | 仅条上按钮；菜单 V1 可不显示数字角标 |

---

## 7. 验收标准（V1）

- [x] 冷启动：地址栏右侧无工具图标；标签条仍为七 Chrome + ⋯（或用户已有 Chrome 布局）  
- [x] ⋯ 菜单含窗口项 + 全部迁入项；**无**评论 / 页面设置 / 复制链接  
- [x] 迁入项默认图钉为「可固定」；窗口项为「取消固定」（若仍在条上）  
- [x] 固定「下载」「查找」后出现在 ⋯ 左侧；可拖改序、可拖回 ⋯  
- [x] 点菜单「查找 / 下载 / 历史…」与原地址栏按钮行为一致  
- [x] 下载角标在钉上条上时正常；按钮 rebuild 后不丢  
- [x] 精简模式下，钉在标签条的工具仍可用（精简只藏地址栏行，标签条 Chrome 区保留）  
- [x] 旧用户迁移：曾在地址栏显示的工具出现在标签条（从 hidden 移除）  
- [x] `make browser` 通过  

---

## 8. 后续扩展（非 V1）

- 菜单内分组标题（窗口 / 工具）  
- 窄窗自动把次要钉上项挤回 ⋯  
- 菜单行显示角标数字  
- 分享 / 截图 / 扩展真实实现  
- 「恢复默认工具栏」设置项  

---

## 9. 与旧文档关系

| 文档 | 关系 |
|------|------|
| `chrome-actions-customize-design.md` | 本方案为其 **Catalog 扩展 + 地址栏退役**；§1.4「不与地址栏打通」由本需求显式推翻 |
| 各功能设计（查找/下载/互联…） | 入口从 ActionGroup 改为 Chrome Catalog；行为不变 |
| `BrowserAddressBarActionGroup` | V1 后退役工具职责 |
