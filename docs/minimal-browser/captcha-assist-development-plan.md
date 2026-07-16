# 图形验证码智能助手 — 开发计划

> 基于 [captcha-assist-design.md](captcha-assist-design.md) 的分阶段实施计划。  
> 前置条件：多标签 + ActionGroup + Login Assist（`LoginRunner` / ScriptMessage 代理）可用；文本输入用 SBKit。  
> **状态：CA-0 骨架已落地（2026-07-16）；CA-1～CA-6 未开工。**  
> 关联：[auto-login-design.md](auto-login-design.md) · [auto-login-development-plan.md](auto-login-development-plan.md) · [professional-features-roadmap.md](professional-features-roadmap.md)

---

## 行为定稿（相对设计稿的默认取值）

| 项 | 定稿 |
|----|------|
| 产品名（UI） | **验证码助手** |
| 总开关 | 默认 **关**（不点亮工具栏）；检测脚本始终注入，避免开关后须重建 `WKWebViewConfiguration` |
| 自动求解 | 默认 **询问后执行**；仅白名单 origin 可勾选「自动」 |
| 模型默认 | 优先本地 Ollama；云端 API Key 存 Keychain，首次上传弹二次确认 |
| 求解分层 | 厂商适配器 → 专用 OCR/CV → 规则 → VLM 兜底 |
| 跨域 iframe | CA-0～CA-4 以截图 + 同源 DOM 为主；CA-5 再上 CGEvent |
| 商业打码 | 仅用户自备 API Key；产品不内置账号 |
| 快捷键 | ⌘⇧C 打开面板 / 触发截图；设置走「文件 → 验证码助手…」 |
| 与登录助手 | CA-4 才扩展 `LoginStep.solveCaptcha`；此前独立运行 |

未决项若变更，先改设计稿，再回写本表。

---

## 总览

| 阶段 | 名称 | 对应设计 | 状态 | 产出 |
|------|------|----------|------|------|
| Phase CA-0 | 检测 + 截图骨架 | §3 / §5 / §8 | **完成** | Detector + Capture + 面板 + 日志；不解题 |
| Phase CA-1 | 文本 / 算术 | §2.1 A–B / §4.4 | 未开始 | ddddocr Helper + type |
| Phase CA-2 | 滑块 | §2.1 E / §4.5 | 未开始 | OpenCV 缺口 + 轨迹 + Geetest/Aliyun |
| Phase CA-3 | VLM 通用 | §3.3 / §4.4 | 未开始 | ModelGateway + Plan/Act |
| Phase CA-4 | Login 集成 | §1.5 / §4.6 | 未开始 | `solveCaptcha` 步骤 |
| Phase CA-5 | 跨域强化 | §4.3 | 未开始 | CGEvent + 辅助功能引导 |
| Phase CA-6 | 可选增强 | §6.2 / §10 | 未开始 | 2Captcha、ASR、旋转 |

建议节奏：CA-0 可独立交付演示；MVP = **CA-0 + CA-1 + CA-2**；接登录闭环以 **CA-4** 为门禁。

---

## Phase CA-0：检测 + 截图骨架

**目标**：能检测常见验证码指纹、点亮工具栏、裁剪/整页截图、本地会话日志与 HUD 面板；**不调用模型、不执行解题操作**。

### 任务清单

#### 0A — 模块与数据

- [x] **0.1** 创建目录 `SimpleBrowser/CaptchaAssist/`
- [x] **0.2** `CaptchaDetection` 模型：`vendor` / `kind` / `confidence` / `rect` / `frameHint` / `pageURL` / `detectedAt`
- [x] **0.3** `CaptchaAssistPreferences`：总开关（默认关）、最近会话保留条数
- [x] **0.4** `CaptchaSessionLog`：写入 `Application Support/MeoBrowser/CaptchaAssist/sessions/<uuid>/`（meta.json + image.png）
- [x] **0.5** 测试页 `captcha-assist-test.html` 入 App Resources（模拟 Geetest / OCR / 算术 DOM）

#### 0B — 检测与截图

- [x] **0.6** `CaptchaDetector`：`WKUserScript` + `WKScriptMessageHandler`（name=`captchaAssist`）；厂商指纹 + DOM 关键词
- [x] **0.7** 去抖：同 tab 同一 `vendor+kind` 5s 内不重复上报点亮
- [x] **0.8** `CaptchaCaptureService`：`takeSnapshotWithConfiguration:`；支持整页与按 rect 裁剪
- [x] **0.9** 总开关控制点亮；检测脚本始终注入（避免开关后须重建 configuration）

#### 0C — Chrome 与面板

- [x] **0.10** ActionGroup 增加 `captchaAssist`（`checkerboard.rectangle`）
- [x] **0.11** `CaptchaAssistController`：点亮态、tooltip、单击打开面板
- [x] **0.12** `CaptchaAssistPanel`：预览图、类型/厂商、置信度、「立即截图」「清空检测」
- [x] **0.13** 文件菜单：验证码助手（⌘⇧C）
- [x] **0.14** 导航 `didFinish` 刷新检测态；切换 tab 同步按钮
- [x] **0.15** Makefile：源文件、`-ICaptchaAssist`、拷贝测试页
- [x] **0.16** `make browser`；设计稿 / 本计划勾选 CA-0

### 完成标准

- 打开 `captcha-assist-test.html`（助手已启用）：工具栏点亮，面板显示检测到的 vendor/kind。  
- 点「立即截图」：Application Support 下出现 session 目录与 PNG。  
- 总开关关闭：不注入有效检测、按钮灰态。  
- **不**调用任何外部模型或商业打码 API。

### 手测清单

- [ ] file:// 测试页：模拟 Geetest / OCR 区块均能检测  
- [ ] 开关关 → 刷新页 → 不点亮  
- [ ] 截图文件可在 Finder 打开  
- [ ] 切换标签后按钮状态跟随当前 tab  

---

## Phase CA-1：文本 OCR / 算术

**目标**：对简单文本验证码与算术题完成识别并填入输入框。

### 任务清单

- [ ] **1.1** `Resources/CaptchaAssist/helpers/captcha_helper.py`：ddddocr / 算术解析 CLI  
- [ ] **1.2** `CaptchaHelperBridge`：`NSTask` 调 Helper，超时与错误映射  
- [ ] **1.3** `MathCaptchaAdapter`：解析「a ± b = ?」  
- [ ] **1.4** `OCRCaptchaAdapter`：图 → 文本  
- [ ] **1.5** `CaptchaActor`（最小）：同源 `type` + 派发 `input`/`change`（可复用 LoginRunner fill 片段）  
- [ ] **1.6** Pipeline：Detect → Capture → Tier1/2 Plan → Act → Verify（输入框有值 / 提交按钮可点）  
- [ ] **1.7** 面板增加「求解（OCR/算术）」按钮；失败可读错误  
- [ ] **1.8** 测试页增加可提交的 OCR / 算术样例与期望答案  

### 完成标准

- 测试页 OCR：成功率 ≥ 80%（固定样例图可重复）。  
- 算术题：规则引擎 100% 通过固定用例。  
- Helper 缺失时提示安装路径，不崩溃。

---

## Phase CA-2：滑块拼图

**目标**：Geetest / 阿里云类滑块在 demo 或测试页可拖过（允许重试）。

### 任务清单

- [ ] **2.1** Helper 扩展：OpenCV 缺口 x 偏移  
- [ ] **2.2** 人类轨迹生成（时长 800–1500ms、缓动 + 微抖动）  
- [ ] **2.3** `CaptchaActor`：`drag`（同源 Pointer/Mouse 事件）  
- [ ] **2.4** `GeetestCaptchaAdapter` v1  
- [ ] **2.5** `AliyunCaptchaAdapter` v1（可与 Geetest 共享 CV）  
- [ ] **2.6** Verify：面板消失 / success class / token 输入有值  
- [ ] **2.7** `maxAttempts`（默认 3）+ 退避  

### 完成标准

- 官方或自建滑块 demo：3 次内至少 1 次通过。  
- 失败时面板展示「缺口检测失败 / 轨迹被拒」等可区分原因。

---

## Phase CA-3：VLM 通用管道

**目标**：点选文字 / 图标类通过通用 VLM 输出 `CaptchaActionPlan` 并执行。

### 任务清单

- [ ] **3.1** `captcha-action-plan.schema.json` + ObjC 解析模型  
- [ ] **3.2** `CaptchaModelGateway`：Ollama / OpenAI-compatible  
- [ ] **3.3** API Key Keychain；「仅本地」开关  
- [ ] **3.4** `GenericVLMCaptchaAdapter`：图 + kind → Plan  
- [ ] **3.5** Actor：多点 `click` 顺序执行  
- [ ] **3.6** 首次云端上传二次确认 + 本地 consent  
- [ ] **3.7** SolverRegistry 路由：厂商 → OCR/CV → VLM  
- [ ] **3.8** 设置窗：端点、模型名、Key、策略  

### 完成标准

- 测试页点选序列：VLM（或 mock Plan）可完成点击并 Verify。  
- 无 Key / Ollama 不可达时错误文案明确。  
- 会话日志含 Plan JSON（不含 API Key）。

---

## Phase CA-4：Login Assist 集成

**目标**：Recipe 可编排「账密 → 验证码 → OTP」全自动（白名单 + 询问/自动策略）。

### 任务清单

- [ ] **4.1** `LoginStep.solveCaptcha` 字段与 JSON 编解码  
- [ ] **4.2** `LoginRunner` 阻塞调用 Captcha Pipeline  
- [ ] **4.3** 登录助手设置：编辑 Recipe 时配置 mode / maxAttempts / onFail  
- [ ] **4.4** 站点白名单与 Login Recipe origin 对齐  
- [ ] **4.5** `LoginFormDetector`：检测到 captcha 时内联入口提示验证码助手  
- [ ] **4.6** 端到端：测试页串联账密 + 图形 +（可选）OTP  

### 完成标准

- 一条 Recipe 可在无人值守（auto）或询问确认后跑通测试页全流程。  
- onFail=`pause` 时弹出面板等人手；`abort` 停止并提示。

---

## Phase CA-5：跨域 iframe 强化

**目标**：reCAPTCHA v2 等跨域挑战可通过视口坐标 + 原生鼠标完成基本交互。

### 任务清单

- [ ] **5.1** 辅助功能权限检测与系统设置深链引导  
- [ ] **5.2** `CaptchaActor`：CGEvent 点击 / 拖拽（窗口坐标换算）  
- [ ] **5.3** iframe 元素截图裁剪改进  
- [ ] **5.4** reCAPTCHA 图片网格切分辅助 VLM  
- [ ] **5.5** 权限被拒时降级文案 + 人工接管  

### 完成标准

- 有辅助功能授权时：Google test key 页可完成一轮图片点选（允许重试）。  
- 无授权：明确提示，不静默失败。

---

## Phase CA-6：可选增强

**目标**：按需开启，不阻塞主线。

### 任务清单

- [ ] **6.1** `CaptchaProvider` 插件协议 + 2Captcha / CapSolver（用户自备 Key）  
- [ ] **6.2** 音频验证码：whisper.cpp / ASR → type（默认关）  
- [ ] **6.3** 旋转验证码适配器  
- [ ] **6.4** 每日每域配额与成本面板  
- [ ] **6.5** acceptance / roadmap 勾选；设计稿状态更新  

### 完成标准

- 设置中可单独启用各可选能力；默认全部关。  
- 文档声明合规边界与「不做保证」。

---

## 目录约定（实现时）

```
SimpleBrowser/CaptchaAssist/
  CaptchaAssistController.m/h
  CaptchaAssistPreferences.m/h
  CaptchaAssistPanel.m/h
  CaptchaDetector.m/h
  CaptchaCaptureService.m/h
  CaptchaSessionLog.m/h
  CaptchaDetection.m/h          # 检测结果模型
  captcha-assist-test.html
  （CA-1+）CaptchaPipeline / Actor / ModelGateway / Adapters / HelperBridge …
```

复用：`LoginAssistScriptMessageProxy`（弱代理 message handler）。

---

## 风险与门禁

| 门禁 | 要求 |
|------|------|
| 每阶段结束 | `make browser` 通过 |
| CA-0 | 测试页检测 + 截图落盘 |
| CA-1 | OCR/算术验收用例 |
| CA-2 | 滑块 demo 可过 |
| CA-4 | 与 Login Recipe 联调 |
| 合规 | 默认关、白名单、日志可清空；不提交用户 API Key |

---

## 文档修订

| 日期 | 说明 |
|------|------|
| 2026-07-16 | 初稿：CA-0～CA-6 任务与验收；与设计稿 §8 对齐 |
| 2026-07-16 | CA-0 骨架落地：Detector / Capture / Panel / 工具栏 / 测试页 |
