# 不安全 HTTPS（证书无效）继续访问 — 设计方案

> 目标：允许技术用户打开证书无效的 HTTPS 站点（自签名、主机名不匹配、过期、内网 IP 等），并在地址栏持续提示风险。  
> 状态：**已改为方案 A**（CERT-0/1 行为调整：默认自动继续，仅地址栏警告图标；整页 interstitial 不再作为主路径）  
> 关联：[design.md](design.md) · [professional-features-roadmap.md](professional-features-roadmap.md)（P0「自签名证书处理」）  
> 触发报错示例：`The certificate for this server is invalid. You might be connecting to a server that is pretending to be "120.26.48.197"…`

---

## 1. 问题澄清

### 1.1 用户遇到的现象

在地址栏以 `https://` 打开目标（常见为内网 IP、自签站点、开发环境）时，页面打不开，出现证书无效提示；当前 MeoBrowser 将其当作普通导航失败，弹出「无法加载页面」Alert，且**没有「继续访问」路径**。

### 1.2 技术实质（先对齐用语）

口语里的「没有 SSL 却用 HTTPS」通常对应下列之一，**都不是**「纯 HTTP」：

| 实际情况 | 典型表现 | 本方案是否覆盖 |
|----------|----------|----------------|
| 自签名 / 私有 CA | 证书链无法锚定到系统信任根 | ✅ 主场景 |
| 主机名不匹配（IP 访问证书上的域名、或反向） | 文案含 pretending to be “…” | ✅ 主场景 |
| 证书过期 / 尚未生效 | 时间相关错误 | ✅ |
| 明文 HTTP 站点 | `http://` 可开；ATS 已允许 WebContent HTTP | ❌ 本方案不处理（本来就能开） |
| 用户写了 `https://` 但对端只提供 HTTP | 多为连接失败 / 协议错误，不一定是 ServerTrust | △ 另案；不承诺「伪装成 HTTPS」 |

结论：本功能解决的是 **HTTPS 握手中 Server Trust 失败后自动例外放行，并在地址栏标示风险**，不是关闭 TLS。

### 1.3 现状基线（代码）

| 项 | 现状 |
|----|------|
| `WKNavigationDelegate` | 已实现；挂在 `BrowserWindowController` |
| `didReceiveAuthenticationChallenge:` | **未实现**（页面加载） |
| 证书失败 UI | `didFailProvisionalNavigation:` → `handleNavigationError:` → `NSAlert`（仅「确定」） |
| 下载认证 | `BrowserDownloadManager` 仅 `PerformDefaultHandling` |
| ATS | `NSAllowsArbitraryLoadsInWebContent` 只放开 **HTTP**，**不**跳过无效 HTTPS 证书 |
| 地址栏 | 显示完整 URL；无锁图标 / 无安全态 |

L1 设计文档曾明确推迟「继续访问」；路线图已将其列为 P0 开发痛点，本方案据此升级。

---

## 2. 实现难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| **核心 API** | 低～中 | 实现 `webView:didReceiveAuthenticationChallenge:completionHandler:`；对 `NSURLAuthenticationMethodServerTrust` 在用户确认后使用 `credentialForTrust:` + `UseCredential` |
| **挑战生命周期** | 中 | completionHandler **必须且只能调用一次**；用户关窗、切标签、重新导航时要取消挂起的 challenge，避免泄漏或崩溃 |
| **例外存储** | 低 | 会话内存字典即可落地 V1；持久化 allowlist 为可选增强 |
| **地址栏风险提示** | 中 | 需在 URL 文本左侧增加「不安全」指示（图标/色条），并与编辑态、补全弹层共存；`SBTextField` 需扩展 leftView 或并列 badge，不能破坏编辑快捷键 |
| **子资源 / 重定向** | 中 | 同主机后续资源也可能再挑战；例外应按 **host + port**（或证书指纹）记住；跨域子帧另议 |
| **下载路径** | 中 | 页面放行 ≠ 下载自动放行；V1 可与页面共用同一 allowlist |
| **安全与产品边界** | 中 | 默认拒绝 → 用户确认 → 常驻警示；禁止静默信任所有主机 |
| **测试成本** | 中 | 需自签 cert、IP 访问、过期 cert 等本地夹具；自动化有限，手工清单为主 |

**综合判定：中等难度，约 1～2 人日可完成 V1（挑战处理 + 确认 UI + 会话例外 + 地址栏警示）；持久化与证书详情属 V1.1。**

技术上无 WebKit 私有 API 硬依赖；主要风险在交互时序与 UI 一致性，而非「能不能绕过校验」。

---

## 3. 交互方案对比

用户原设想：失败后仍能打开，并在地址栏 URL 前提示风险。主流浏览器几乎都在此之上再加一层「首次确认」，避免误点即泄漏帐密。

### 3.1 方案 A — 仅地址栏警示 + 自动继续（**当前产品路径**）

- 流程：证书失败 → 自动信任 → 加载 → 地址栏前缀警告图标（悬停 tooltip 说明风险；点击可看详情）。
- 优点：最少步骤，符合「直接打开」。
- 缺点：高风险；误触钓鱼站无拦截；与 Safari/Chrome 安全模型相悖。
- **已定稿为默认行为**（面向内网 / 运维 / 开发场景的 MeoBrowser）。

### 3.2 方案 B — 仅 NSAlert「继续 / 取消」

- 流程：challenge 时弹 sheet → 继续则信任并加载。
- 优点：实现快，与现有错误 Alert 一致。
- 缺点：模态打断；无法展示证书细节；用户关掉 sheet 后页面是空白，心智不如整页说明；地址栏警示仍要另做。
- 适合极小补丁，**不作为主体验。**

### 3.3 方案 C — Chrome 式整页 interstitial + 地址栏不信任指示（已弃用为主路径）

- 流程：ServerTrust 失败 → 内容区警告页 →「仍然访问」后写入例外 → 地址栏 badge。
- 曾作为 V1 推荐；现已改为方案 A。相关 `BrowserCertificateWarningView` 代码保留但默认不再展示。

### 3.4 方案 D — 全局「开发模式」一键放开所有证书

- 流程：设置开关打开后，所有无效证书一律信任（仍可在地址栏标红）。
- 优点：本地连锁调试极方便。
- 缺点：一开全站无防护；应用作**可选增强**，且默认关闭，打开时设置页强警告。
- 对应路线图「开发模式」；**不替代**按站确认。

### 3.5 方案 E — 系统钥匙串「始终信任该证书」

- 引导用户用钥匙串信任证书，浏览器不拦截。
- 优点：系统级、其他 App 共享。
- 缺点：对普通/快速内网 IP 场景步骤重；证书换了又要操作。
- 文档可写「可选」，**不作为产品主路径。**

---

## 4. 建议定稿（方案 A）

### 4.1 产品原则

1. **自动继续**：ServerTrust 失败时默认写入会话例外并 `UseCredential`，不弹整页确认。  
2. **持续可见**：地址栏 URL 左侧常驻警告图标；悬停显示风险说明；点击可看详情。  
3. **范围最小**：例外按 **host + port**，进程内会话；不做「信任全世界」的持久全局开关（CERT-2 可选）。  
4. **可解释**：文案中文；说明这是「加密通道可能仍在，但身份不被系统信任」，不是「没有加密」。

### 4.2 推荐用户路径

```
输入 https://186.241.123.36:14897/
        │
        ▼
  ServerTrust 失败
        │
        ▼
  自动 allowlist(host:port) + UseCredential
        │
        ▼
  页面正常显示
  地址栏：⚠ | https://186.241.123.36:14897/...
        │
        │ 悬停 ⚠ → tooltip 风险说明
        │ 点击 ⚠ → 详情说明
```

### 4.3 地址栏交互细节

| 状态 | 展示 |
|------|------|
| 正常 HTTPS（系统信任） | 可选：轻量锁或无图标（V1 可不做锁，只做「不安全」） |
| HTTP 明文 | 可选：「不安全」弱提示（非本方案必做） |
| 例外放行的 HTTPS | **必做**：URL 文本左侧警告图标（SF Symbol），悬停 tooltip；颜色用系统 warning/orange |
| 编辑地址栏时 | badge 可暂时隐藏或保留在字段外；以不挡输入为准 |
| 补全面板打开时 | badge 不抢焦点；不与建议列表重叠 |

**不要**只改 URL 字符串前缀（例如把显示改成 `[危险]https://…`）：会污染复制、补全与收藏；应使用独立 UI 指示器。

### 4.4 文案建议（中文）

- 地址栏图标 tooltip：`此站点证书不受信任。攻击者可能正在试图窃取你的信息（例如密码、消息或信用卡）。`
- 详情标题：`连接不安全`
- 详情正文：`「{host}」使用了无效或不受信任的证书。…`

---

## 5. 技术设计

### 5.1 模块划分（建议）

| 组件 | 职责 |
|------|------|
| `BrowserSSLExceptionStore`（新建） | 会话内 allowlist：`host:port` → 原因 / 时间；可选后续持久化 |
| `BrowserCertificateWarningController`（新建） | 展示警告页（原生 `NSView` 或内存 HTML `loadHTMLString:`）；接收「仍然访问」回调 |
| `BrowserWindowController` | 实现 `didReceiveAuthenticationChallenge:`；串联 store + 警告 UI；同步地址栏安全态 |
| 地址栏 UI | `BrowserAddressBarRowView` / 字段旁增加 `securityBadge`（`NSButton` 或 `NSImageView`） |
| Tab 态 | `BrowserTab` 增加 `connectionSecurityState`（trusted / insecureException / unknown）供 UI 绑定 |

### 5.2 认证挑战处理伪流程

```
收到 challenge
  method != ServerTrust → PerformDefaultHandling（或 HTTP Basic）
  method == ServerTrust:
    if SecTrustEvaluate 已可信 → PerformDefaultHandling
    else → store.allow(host:port) → UseCredential(credentialForTrust) → 地址栏显示警告图标
```

注意：

- 若 WebKit 在未处理 challenge 时已走 `didFailProvisionalNavigation`，识别证书类错误后写入例外并 **reload 一次**；若已在例外中仍失败则走通用错误页，避免死循环。
- 下载路径与页面一致：无效证书自动 UseCredential。

### 5.3 与现有错误处理的关系

| 错误类型 | V1 行为 |
|----------|---------|
| 证书类（本方案） | 自动放行 + 地址栏警告；**不**弹整页确认 |
| 取消、下载打断 | 仍忽略（现有 `shouldIgnoreNavigationError:`） |
| DNS / 超时 / 其他 | 保持现有 Alert |

### 5.4 例外策略（V1 / V1.1）

| 级别 | V1 | V1.1（可选） |
|------|----|--------------|
| 作用域 | 进程内会话；按 host+port | 可选「记住此主机」写入 UserDefaults（明文 host，不存私钥） |
| 证书绑定 | 可不绑定指纹 | 指纹变化则重新提示 |
| 开发模式 | 不做全局一键 | 设置开关：跳过确认但仍显示地址栏警示 |

### 5.5 下载与登录助手

- **下载**：若同一 host 已在 allowlist，download 的 ServerTrust 挑战应同样 UseCredential；否则可再确认或失败提示。  
- **登录助手**：在「连接不安全」状态下仍可填表，但建议在登录助手 UI 旁增加短提示「当前连接证书不受信任」，避免用户在假站上保存凭证（V1.1 文案级即可）。

---

## 6. 非目标（明确不做）

- 不禁用 TLS、不把 HTTPS「降级」成 HTTP。  
- 不实现完整证书管理器 / 私有 CA 导入向导（可文档引导钥匙串）。  
- V1 不做 EV、CT、混合内容精细指示（`hasOnlySecureContent` 可后续）。  
- 不处理客户端证书选择器（mTLS）——另案。

---

## 7. 分期与验收

### 7.1 分期

| 阶段 | 内容 | 预估 |
|------|------|------|
| **CERT-0** | `didReceiveAuthenticationChallenge` + 会话 allowlist + 警告页双按钮；证书错误不再双弹 Alert | 0.5～1 日 |
| **CERT-1** | 地址栏「连接不安全」badge + 点击详情 / 撤回信任 | 0.5 日 |
| **CERT-2** | 可选「记住此主机」；下载共用 allowlist；开发模式开关 | 0.5～1 日 |

### 7.2 验收清单（方案 A）

- [x] 访问自签名或主机名不匹配的 HTTPS（含纯 IP）时，**直接打开**，不出现「你的连接不是私密连接」整页。  
- [x] 打开后地址栏左侧有警告图标；悬停有风险说明；复制地址栏得到干净 URL。  
- [x] 同会话再次访问同 host:port 正常；有效公共证书站点行为不变。  
- [x] 用户取消挑战 / 关闭窗口无 completionHandler 泄漏或二次调用崩溃。

### 7.3 手工测试夹具建议

1. `openssl` 生成自签证书的本地 https server。  
2. 用 IP 打开绑了域名 SAN 的证书（复现 pretending to be）。  
3. 对照 `https://example.com` 回归。  
4. 多标签：标签 A 例外不影响标签 B 的未确认状态展示（store 可共享，但 B 首次仍应有警示态同步到地址栏）。

---

## 8. 结论与建议

| 问题 | 建议 |
|------|------|
| 能不能做？ | 能；标准 WKWebView 能力。 |
| 直接静默打开？ | **已采用**（方案 A）；风险靠地址栏图标持续提示。 |
| 与路线图关系 | 落地即完成 P0「自签名证书处理」；全局开发模式开关可作为 CERT-2（当前默认已等价于始终开发模式放行）。 |
