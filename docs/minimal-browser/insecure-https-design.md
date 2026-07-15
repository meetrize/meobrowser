# 不安全 HTTPS（证书无效）继续访问 — 设计方案

> 目标：允许技术用户在知情前提下打开证书无效的 HTTPS 站点（自签名、主机名不匹配、过期、内网 IP 等），并在地址栏持续提示风险。  
> 状态：CERT-0 / CERT-1 已实现（CERT-2 未做）  
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

结论：本功能解决的是 **HTTPS 握手中 Server Trust 失败后，用户显式例外放行**，不是关闭 TLS。

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

### 3.1 方案 A — 仅地址栏警示 + 自动继续

- 流程：证书失败 → 自动信任 → 加载 → 地址栏前缀「危险」。
- 优点：最少步骤，符合「直接打开」。
- 缺点：高风险；误触钓鱼站无拦截；与 Safari/Chrome 安全模型相悖；App 审核与专业用户信任都会受损。
- **不推荐作为默认。**

### 3.2 方案 B — 仅 NSAlert「继续 / 取消」

- 流程：challenge 时弹 sheet → 继续则信任并加载。
- 优点：实现快，与现有错误 Alert 一致。
- 缺点：模态打断；无法展示证书细节；用户关掉 sheet 后页面是空白，心智不如整页说明；地址栏警示仍要另做。
- 适合极小补丁，**不作为主体验。**

### 3.3 方案 C — Chrome 式整页 interstitial + 地址栏不信任指示（推荐）

- 流程：
  1. ServerTrust 失败 → **不立刻弹出系统 Alert**，在内容区展示浏览器自有警告页（标题、简述、主机名、可选「高级」展开证书摘要）。
  2. 用户点「返回安全页面」→ `CancelAuthenticationChallenge`，可回退历史或停在警告页。
  3. 用户点「仍然访问」→ 写入该 tab/会话的例外 → `UseCredential` → 重新加载（或完成挂起 challenge 后继续）。
  4. 加载成功后，地址栏 URL **左侧常驻**「连接不安全」badge（警示色），点击可查看详情 / 撤回例外。
- 优点：与用户预期一致（「打开 + 一直看得见风险」）；专业用户习惯好（运维面板、内网 IP）；首次决策清晰，持续状态可感知。
- 缺点：需一张简单 HTML/原生空白页 UI；比纯 Alert 多一点代码。
- **推荐为 V1 主路径。**

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

## 4. 建议定稿（V1）

### 4.1 产品原则

1. **默认拒绝**：与系统 WebKit 一致，无用户确认绝不信任无效证书。  
2. **显式继续**：至少一次明确「仍然访问」。  
3. **持续可见**：继续之后，地址栏必须有风险前缀，直到导航离开例外上下文或用户撤回。  
4. **范围最小**：例外默认按 **scheme + host + port**，优先 **当前会话 / 当前窗口进程内**；不做「信任全世界」。  
5. **可解释**：文案中文；说明这是「加密通道建立了，但身份不被系统信任」，不是「没有加密」。

### 4.2 推荐用户路径

```
输入 https://120.26.48.197/
        │
        ▼
  ServerTrust 失败
        │
        ▼
  内容区：不安全连接警告页
   · 主机：120.26.48.197
   · 原因：证书无效 / 主机名不匹配 / …
   · [返回]  [仍然访问（不安全）]
        │
        │ 用户点「仍然访问」
        ▼
  会话 allowlist 写入该 host:port
  完成 challenge / 重新 load
        │
        ▼
  页面正常显示
  地址栏：⚠ 连接不安全 | https://120.26.48.197/...
        │
        │ 点击 ⚠ → 弹出说明 +「停止信任此主机」
        ▼
  可选撤回；下次再进需再次确认
```

### 4.3 地址栏交互细节

| 状态 | 展示 |
|------|------|
| 正常 HTTPS（系统信任） | 可选：轻量锁或无图标（V1 可不做锁，只做「不安全」） |
| HTTP 明文 | 可选：「不安全」弱提示（非本方案必做） |
| 例外放行的 HTTPS | **必做**：URL 文本左侧醒目 badge，文案建议「连接不安全」或「证书不受信任」；颜色用系统 warning/red，避免紫系装饰 |
| 编辑地址栏时 | badge 可暂时隐藏或保留在字段外；以不挡输入为准 |
| 补全面板打开时 | badge 不抢焦点；不与建议列表重叠 |

**不要**只改 URL 字符串前缀（例如把显示改成 `[危险]https://…`）：会污染复制、补全与收藏；应使用独立 UI 指示器。

### 4.4 文案建议（中文）

- 警告页标题：`你的连接不是私密连接`
- 摘要：`服务器「{host}」的证书不受信任。攻击者可能正在试图窃取你的信息（例如密码、消息或信用卡）。`
- 主按钮（危险）：`仍然访问`
- 次按钮：`返回`
- 地址栏 badge：`连接不安全`
- badge 详情：`此站点使用了无效或不受信任的证书。流量仍可能被加密，但无法验证你访问的是否为真正的服务器。`

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
  method != ServerTrust → PerformDefaultHandling（或后续再做 HTTP Basic）
  method == ServerTrust:
    if SecTrustEvaluate 已可信 → UseCredential(credentialForTrust)
    else if exceptionStore 已允许该 host:port → UseCredential
    else:
      挂起 challenge（保存 completionHandler + challenge）
      展示警告页（打断普通错误 Alert）
      用户 仍然访问 → store.add → UseCredential →（必要时 reload）
      用户 返回/关闭 → CancelAuthenticationChallenge
```

注意：

- 若 WebKit 在未处理 challenge 时已走 `didFailProvisionalNavigation`，需在失败路径识别证书类错误（`NSURLErrorServerCertificateUntrusted` / `NSURLErrorSecureConnectionFailed` / `NSURLErrorServerCertificateHasBadDate` 等），**避免再弹「无法加载页面」与警告页双弹**。优先以 challenge 路径承接；失败路径仅作兜底。
- 同一导航期间多次 challenge：同 host 例外命中后应直接放行。

### 5.3 与现有错误处理的关系

| 错误类型 | V1 行为 |
|----------|---------|
| 证书类（本方案） | 警告页，**不**用通用「无法加载页面」Alert |
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
- 不默认信任全部无效证书。  
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

### 7.2 验收清单（CERT-0 + CERT-1）

- [x] 访问自签名或主机名不匹配的 HTTPS（含纯 IP）时，出现警告页而非仅英文系统句 Alert。  
- [x] 点「返回」不加载目标页；点「仍然访问」可打开内容。  
- [x] 打开后地址栏左侧有「连接不安全」指示，复制地址栏得到干净 URL（无徽章文案）。  
- [x] 同会话再次访问同 host:port 不再弹警告（或仅首次）；新启动会话后需重新确认（V1）。  
- [x] 有效公共证书站点行为不变（无多余警告）。  
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
| 能不能做？ | 能；标准 WKWebView 能力，中等工程量。 |
| 直接静默打开？ | **不建议**；至少首次确认。 |
| 更好的交互？ | **整页警告 +「仍然访问」+ 地址栏常驻「连接不安全」**（方案 C），兼顾技术用户效率与风险可见性。 |
| 与路线图关系 | 落地即完成 P0「自签名证书处理」的核心；全局开发模式作为 CERT-2 开关。 |

**推荐落地顺序：先 CERT-0（能打开）→ 立刻跟 CERT-1（地址栏风险提示）→ 按需 CERT-2（记住主机 / 开发模式）。**  
仅实现「能打开」而不做地址栏指示，不符合本需求；仅做地址栏而不做首次确认，不符合安全默认。
