# 登录表单检测性能优化 — 设计方案（IF-P）

> 目标：在保持内联登录助手可用性的前提下，消除重 SPA（如闲鱼 [goofish.com](https://www.goofish.com/)）上因常驻扫描导致的卡顿。  
> 范围：**仅改** `LoginFormDetector` 注入脚本行为；不改 Recipe / 系统密码 / 保存提示产品路径。  
> 前置：[login-form-inline-design.md](login-form-inline-design.md)（V1.5 已落地）  
> 触发背景：打开高 DOM churn 站点后浏览器响应明显变慢；主因是默认开启的全页 `MutationObserver` + 昂贵 `scan()` + 捕获阶段 `scroll`。  
> 状态：**已落地**（2026-07-15 · `LoginFormDetector.m` IF-P）

---

## 1. 问题简述

当前 `LoginFormDetector.m` 注入脚本在启用时：

1. 对 `document.documentElement` 做 `{ childList, subtree: true }` 的 `MutationObserver`；
2. `window` 捕获阶段监听 `scroll` / `resize`；
3. 防抖 250ms 后跑完整 `scan()` → `contexts()` 对每个 `input` 先 `visible()`（`getComputedStyle` + `getBoundingClientRect`）。

在闲鱼这类虚拟列表 / 无限滚动页面上，DOM 几乎不停变更，scan 可近似按 **~4Hz** 持续执行，与站点自身 JS 抢 WebContent，表现为整页与标签 UI 发黏。非登录类电商 / 信息流 SPA 普遍存在同类风险。

---

## 2. 本版做啥（三刀）

| # | 改动 | 一句话 |
|---|------|--------|
| A | **无密码框早退** | `scan()` 开头用廉价选择器探测；没有密码候选则不走全量 `contexts()` |
| B | **卸掉常驻 scroll** | 删除始终挂载的捕获 `scroll`；仅在已放置内联按钮时按需监听，用于滚动容器内重定位 |
| C | **空闲后暂停观察** | 连续多次「无密码候选」后 `disconnect` MutationObserver；用轻量事件重新武装 |

刻意**不做**本版：站点黑名单、拉长防抖、改 Native `formDetected` 去重（可作为 IF-P2）。

---

## 3. 行为定稿

### 3.1 A — 无密码框早退

在现有 `scan()` 最前端增加：

```js
function hasPasswordCandidate() {
  try {
    return !!document.querySelector(
      'input[type="password"],' +
      'input[autocomplete*="current-password"],' +
      'input[autocomplete*="new-password"]'
    );
  } catch (e) { return true; } // 选择器异常时退回全量，偏保守
}
```

- `hasPasswordCandidate() === false`：`clearButtons`；若此前有 `activeFormId` 则 `formCleared`；递增空闲计数；**return**（不调用 `contexts()`）。
- 为 `true`：走现有 `contexts()` / `placeButton` / `post(formDetected)`；空闲计数清零。

说明：早退只跳过布局强迫式遍历，不改变「怎样算登录表单」的启发式（帐号字段、注册排除等仍在全量路径）。

### 3.2 B — scroll 策略

| 阶段 | 行为 |
|------|------|
| 初始安装 | **不** `addEventListener('scroll', …)` |
| `resize` | 保留（低频）；仍走 `schedule` |
| 首次 `placeButton` 成功 | 若尚未挂载，再 `addEventListener('scroll', schedule, true)` |
| `clearButtons` 清空到无按钮 / `formCleared` | `removeEventListener`，卸掉 scroll |

理由：按钮用 `scrollY/X + getBoundingClientRect` 的文档坐标定位，**窗口滚动**本身不必重算；需要 scroll 的主要是 **overflow 子滚动容器** 导致视口相对位移。常驻捕获 scroll 是闲鱼卡顿的放大器，按需挂载即可兼顾登录页内滚动条场景。

### 3.3 C — 空闲暂停 / 重新武装

**状态机**

```
[ACTIVE] ──(连续 EMPTY_STREAK 次无密码候选)──► [PAUSED]
   ▲                                              │
   └────(rearm 触发：focusin / 廉价脉搏)───────────┘
```

| 常量（建议默认） | 值 | 含义 |
|------------------|----|------|
| `EMPTY_STREAK` | `8` | 连续 8 次早退（约 ≥2s 稳态，考虑防抖）后暂停 |
| `PULSE_MS` | `8000` | 暂停期间每 8s 做一次**仅** `hasPasswordCandidate` 的脉搏；命中则 rearm |

**进入 PAUSED**

1. `mo.disconnect()`；
2. 卸掉 scroll（若有）；
3. 保留：`focusin`（capture，目标为 `INPUT`/`TEXTAREA`）→ `rearm()`；
4. 启动 `pulseTimer`（可 `setInterval`）。

**`rearm()`**

1. 清脉搏定时器；
2. `mo.observe(document.documentElement, { childList: true, subtree: true })`；
3. `schedule()` 立即排队一次 scan；
4. 空闲计数归零；状态 → ACTIVE。

**仍在 ACTIVE 且已有登录表单时**：不进入暂停（空闲计数在有密码候选时清零）。表单被卸掉后再开始累计。

---

## 4. 对「其它网站正常登录浏览」的影响分析

### 4.1 结论先讲

对**已经出现或即将出现密码框的常规登录页**，行为应与今日基本一致；风险集中在「长时间无密码 → 已 PAUSED → 再以纯 DOM 插入密码框且用户尚未聚焦」这一窄场景，由 **focusin + 8s 脉搏** 兜底。

### 4.2 分场景

| 场景 | 影响 | 说明 |
|------|------|------|
| 静态登录页（HTML 里已有 password） | **无实质影响** | 首次 `schedule` 即命中密码候选 → 全量 scan；不会进 PAUSED |
| SPA 晚渲染登录（路由进 `/login` 后挂表单） | **基本无影响** | 渲染过程有 mutation → ACTIVE 下 debounce scan；密码一出现即走全量 |
| 首页点「登录」→ 模态/抽屉插入 password | **多数无感** | 插入会触发 MO（若仍 ACTIVE）。若此前在信息流已 PAUSED：用户点帐密框时 `focusin` → rearm → 下一帧级出现图标；最坏未聚焦时等脉搏 ≤8s |
| 密码框在 iframe（跨域） | **与现网相同** | V1.5 本就不支持跨域；本方案不恶化 |
| Shadow DOM 内密码框 | **与现网相同** | `querySelector` / 现 `contexts` 都看不到 |
| 先 `type=text` 后改成 `password` | **轻微延迟可能** | 早退选择器在改 type 前可能 miss；靠 mutation（改 attribute 会否触发取决于站点；`childList` **不**观察 attributes！） |

### 4.3 关于 `childList`-only 与改 type

现有 Observer **只观察 `childList`**，本来就不会因 `type`/`autocomplete` 属性变更触发。本方案不新增 `attributes` 观察（避免再放大成本）。依赖：

- 改 type 时站点常伴随节点替换 / 重挂（多数框架会触发 childList）；或  
- 用户聚焦 → `focusin` rearm + scan；或  
- 脉搏命中（若 type 已是 password）。

若日后实测某站「仅改 type、无 childList」漏检，IF-P2 再考虑对 `INPUT` 开窄域 `attributes: true, attributeFilter: ['type','autocomplete']`，**且仅 ACTIVE 且未早退时**，勿默认全树 attributes。

### 4.4 卸掉常驻 scroll 对登录页

| 布局 | 影响 |
|------|------|
| 密码框在文档流，窗口滚动 | **无**：文档坐标按钮与输入框一起滚 |
| 密码框在 `overflow:auto` 面板内 | **有按钮后**才挂 scroll，仍会 `schedule` 重定位 → **保持可用** |
| 无按钮的浏览页 | 不再因滚动触发 scan → **正是本版收益** |

### 4.5 会变「差」的只有这些

1. 浏览型重 SPA：图标本就不该出现 → 应变快，属预期收益。  
2. PAUSED 后弹出登录层、用户盯着看却迟迟不点输入框：图标最多延迟到脉搏（≤8s）或第一次 focus。可接受；工具栏钥匙入口仍在。  
3. 早退选择器漏掉「无 type=password、仅靠 name 启发式当密码」的非标字段：现网 `isPasswordField` 也要求 `type=password` 或 autocomplete 含 password 语义，**与早退对齐，不新增漏检面**。

### 4.6 不必担心的

- Recipe 一键 / 系统密码 / 保存提示：不改 Native 协议与开关语义。  
- `login-assist-test.html`：静态 password，路径与今日一致。  
- 关闭 `inlineAssistEnabled`：仍整段不安装（现逻辑）。

---

## 5. 实现落点

| 项 | 位置 |
|----|------|
| 唯一代码改动 | `SimpleBrowser/LoginAssist/LoginFormDetector.m` 的 `userScriptSource` |
| Native / Pref | **不动**（本版不改开关文案；可选在设置说明里加一句「已优化重页面扫描」） |
| 文档互链 | 本文件；在 `login-form-inline-design.md` §7 增一行修订；开发计划可记 IF-P |

实现时注意 JS 字符串转义与现有 `@""` 拼接风格一致；可抽取小段注释标明 `IF-P`。

### 建议伪代码骨架（嵌入脚本内）

```js
let emptyStreak = 0;
let paused = false;
let scrollBound = false;
const EMPTY_STREAK = 8;
const PULSE_MS = 8000;
let pulseTimer = null;

function bindScroll(on) { /* add/remove capture scroll → schedule */ }
function setPaused(p) { /* disconnect/observe + pulse + 标志 */ }
function rearm() { setPaused(false); schedule(); }

function scan() {
  if (!hasPasswordCandidate()) {
    clearButtons(/* none */);
    // formCleared if needed
    bindScroll(false);
    emptyStreak++;
    if (!paused && emptyStreak >= EMPTY_STREAK) setPaused(true);
    return;
  }
  emptyStreak = 0;
  // … existing contexts / placeButton …
  bindScroll(list.length > 0);
  // … formDetected …
}

// 初始：MO + resize；无 scroll
// focusin capture → if INPUT|TEXTAREA then rearm()
```

---

## 6. 验收

### 6.1 回归（不得变差）

- [ ] `login-assist-test.html`：密码框右侧钥匙仍出现；点击菜单行为不变  
- [ ] 至少 1 个真实静态登录页：图标出现时间与改前无明显变差  
- [ ] 至少 1 个 SPA 登录（晚挂表单）：进入登录路由后图标仍出现  
- [ ] 登录模态：从已浏览页打开模态后，点击密码框前后图标应出现（允许 focus 后出现）  
- [ ] `overflow` 内登录表单：滚动容器时图标不严重错位  

### 6.2 性能（本版目标）

- [ ] 闲鱼首页滚动 / 停留：主观卡顿相对改前明显减轻；CPU 抽样中注入脚本不再持续高占比  
- [ ] 同类信息流站（可选 1 个）同样改善  
- [ ] 已显示登录图标的页面：滚动、填表、一键填充仍可用  

### 6.3 调试（可选）

临时 `post({ type: 'detectorState', paused, emptyStreak })` 仅 Debug 宏编译；正式提交可不带，或默认关闭。

---

## 7. 非目标 / 后续（IF-P2）

- 按 host 黑名单跳过检测  
- `formDetected` 结果去重降 IPC  
- Observer 增加 `attributes` 窄过滤  
- 关闭 Pref 后对已开页立刻 `disconnect`（Native `evaluateJavaScript`）  
- 独立 `WKProcessPool`  

---

## 8. 文档维护

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1 | 2026-07-15 | 初稿：早退 + 卸常驻 scroll + 空闲暂停；登录场景影响分析；验收 |
| 0.2 | 2026-07-15 | 落地：`LoginFormDetector` 注入脚本实现 IF-P |
