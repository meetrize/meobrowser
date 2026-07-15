# 站点登录助手 — 开发计划

> 基于 [auto-login-design.md](auto-login-design.md) 的分阶段实施计划。  
> 前置条件：多标签 + ActionGroup（下载按钮接线模式）+ 设置窗（`BrowserSettingsWindowController`）可用；文本输入用 SBKit。  
> **状态：未开工（计划草案 2026-07-15）。**

---

## 行为定稿（相对设计稿的默认取值）

| 项 | 定稿 |
|----|------|
| 产品名（UI） | **登录助手** |
| 自动登录 | 默认 **关**；仅 Recipe 级开关 |
| 凭证互通 | V1 **不**接系统「密码」App / iCloud 钥匙串同步 |
| 多账号同 host | V1 允许多 Recipe；工具栏单击用「默认」Recipe，长按/菜单选其他 |
| 清除网站数据 | **不**删除 Recipe / Keychain |
| Companion（V2） | 先做 Mac 端「手动粘贴 / 剪贴板 OTP」管线，再接 Companion |
| 中继 | V2 文档提供自建模板；不做强制公有托管 |
| 快捷键 | ⌘⇧L 一键登录；设置走现有 ⌘, 入口内分区或子窗 |

未决项若变更，先改设计稿 §9，再回写本表。

---

## 总览

| 阶段 | 名称 | 对应设计 | 状态 | 产出 |
|------|------|----------|------|------|
| Phase LA-0 | 数据层 | §3.1 / §3.3 | 未开始 | Recipe JSON + Keychain |
| Phase LA-1 | 一键执行 MVP | §4.1 / §5 | 未开始 | Runner + 工具栏点亮 + ⌘⇧L |
| Phase LA-2 | 设置与点选拾取 | §2.2 | 未开始 | 设置 UI + 选择器拾取 |
| Phase LA-3 | 自动登录与 V1 验收 | §2.1 / §7 V1 | 未开始 | 自动策略、防抖、验收通过 |
| Phase LA-4 | TOTP（可选插入） | §8 建议 | 未开始 | 本地算码 step，无 Companion |
| Phase LA-5 | 短信 OTP | §4.2 / §7 V2 | 未开始 | waitOTP + 通道 + Companion 最小闭环 |
| Phase LA-6 | 二维码辅助 | §4.3 / §7 V3 | 未开始 | 检测 + 传图/深链 + 状态 HUD |
| Phase LA-7 | 联调收尾 | — | 未开始 | 文档 / acceptance / 路线图勾选 |

建议节奏：先完整走通 **LA-0～LA-3（V1）** 再开 LA-5/6；LA-4 可在 V1 验收后、短信之前插入。

---

## Phase LA-0：数据层

**目标**：可持久化的 Recipe 与凭证 API，无 UI、不执行页面脚本。

### 任务清单

- [ ] **0.1** 创建目录 `SimpleBrowser/LoginAssist/`
- [ ] **0.2** `LoginRecipe` / `LoginStep` 模型（编解码 JSON；`mode` 先支持 `password`）
- [ ] **0.3** `LoginRecipeStore`：读写 `Application Support/MeoBrowser/LoginAssist/recipes.json`
- [ ] **0.4** 匹配 API：`recipesMatchingURL:`（host；可选 pathPrefix）
- [ ] **0.5** `LoginCredentialStore`：Keychain 读写（username / password / phone；service=`MeoBrowser.LoginAssist`）
- [ ] **0.6** 删除 Recipe 时同步删除对应 Keychain 项
- [ ] **0.7** 单元级自测或小型测试页数据：写入 → 读回 → 匹配 host
- [ ] **0.8** Makefile：加入源文件与 `-ILoginAssist`

### 完成标准

- 无窗口也能在调试代码里创建 Recipe、存密码、按 URL 命中。  
- 日志中无明文密码。

---

## Phase LA-1：一键执行 MVP

**目标**：已有 Recipe 时工具栏可点，对当前页执行 fill + click/enter。

### 任务清单

#### 1A — 执行引擎

- [ ] **1.1** `LoginRunner`：按 `steps` 顺序执行；支持 `waitFor` / `fill` / `click` / `pressEnter` / `pauseMs`
- [ ] **1.2** JS 填充时派发 `input` / `change`（及必要的键盘事件）
- [ ] **1.3** 失败回调：选择器未命中、超时、WebView 不可用 → 可读错误文案
- [ ] **1.4** 成功 hint（V1 最小）：离开 match URL 或自定义 `jsPredicate` 可选

#### 1B — 控制器与 chrome

- [ ] **1.5** `LoginAssistController`：根据当前 tab URL 更新按钮可用态
- [ ] **1.6** ActionGroup 新增 `loginAssist`（SF Symbol 如 `key.horizontal`）；接线 `oneClickLogin:`
- [ ] **1.7** 菜单或全局快捷键 ⌘⇧L → 当前页一键登录
- [ ] **1.8** 执行中禁用按钮 / 简短转圈；同 tab 防重入
- [ ] **1.9** 导航回调（`didFinish` / `didCommit`）刷新匹配态

#### 1C — 联调用配置

- [ ] **1.10** 提供本地静态测试页（或文档内 HTML）含标准 username/password/submit，便于手工验收
- [ ] **1.11** 开发期可用临时代码或调试菜单写入第一条 Recipe（正式设置在 LA-2）

### 完成标准

- 对测试页：点亮 → 一键 → 表单提交成功。  
- 无匹配 Recipe 时按钮不可用（或灰态 + tooltip）。

---

## Phase LA-2：设置与点选拾取

**目标**：用户可完成本地管理 Recipe，无需改代码。

### 任务清单

#### 2A — 设置 UI

- [ ] **2.1** `BrowserLoginAssistSettingsWindowController`（或嵌入现有设置分区）
- [ ] **2.2** 列表：名称、host、mode、自动登录开关、默认账号标记
- [ ] **2.3** 编辑表：match、用户名/密码（`SBTextField` / `SBSecureTextField`）、各 step 选择器、提交方式
- [ ] **2.4** 删除 / 设为默认；文案说明与「清除网站数据」边界
- [ ] **2.5** 应用菜单「设置」内增加入口（或设置窗内 Tab/分段）

#### 2B — 点选拾取

- [ ] **2.6** 「从当前页拾取」：向页面注入临时脚本，点击元素后回传唯一 CSS（优先 `id` / `name` / `autocomplete`）
- [ ] **2.7** `WKScriptMessageHandler` 接收拾取结果写入编辑表
- [ ] **2.8** 拾取结束退出页面高亮态；Esc 取消

### 完成标准

- 新用户仅通过 UI 能为测试站建 Recipe 并一键登录。  
- 输入控件符合 SBKit 规范。

---

## Phase LA-3：自动登录与 V1 验收

**目标**：可选自动登录稳健可用；V1 达到设计稿验收。

### 任务清单

- [ ] **3.1** Recipe.`autoLogin`：匹配登录页且未见成功 hint 时，短延迟后自动 `LoginRunner`
- [ ] **3.2** 防抖：同 tab + 同 Recipe 在 N 秒内不重复；Esc 可取消待执行
- [ ] **3.3** 可选：执行前 `LAContext`（Touch ID）——至少做设置开关骨架，实现可列「安全增强」
- [ ] **3.4** 失败对话框：「打开编辑」跳转对应 Recipe
- [ ] **3.5** 多 Recipe：长按或菜单选择账号（V1 至少两种入口之一）
- [ ] **3.6** 可选挂钩 Launchpad：快捷方式「打开后一键登录」（时间盒，可延后）
- [ ] **3.7** `make clean && make browser`；`-Wall -Wextra` 无新增警告
- [ ] **3.8** 手动验收（见下方 V1 清单）
- [ ] **3.9** 更新设计稿状态为「V1 已实现」；本计划 LA-0～3 勾选完成
- [ ] **3.10** [acceptance.md](acceptance.md) 增加登录助手 V1 条目

### V1 验收清单

- [ ] 测试页：创建 Recipe → 按钮点亮 → ⌘⇧L / 单击登录成功
- [ ] 密码仅存 Keychain；清除网站数据后 Recipe 仍在，Cookie 清掉后可再一键登入
- [ ] 错误选择器：失败提示可读，可从提示进编辑
- [ ] 自动登录开：进入匹配页自动提交；关：绝不自动
- [ ] 自动登录防抖：连续刷新不形成死循环
- [ ] SPA 晚出表单：`waitFor` 在约定超时内仍能填
- [ ] 无障碍：按钮有 tooltip；设置窗可键盘操作核心控件

### 发布检查（V1）

```bash
make clean && make browser && make verify
make run-browser
```

---

## Phase LA-4：TOTP（可选插入）

**目标**：本地生成 OTP，无手机 Companion；服务专业用户控制台场景。

### 任务清单

- [ ] **4.1** Keychain 增加 `totpSecret`（Base32）；设置 UI「二次验证（TOTP）」
- [ ] **4.2** `LoginStep` 增加 `fillTotp`（算法默认 SHA1 / 30s / 6 位）
- [ ] **4.3** Runner 在填密码后填 TOTP 再提交
- [ ] **4.4** 验收：对接任一自建或标准 TOTP 测试站

**若不做**：勾选取消并在设计稿注明「延后」。

---

## Phase LA-5：短信 OTP（V2）

**目标**：`waitOTP` 管线打通；Companion 或降级粘贴均能填码。

### 任务清单

#### 5A — 浏览器侧管线（可先于 App）

- [ ] **5.1** Recipe `mode` / steps 支持 `waitOTP` + 手机号 fill
- [ ] **5.2** `CompanionChannel` 协议草稿：配对、推送 OTP（码、时间戳、发件人 hash）
- [ ] **5.3** Mac 降级：监听剪贴板 / 设置页「粘贴验证码」→ 同一填码出口
- [ ] **5.4** TTL（默认 120s）与一次性消费；超时失败提示

#### 5B — Companion 最小闭环

- [ ] **5.5** 选定通道：局域网 Bonjour **或** 用户自建 WebSocket/Worker（二选一先落地）
- [ ] **5.6** Android 最小 App：读通知/短信 → 解析 4～8 位码 → 加密发送
- [ ] **5.7** iOS：文档写明降级路径（分享到 App / 粘贴）；完整短信权限不做硬依赖
- [ ] **5.8** 设置页：配对二维码/配对码、连接状态、注销设备
- [ ] **5.9** 隐私：默认不上传短信全文；设置中明示

### V2 验收清单

- [ ] 测试站：填手机号 → 点发送 →（模拟或真机推码）→ 自动填入并提交
- [ ] 过期码不填；重复码不二次消费
- [ ] 无 Companion 时，手动粘贴仍可完成同流程
- [ ] 断连时 UI 明示，不无声失败

---

## Phase LA-6：二维码辅助（V3）

**目标**：减少对准屏幕；桌面与手机状态可感知。

### 任务清单

- [ ] **6.1** Recipe 策略：`qr_assisted`；DOM 选择器优先
- [ ] **6.2** DOM 提取 QR 图；失败则区域截图 + 本地 QR 解码
- [ ] **6.3** S1：经 Companion 通道把图推到手机大图展示
- [ ] **6.4** S2：若载荷为 URL，手机可直接打开（设置中可选）
- [ ] **6.5** S5：桌面 HUD——等待确认 / 成功 / 过期（QR 刷新后自动再推可选）
- [ ] **6.6** 明确不做：滑块、无障碍模拟点手机「同意」
- [ ] **6.7** 手工验收 1～2 个真实扫码登录站（失败则文档记录局限）

### V3 验收清单

- [ ] 登录页出现 QR 后，手机 Companion 在数秒内收到图或深链
- [ ] 用户在手机完成确认后，桌面能提示成功或超时
- [ ] 无 Companion 时桌面仍显示「请扫码」状态，不崩溃

---

## Phase LA-7：联调收尾

**目标**：文档与产品状态一致。

### 任务清单

- [ ] **7.1** 各已交付阶段勾选完成；总览表状态更新
- [ ] **7.2** 更新 [auto-login-design.md](auto-login-design.md) 版本表与「状态」行
- [ ] **7.3** 更新 [professional-features-roadmap.md](professional-features-roadmap.md) 相关 checkbox（若有里程碑条目）
- [ ] **7.4** [docs/README.md](../README.md) 索引保持有效
- [ ] **7.5** [acceptance.md](acceptance.md) 按 V1/V2/V3 分段记录

---

## 建议实现文件

```text
SimpleBrowser/LoginAssist/
  LoginRecipe.h/.m
  LoginRecipeStore.h/.m
  LoginCredentialStore.h/.m
  LoginRunner.h/.m
  LoginAssistController.h/.m
  BrowserLoginAssistSettingsWindowController.h/.m
  LoginElementPicker.js          # 或字符串内嵌
  Companion/                     # LA-5+
    CompanionChannel.h/.m
    CompanionBonjour*.m
    CompanionRelayClient.m
  QR/                            # LA-6
    LoginQRDetector.h/.m

SimpleBrowser/Resources/LoginAssist/
  login-assist-test.html         # 本地验收页（可选 file:// 或内嵌）
```

集成点：

| 现有文件 | 改动 |
|----------|------|
| `BrowserAddressBarActionGroup*`（或等价目录） | 增加 `loginAssist` 项 |
| `BrowserWindowController.m` | 持有 Controller；导航回调；快捷键 |
| `BrowserMenus` / `AppDelegate` | 设置入口、⌘⇧L |
| `WKWebViewConfiguration` 配置处 | UserScript / message handler |
| `Makefile` | 编译与头文件路径 |

---

## 风险与时间盒

| 风险 | 缓解 | 时间盒建议 |
|------|------|------------|
| 站点禁用程序化填表 | 事件派发 + 失败可编辑；不承诺全站 | LA-1 测 2 站即收 |
| SPA 时序 | waitFor / 轮询 | LA-1～3 |
| Keychain 权限弹窗 | 首次使用说明；主线程调用规范 | LA-0 |
| Companion 工作量大 | LA-5A 粘贴管线可单独交付 | V2 砍范围优先 Mac |
| QR 站点差异大 | DOM 选择器 per-recipe；解码仅兜底 | LA-6 限定样本站 |
| 与「密码管理器」范围膨胀 | 严格按 Recipe；拒做全网启发式 | 全程 |

粗估（一人、含联调，仅供排期）：

| 阶段 | 粗估 |
|------|------|
| LA-0～LA-3（V1） | 1.5～2.5 周 |
| LA-4 TOTP | 2～4 天 |
| LA-5（含最小 Android） | 2～4 周 |
| LA-6 | 1.5～2.5 周 |

---

## 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：LA-0～LA-7 任务拆分、验收清单与文件落点 |
