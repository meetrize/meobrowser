# 图形验证码智能助手（Captcha Assist）— 设计方案

> 目标：为 MeoBrowser 提供**可控、可解释、本地优先**的图形验证码识别与交互能力，与登录助手（Login Assist）协同，覆盖主流验证码形态；通过多模态大模型 + 专用小模型 + 规则引擎组合，自动完成识别、点击、拖拽、计算、拼接、旋转等操作。  
> 状态：**设计草案**（2026-07-16）  
> 关联：[auto-login-design.md](auto-login-design.md) · [login-form-inline-design.md](login-form-inline-design.md) · [anti-bot-session-design.md](anti-bot-session-design.md)（减触发 /sorry/ 等误伤） · [professional-features-roadmap.md](professional-features-roadmap.md) · [companion-protocol.md](companion-protocol.md) · [design.md](design.md)

---

## 1. 方案定位

### 1.1 产品一句话

**验证码助手（Captcha Assist）**：在**用户显式授权**的站点与场景下，检测页面验证码挑战，调用 AI 视觉理解 + 原生交互执行引擎完成验证，并作为 Login Recipe 的可选步骤嵌入登录流程。

与「登录助手填账密 / 收短信 OTP」形成闭环：**账密 → 图形验证 → 短信 OTP → 登录成功**。

### 1.2 要解决的痛点

| 用户场景 | 痛点 | 助手价值 |
|----------|------|----------|
| 国内控制台 / 运维面板登录 | 滑块、点选、拼图反复出现 | 登录 Recipe 可自动续跑，减少人工打断 |
| 内网 / 测试环境 | 自研图形验证码阻碍自动化测试 | 可控环境下「帮点一下」，加速回归 |
| 多因子登录 | 图形验证夹在账密与短信之间 | 与 LoginRunner 步骤链无缝衔接 |
| 专业用户批量巡检 | 多个站点同类 Geetest / 阿里云盾 | 站点级策略 + 厂商适配器复用 |

### 1.3 做什么 / 不做什么

| 做 | 不做 |
|----|------|
| 检测常见验证码 UI（弹层、iframe、内联） | 保证 100% 通过率或绕过所有风控 |
| 多模态模型理解验证码意图并生成操作计划 | 无提示全网静默破解、批量撞库 |
| 原生执行：点击、拖拽、输入、旋转（视能力） | 破解 reCAPTCHA v3 / Turnstile 等**纯行为评分**（无 UI 挑战时） |
| 与 Login Recipe 集成为 `solveCaptcha` 步骤 | 替代用户承担违法爬取 / 薅羊毛责任 |
| 本地 / 自建模型端点优先；API Key 用户自备 | 内置商业打码平台账号、代用户付费 |
| 失败可解释 + 一键切换人工接管 | 隐藏执行过程（默认展示进度与截图摘要） |
| 站点白名单 + 每域开关 + 审计日志（本地） | 上传页面全文/HTML 到云端（默认仅裁剪验证码区域） |

### 1.4 设计原则

1. **人在回路**：默认「询问后执行」；自动破解仅对 Recipe 白名单站点开启。  
2. **可解释**：每次尝试保留裁剪图、模型推理摘要、执行轨迹、成败原因。  
3. **分层求解**：规则 / 厂商适配器优先 → 专用 OCR / 滑块模型 → 通用 VLM 兜底，控制成本与延迟。  
4. **与 Login Assist 同构**：共享 `WKWebView` 注入、ScriptMessage、工具栏 ActionGroup 扩展位。  
5. **合规边界清晰**：产品定位为**个人工作流助手**，文档与 UI 明确禁止用于未授权访问。

### 1.5 与现有「登录助手」的关系

`auto-login-design.md` 曾将滑块 / 图形验证标为「刻意不做」。本方案将其升级为**独立子系统**，原因：

- Login Assist V2 已具备步骤引擎、OTP 等待、Companion 通道；验证码是自然下一步。  
- 专业用户（运维 / 内网测试）需求明确，且可通过白名单控制范围。  
- 独立模块便于合规审查与默认关闭。

```
LoginRecipe.steps 扩展示意：

  fill username → fill password → click submit
       → solveCaptcha (auto|ask|skip)    ← 新增
       → waitOTP → fill otp → submit
```

---

## 2. 互联网典型图形验证码分类

以下按 **交互类型**、**弹出方式**、**出现时机** 三维整理，作为检测器与求解器的分类学基础。

### 2.1 按交互类型（求解策略映射）

| 类型 | 典型形态 | 代表厂商 / 场景 | 主要操作 | 推荐求解层 |
|------|----------|-----------------|----------|------------|
| **A. 文本 OCR** | 扭曲字母数字、干扰线、背景噪点 | 传统论坛、小型 CMS、部分内网 | `type` 输入框 | 专用 OCR（ddddocr）→ VLM |
| **B. 算术 / 逻辑** | 「3 + 5 = ?」「请点击大于 10 的数」 | 简单自建站、老系统 | `evaluate` + `type` / `click` | 规则引擎 → 小 LLM |
| **C. 点选文字** | 「请依次点击：春、夏、秋、冬」 | 网易易盾、部分金融站 | 顺序 `click` 坐标 | VLM 定位 + 坐标映射 |
| **D. 点选图标** | 「点选所有包含红绿灯的图片」 | reCAPTCHA v2、hCaptcha 图片挑战 | 多 `click` 或 `toggle` + 确认 | VLM 目标检测；可选 YOLO 类小模型 |
| **E. 滑块拼图** | 拖动滑块使拼图块对齐缺口 | **极验 Geetest**、阿里云 AWSC、腾讯天御、网易 | `drag` 水平轨迹 | 缺口检测 CV → 轨迹拟合 → 厂商适配 |
| **F. 拼图块交换** | 交换两块完成图片 | 部分活动页、自定义 H5 | `drag` 两点或两次 `click` | VLM + 交换策略 |
| **G. 旋转对齐** | 旋转图片至正向 / 拨盘角度 | 抖音系、部分风控 H5 | `rotate` 或 `drag` 环形 | 角度回归模型 / VLM |
| **H. 轨迹 / 手势** | 按顺序连线、画手势 | 早期支付宝式、部分 APP WebView | `path` 手势 | 模板匹配 + VLM |
| **I. 音频验证** | 听数字 / 单词 | reCAPTCHA 音频 fallback | 播放 + ASR | Whisper 类 ASR → `type` |
| **J. 无 UI 行为分** | 无可见题，仅 token | reCAPTCHA v3、hCaptcha invisible、**Cloudflare Turnstile** | 无（或仅等待 token） | **不纳入 V1**；仅检测并提示人工 |
| **K. 短信 / 邮箱 OTP** | 6 位数字 | 绝大多数国内站 | `type` | 已由 Login Assist + Companion 覆盖 |
| **L. 扫码登录** | 二维码 | 微信 / 支付宝 | 展示 + 手机确认 | Login Assist V3「辅助」非破解 |

### 2.2 按弹出 / 嵌入方式（检测与截图策略）

| 方式 | DOM 特征 | 截图难度 | MeoBrowser 策略 |
|------|----------|----------|-------------------|
| **内联表单字段** | `<input>` 旁 `<img>` 或 canvas | 低 | 元素 bounding rect 裁剪 |
| **页内 Modal** | 全屏遮罩 + 居中面板 | 低 | 遮罩层选择器 + 面板 rect |
| **iframe 嵌入** | `recaptcha` / `geetest` iframe | **高**（跨域不可读 DOM） | **整页或 iframe 视口截图** + 视觉定位；同源 iframe 可读 DOM 时优先 DOM |
| **Shadow DOM** | 自定义 element | 中 | pierce shadow（仅同源）或截图 |
| **新窗口 / popup** | `window.open` | 中 | 监听新 `WKWebView` / 窗口（V2+） |
| **跳转独立验证页** | URL 含 `/captcha`、`/verify` | 低 | URL 规则 + 全页截图 |
| **Canvas 全绘** | 无传统 img | 高 | `canvas.toDataURL`（同源）或截图 |

### 2.3 按出现时机（与 LoginRunner 编排）

| 时机 | 典型流程 | Recipe 钩子 |
|------|----------|-------------|
| **T1. 登录前网关** | 打开登录页即弹 Geetest | `onNavigationFinished` → 先 `solveCaptcha` 再 fill |
| **T2. 提交账密后** | 点击登录 → 弹出滑块 | `afterSubmit` 或 MutationObserver 触发 |
| **T3. 短信前** | 图形验证通过才发 SMS | `solveCaptcha` → `waitOTP` |
| **T4. 短信后** | 填 OTP 后再弹一次 | `waitOTP` 之后插入步骤 |
| **T5. 会话中敏感操作** | 导出、支付、改密 | 独立「验证码助手」按钮，非 Recipe 自动 |
| **T6. 周期性刷新** | 长会话每 N 分钟 | 可选「会话守护」策略（P2） |

### 2.4 国内 vs 国际主流厂商速查

| 厂商 | 常见交互 | 嵌入形式 | 适配优先级 |
|------|----------|----------|------------|
| **极验 Geetest v3/v4** | 滑块、点选、图标 | iframe + JS SDK | **P0（国内最高频）** |
| **阿里云 AWSC / 验证码 2.0** | 滑块、拼图、无痕 | JS + iframe | **P0** |
| **腾讯天御 / 防水墙** | 滑块、文字点选 | JS | **P1** |
| **网易易盾** | 滑块、点选 | JS | **P1** |
| **reCAPTCHA v2** | 图片点选、checkbox | iframe 跨域 | **P1** |
| **hCaptcha** | 同 reCAPTCHA | iframe | **P2** |
| **Cloudflare Turnstile** | 多数无感 | iframe | 检测 + 人工（V1 不解） |
| **自建 canvas** | 任意 | 内联 | VLM 通用管道 |

---

## 3. 总体架构

### 3.1 组件图

```
┌─────────────────────────────────────────────────────────────────┐
│                     BrowserWindowController                      │
│  ┌─────────────────┐    ┌──────────────────────────────────┐  │
│  │ LoginAssist     │───▶│ CaptchaAssistController            │  │
│  │ Controller      │    │  · 工具栏按钮 / 设置 / 白名单       │  │
│  └────────┬────────┘    └───────────────┬──────────────────────┘  │
│           │                              │                          │
│           ▼                              ▼                          │
│  ┌─────────────────┐    ┌──────────────────────────────────┐  │
│  │ LoginRunner     │◀──▶│ CaptchaPipeline                   │  │
│  │ (steps 引擎)    │    │  Detect → Capture → Plan → Act → Verify │
│  └────────┬────────┘    └───────┬──────────────┬─────────────┘  │
│           │                     │              │                    │
│           ▼                     ▼              ▼                    │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ BrowserWebView (WKWebView)                                   │ │
│  │  · CaptchaDetector.js (UserScript)                           │ │
│  │  · CaptchaActor.js (click/drag/type)                         │ │
│  │  · WKScriptMessageHandler: captchaAssist                      │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
           │                     │
           ▼                     ▼
┌──────────────────┐   ┌────────────────────────────────────────┐
│ CaptchaSolver    │   │ CaptchaProviderRegistry                 │
│ Registry         │   │  · GeetestAdapter / AliyunAdapter / …   │
│  · OCR           │   │  · GenericVLMAdapter                    │
│  · SliderCV      │   └────────────────────────────────────────┘
│  · VLM (HTTP)    │              │
└──────────────────┘              ▼
                        ┌─────────────────────┐
                        │ Model Endpoint       │
                        │  · 本地 Ollama       │
                        │  · 用户 API (OpenAI) │
                        │  · 自建 vLLM         │
                        └─────────────────────┘
```

### 3.2 核心流水线（Detect → Capture → Plan → Act → Verify）

| 阶段 | 职责 | 实现要点 |
|------|------|----------|
| **Detect** | 页面是否出现验证码、类型与容器 | JS MutationObserver + 厂商 SDK 指纹（`initGeetest`、`grecaptcha` 等） |
| **Capture** | 获取模型输入 | 元素截图（`WKSnapshotConfiguration`）、canvas export、整页裁切 |
| **Plan** | 输出结构化「操作计划」 | JSON Schema：`{ actions: [{type, target, params}] }` |
| **Act** | 执行操作 | 同源 JS 合成事件；跨域依赖**视口坐标 + 原生鼠标注入**（见 §4.3） |
| **Verify** | 是否通过 | DOM 消失、success class、token 字段有值、URL 变化、Recipe successHints |

### 3.3 操作计划（CaptchaActionPlan）Schema

```json
{
  "version": 1,
  "captchaKind": "slider_puzzle | click_sequence | text_ocr | math | rotate | ...",
  "vendorHint": "geetest_v4 | aliyun | generic",
  "confidence": 0.87,
  "actions": [
    { "type": "wait", "ms": 500 },
    { "type": "click", "target": { "selector": ".geetest_btn" } },
    { "type": "drag", "from": { "x": 42, "y": 380 }, "to": { "x": 215, "y": 380 }, "durationMs": 820, "easing": "human" },
    { "type": "type", "target": { "selector": "#captcha-input" }, "text": "a7kp" },
    { "type": "click", "target": { "selector": "button.submit" } }
  ],
  "verify": {
    "disappearSelector": ".geetest_panel",
    "tokenSelector": "input[name=captcha_token]",
    "maxWaitMs": 8000
  }
}
```

VLM 只负责产出 **Plan**；执行由确定性 `CaptchaActor` 完成，避免模型直接「幻觉点击」不可复现坐标。

### 3.4 求解器分层（Solver Tier）

```
Tier 0  厂商适配器（Geetest/Aliyun/…）— 读 SDK 状态、专用 CV，成功率最高
Tier 1  专用小模型 — ddddocr、滑块缺口 OpenCV、角度分类器
Tier 2  规则 — 算术式解析、正则提取 4–6 位
Tier 3  通用 VLM — GPT-4o / Claude / Qwen-VL / GLM-4V 等，结构化输出 Plan
```

路由逻辑：Detect 给出 `vendorHint` → 优先 Tier 0/1 → 失败再升级 Tier 3（用户可设「仅本地」禁止 Tier 3）。

---

## 4. 技术方案细节

### 4.1 检测层（CaptchaDetector）

**注入时机**：与 `LoginFormDetector` 相同，在 `configureWebViewConfiguration:` 注册 `WKUserScript`（`document-idle`）。

**检测信号（组合打分）**：

| 信号 | 示例 |
|------|------|
| 全局对象 | `window.initGeetest`、`grecaptcha`、`AWSC`、`TencentCaptcha` |
| DOM 关键词 | class/id 含 `captcha`、`geetest`、`nc_`、`yidun` |
| 视觉占位 | 固定比例 canvas、320×40 滑块条 |
| iframe src | `google.com/recaptcha`、`api.geetest.com` |
| 登录助手协同 | `LoginFormDetector` 已标记「提交后出现验证容器」 |

**上报**：`webkit.messageHandlers.captchaAssist.postMessage({ event: "detected", kind, vendor, rect, frame })`

Native 侧去抖：同一 tab 5s 内相同 `kind+vendor` 不重复弹通知。

### 4.2 截图与隐私（CaptureService）

| 模式 | 说明 | 默认 |
|------|------|------|
| **元素裁剪** | 根据 detector 提供的 `getBoundingClientRect` | ✅ |
| **iframe 视口** | 对 iframe element 截图（即使跨域 DOM 不可读） | ✅ |
| **整页** | 仅当元素裁剪失败 | 需用户授权 |
| **Redaction** | 验证码外区域打码后再送模型 | 可选 |

实现：`WKWebView` `takeSnapshotWithConfiguration:completionHandler:`（macOS 11+）或 `layer renderInContext` 回退。

存储：`~/Library/Application Support/MeoBrowser/CaptchaAssist/sessions/<uuid>/`  
保留最近 N 次（默认 20），设置可一键清空。

### 4.3 交互执行（CaptchaActor）— WKWebView 关键难点

| 操作 | 同源 DOM | 跨域 iframe |
|------|----------|-------------|
| click | `element.dispatchEvent` + 聚焦 | 视口坐标 → `CGEvent` 注入到 `BrowserWebView` 窗口 |
| drag | JS `mousedown/mousemove/mouseup` + `PointerEvent` | **原生拖拽**（`CGEventCreateMouseEvent` 轨迹） |
| type | 已有 LoginRunner fill 逻辑 | 通常仍在主文档 input；iframe 内 input 需坐标点击后键入 |
| rotate | 滑块式 drag 或 transform 按钮连点 | 同 drag |

**人类轨迹**：滑块 `durationMs` 800–1500ms，ease-out + 微抖动（参考开源 `trajectory` / 贝塞尔 + 噪声），降低简单 bot 特征。

**限制声明**：跨域 iframe 原生点击依赖 macOS 辅助功能权限（TCC）；首次使用时引导用户在「系统设置 → 隐私与安全性 → 辅助功能」授权 MeoBrowser。

### 4.4 AI / 模型接入（ModelGateway）

统一 HTTP 抽象，支持：

| 后端 | 用途 | 配置 |
|------|------|------|
| **Ollama** | 本地 `llava` / `qwen2-vl` | `baseURL` 默认 `http://127.0.0.1:11434` |
| **OpenAI-compatible** | GPT-4o、Moonshot、DeepSeek-VL 等 | `apiKey` 存 Keychain |
| **自建 vLLM / LM Studio** | 企业内网 | 自定义 URL + model id |

**Prompt 结构（Tier 3）**：

1. 系统：输出必须符合 `CaptchaActionPlan` JSON Schema；只描述可见题面；不确定则 `"confidence": low` 并 `type: "abort"`。  
2. 用户：裁剪图 base64 + DOM 摘要（可选）+ `captchaKind` 提示。  
3. 响应：JSON mode / tool call 解析。

**推荐模型（2026 参考）**：

| 模型 | 优势 | 备注 |
|------|------|------|
| GPT-4o / Claude 3.5 Sonnet | 点选、语义题泛化强 | 需 API，注意图片隐私 |
| Qwen2-VL / Qwen-VL-Max | 中文点选、国内部署 | 可本地 Ollama |
| GLM-4V | 中文场景 | 智谱 API |
| 本地 llava:13b | 零外传 | 复杂题成功率低于云端 |

**非 VLM 组件（建议内置或可插拔）**：

| 组件 | 用途 | 开源参考 |
|------|------|----------|
| **ddddocr** | 扭曲文本 OCR | [sml2h3/ddddocr](https://github.com/sml2h3/ddddocr) |
| **OpenCV 缺口检测** | 滑块 x 偏移 | 模板匹配 / Canny + 轮廓 |
| **Whisper tiny** | 音频验证码 | 本地 whisper.cpp |

Objective-C 侧通过 **Helper CLI / Python 子进程**（`NSTask`）或 **本地 HTTP 微服务** 调用 Python 库，避免重写 OCR；Makefile 可选打包 `Resources/CaptchaAssist/helpers/`。

### 4.5 厂商适配器（Vendor Adapters）

优先实现「**检测 + 专用求解 + 专用轨迹**」三板斧，减少通用 VLM 调用成本。

#### Geetest v3/v4（P0）

- 检测：`initGeetest`、`geetest_` 前缀 class。  
- 滑块：背景图 + 滑块图 → OpenCV 缺口 x；或通过 OCR 识别缺口位置。  
- 点选：VLM 返回文字坐标，映射到 `.geetest_item` 或绝对坐标。  
- 开源参考：[Geetest 逆向社区脚本](https://github.com/search?q=geetest+slider)（仅作协议研究，产品内实现须合规）

#### 阿里云 AWSC（P0）

- 检测：`AWSC`、`uab`、`nc_` 类名。  
- 与 Geetest 类似滑块 CV；注意 UA 与 cookie 绑定。

#### reCAPTCHA v2 图片题（P1）

- 跨域 iframe：截图 + 网格切分（3×3 / 4×4）→ VLM 逐格或多选 JSON。  
- **不提供** audio 自动破解作为默认（合规敏感）；可 P2 作为可选项。

### 4.6 与 LoginRunner 集成

扩展 `LoginStep`：

```text
LoginStep
  ...
  solveCaptcha: {
    mode: ask | auto | skip
    maxAttempts: 3
    solverProfile: "balanced" | "local_only" | "vendor_first"
    onFail: pause | abort | manual
  }
```

`LoginRunner` 在执行到该步时：

1. 调用 `[CaptchaAssistController waitForCaptchaAndSolve:...]`  
2. 阻塞直至 `Verify` 成功 / 超时 / 用户取消  
3. 继续后续 `waitOTP` 等步骤

`LoginFormDetector` 扩展：检测到 captcha 字段时，内联按钮显示「验证码助手」而非盲目自动提交。

---

## 5. 用户体验与交互

### 5.1 Chrome 落点

```
[ ← → ↻ ] [ ========== 地址栏 ========== ] [ ↓  key  shield.checkered  … ]
                                                    ↑
                                         验证码助手（检测到挑战时点亮）
```

| 状态 | 行为 |
|------|------|
| 无检测 | 灰色；tooltip「未检测到验证码」 |
| 检测到挑战 | **点亮**；单击打开 Captcha Assist 面板 |
| 执行中 | 进度：检测 → 分析 → 执行 → 验证；可 Esc 取消 |
| 成功 | 短暂 ✓；若来自 LoginRunner 则自动续跑 |
| 失败 | 展示原因 + 「重试 / 人工操作 / 跳过（Recipe 允许时）」 |

快捷键建议：⌘⇧C（Captcha）；与 ⌘⇧L（Login）并列。

### 5.2 Captcha Assist 面板（HUD / 侧栏）

| 区块 | 内容 |
|------|------|
| 预览 | 本次裁剪图（可展开） |
| 判定 | 类型、厂商、置信度 |
| 计划 | 人类可读步骤列表（「拖动滑块约 173px」） |
| 控制 | 立即求解 / 只看不动 / 人工接管 |
| 历史 | 本 tab 最近 5 次尝试 |

**人工接管**：面板最小化，不再注入事件；用户手动完成后点「我已完成」触发 Verify。

### 5.3 设置（Captcha Assist 分区）

| 区块 | 项 |
|------|-----|
| 总开关 | 启用验证码助手（默认 **关**） |
| 站点白名单 | origin 列表 + 继承 Login Recipe |
| 模型 | 端点类型、模型名、API Key（Keychain）、「仅本地」 |
| 求解策略 | 厂商优先 / 平衡 / 总是 VLM |
| 隐私 | 是否允许整页截图、日志保留天数 |
| 权限 | 辅助功能授权状态、跳转系统设置 |
| 高级 | Helper 路径、Tier 开关、单步超时 |

输入框使用 `SBTextField` / `SBSecureTextField`（API Key）。

### 5.4 默认策略（推荐）

| 场景 | 行为 |
|------|------|
| 首次启用 | 仅「询问后执行」 |
| 已配置 Login Recipe 且用户勾选 | 该站 `solveCaptcha: auto` |
| 未在白名单 | 只检测 + 提示，不自动调模型 |
| 发送图片到云端 API | 弹窗二次确认 + Keychain 存 consent |

---

## 6. 可借鉴开源与商业产品

### 6.1 开源（架构 / 算法 / 参数）

| 项目 | 可借鉴点 | 直接使用 |
|------|----------|----------|
| [ddddocr](https://github.com/sml2h3/ddddocr) | 中文扭曲字 OCR | ✅ Helper 子进程 |
| [opencv/opencv](https://github.com/opencv/opencv) | 滑块缺口、模板匹配 | ✅ 本地 CLI |
| [berstend/puppeteer-extra-plugin-recaptcha](https://github.com/berstend/puppeteer-extra/tree/master/packages/puppeteer-extra-plugin-recaptcha) | reCAPTCHA 流程状态机 | 思路参考；需改写为 WKWebView |
| [yoori/yolo-captcha](https://github.com/search?q=yolo+captcha) | 图标点选检测 | 可选本地 ONNX |
| [g1879/DrissionPage](https://github.com/g1879/DrissionPage) | 国内站自动化 + 验证码处理范例 | 思路参考 |
| [browser-use/browser-use](https://github.com/browser-use/browser-use) | VLM 驱动浏览器 Agent 循环 | Plan/Act 循环参考 |
| [playwright](https://github.com/microsoft/playwright) | 可靠 drag、iframe 坐标 | 不可直接嵌入；借鉴轨迹 API |
| [2captcha/2captcha-python](https://github.com/2captcha/2captcha-python) | 商业打码 API 协议 | 可选「用户自带 API Key」插件 |

### 6.2 商业 / SaaS（用户可选接入，产品不代收）

| 服务 | 类型 | 集成方式 |
|------|------|----------|
| 2Captcha / Anti-Captcha | 人工 + 机器学习混合 | `CaptchaProvider` 插件 |
| CapSolver | 滑块、Geetest 等 | 同上 |
| 打码兔、若快（国内） | OCR / 滑块 | 同上，注意合规 |

产品立场：**内置协议适配，密钥用户自填**；默认不开启。

### 6.3 学术 / 数据集（模型训练可选）

- CAPTCHA 分类与 OCR：CN-CAPTCHA、CAPTCHA-generator  
- 滑块：合成缺口数据 + 真实 Geetest 样本（仅内部测试环境采集）

---

## 7. 目录与模块规划

```
SimpleBrowser/CaptchaAssist/
  CaptchaAssistController.m/h      # 总控、工具栏、白名单
  CaptchaPipeline.m/h              # Detect→Verify 状态机
  CaptchaCaptureService.m/h        # 截图与缓存
  CaptchaActor.m/h                 # 执行 Plan（JS + CGEvent）
  CaptchaModelGateway.m/h          # VLM HTTP 客户端
  CaptchaSolverRegistry.m/h        # Tier 路由
  CaptchaSessionLog.m/h            # 本地审计
  Adapters/
    GeetestCaptchaAdapter.m/h
    AliyunCaptchaAdapter.m/h
    GenericVLMCaptchaAdapter.m/h
    MathCaptchaAdapter.m/h
  JS/
    captcha-detector.js            # UserScript
    captcha-actor.js               # 同源 DOM 操作
  Models/
    CaptchaActionPlan.h            # JSON 模型（可 codegen）

Resources/CaptchaAssist/
  helpers/
    captcha_helper.py              # ddddocr + opencv 入口
  schemas/
    captcha-action-plan.schema.json
```

Login Assist 改动：

- `LoginRecipe` / `LoginStep` 增加 `solveCaptcha`  
- `LoginRunner` 回调 Captcha Pipeline  
- `LoginFormDetector` 上报 captcha 信号

---

## 8. 分阶段交付

| 阶段 | 范围 | 验收 |
|------|------|------|
| **CA-0 骨架** | 检测脚本 + 面板 UI + 截图 + 日志；不解题 | 访问 Geetest demo 页能点亮按钮并截图 |
| **CA-1 文本/算术** | ddddocr + 规则引擎 + type | 内网测试页 OCR 成功率 > 80% |
| **CA-2 滑块** | OpenCV 缺口 + 人类轨迹 + Geetest/Aliyun 适配器 v1 | 官方 demo 滑块通过（允许重试） |
| **CA-3 VLM 通用** | ModelGateway + GenericVLMAdapter + Plan/Act | 点选类 demo 可解；失败可解释 |
| **CA-4 Login 集成** | `solveCaptcha` 步骤 + Recipe 设置 | 账密 → 滑块 → OTP 全自动一条 Recipe |
| **CA-5 跨域强化** | CGEvent 注入 + 辅助功能引导 | reCAPTCHA v2 图片题基本可用 |
| **CA-6 可选** | 用户自带 2Captcha、音频 ASR、旋转验证码 | 设置中可启用 |

建议另附 [captcha-assist-development-plan.md](captcha-assist-development-plan.md)（CA-0～CA-6 任务拆解）。**CA-0 骨架已落地**（检测 + 截图 + 面板，2026-07-16）。

---

## 9. 风险、合规与对策

| 风险 | 对策 |
|------|------|
| 违反站点 ToS / 法律 | 白名单 + 显式授权 + 文档声明；默认关 |
| 模型误判导致账号锁定 | 最大尝试次数、指数退避、失败停手 |
| 隐私泄露（截图上传） | 裁剪默认、本地优先、Keychain、会话本地加密 |
| WKWebView 跨域无法 DOM | 截图 + 原生坐标；降低 reCAPTCHA 预期 |
| 厂商 SDK 频繁升级 | 适配器版本号 + Tier 3 兜底 + 社区反馈渠道 |
| 辅助功能权限被拒 | 降级为仅同源 + 人工接管 |
| 成本（VLM API） | Tier 0/1 优先；每域每日配额 |

---

## 10. 替代方案与演进

### 10.1 更「完美」的长期方向

1. **验证码指纹库**：用户可选匿名上报「厂商 + DOM 指纹 + 成功 Plan 模板」（不含页面 URL 全文），形成社区适配包。  
2. **On-device 小 VLM**：Apple Silicon 上 Core ML 量化 Qwen2-VL-2B，零外传。  
3. **与 Companion 协同**：手机端完成部分厂商「手机盾」验证，Mac 只收 token（类似 OTP 通道扩展）。  
4. **Recipe  marketplace（私有）**：团队内共享 Geetest 适配参数，不进公网。

### 10.2 若范围需收缩

最小可用产品（MVP）= **CA-0 + CA-1 + CA-2 + 仅白名单 Geetest/内网 OCR**，暂不接 reCAPTCHA 与商业打码。

### 10.3 若范围需扩大

- 独立「自动化实验室」窗口：Playwright 式录制 + Captcha Assist（仍不合并进主浏览器的默认路径）。  
- Safari Web Extension 不可行（MeoBrowser 走原生 WKWebView 更深集成）。

---

## 11. 附录

### 11.1 检测器 JS 指纹示例（节选）

```javascript
(function () {
  const vendors = [];
  if (window.initGeetest) vendors.push({ id: 'geetest', kind: 'slider_or_click' });
  if (window.grecaptcha) vendors.push({ id: 'recaptcha', kind: 'checkbox_or_image' });
  if (window.AWSC) vendors.push({ id: 'aliyun', kind: 'slider' });
  if (document.querySelector('.yidun, .yidun_panel')) vendors.push({ id: 'yidun', kind: 'slider_or_click' });
  // postMessage to native...
})();
```

### 11.2 VLM Tool Definition 名称建议

`meobrowser_propose_captcha_plan` — 强制 JSON Schema 输出，便于与 Login Assist 共用 tool 调用基础设施（若未来引入统一 Agent 层）。

### 11.3 相关测试页

| 用途 | 来源 |
|------|------|
| Geetest demo | 极验官方 demo 页 |
| 内网 OCR | 自建 `captcha-assist-test.html`（同 `login-assist-test.html` 模式） |
| reCAPTCHA | Google 官方 test keys |

---

## 12. 文档修订

| 日期 | 说明 |
|------|------|
| 2026-07-16 | 初稿：分类学、架构、Login Assist 集成、开源参考、分阶段 CA-0～CA-6 |
