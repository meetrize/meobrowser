# AI Bridge — BR-0 Spike 操作说明

对应计划：[ai-bridge-development-plan.md](../../../docs/minimal-browser/ai-bridge-development-plan.md) Phase BR-0。

## 文件

| 文件 | 作用 |
|------|------|
| `mock-chat.html` | 本地假对话页（自带加载 runtime + mock adapter） |
| `runtime.js` | `window.__MeoAIBridge` / `AIBridgeRuntime` |
| `adapters/mock.js` | Mock 选择器 |
| `adapters/deepseek.js` | DeepSeek 启发式适配器（需实测修订） |

## A. Mock 页（必做，无登录）

1. 构建并打开 MeoBrowser：`make run-browser`
2. 地址栏打开本文件（可用 Finder 拖入，或粘贴绝对路径）：

```text
file:///Users/meetrice/Projects/meobrowser/SimpleBrowser/AIBridge/Spike/mock-chat.html
```

3. 打开 Web Inspector（开发菜单 / 页面检查），在控制台执行：

```js
__MeoAIBridge.probe()
// 期望 ok: true, hasInput: true
```

4. 跑一轮：

```js
await __MeoAIBridge.send('你好，这是 Spike 测试')
await __MeoAIBridge.waitComplete({ timeoutMs: 30000, stableMs: 800 })
// 期望 { ok: true, text: 包含「Mock 回复」 }
```

5. 连续 5 次不同短句，全部 `ok: true` → 勾选计划 **0.7**。

### 一键五连（可粘贴）

```js
(async () => {
  const results = [];
  for (const q of ['alpha', 'beta', 'gamma', 'delta', 'epsilon']) {
    const s = __MeoAIBridge.send(q);
    if (!s.ok) { results.push({ q, s }); break; }
    const w = await __MeoAIBridge.waitComplete({ timeoutMs: 30000 });
    results.push({ q, ok: w.ok, len: (w.text || '').length });
    await new Promise(r => setTimeout(r, 400));
  }
  console.table(results);
  return results;
})();
```

---

## B. DeepSeek 网页（建议做）

1. 新标签打开 `https://chat.deepseek.com`，**手动登录**完成。
2. 进入可输入对话的页面（能看到输入框）。
3. Web Inspector 控制台：**先粘贴** `runtime.js` 全文，回车；**再粘贴** `adapters/deepseek.js` 全文。
4. 探测：

```js
__MeoAIBridge.probe()
```

- `ok: true` → 勾选 **0.8**  
- 若 `hasInput: false`：多半未登录或 DOM 变更 → 记入附录，用 Elements 面板找真实 textarea / contenteditable，改 `deepseek.js`

5. 三轮短问：

```js
(async () => {
  const qs = ['用五个字介绍你自己', '1+1等于几', '返回单词 OK'];
  const out = [];
  for (const q of qs) {
    __MeoAIBridge.send(q);
    const w = await __MeoAIBridge.waitComplete({ timeoutMs: 120000, stableMs: 1000 });
    out.push({ q, ok: w.ok, preview: (w.text || '').slice(0, 80) });
  }
  console.table(out);
  return out;
})();
```

成功则勾选 **0.9**；把最终可用选择器 / `isBusy` 逻辑回写 `adapters/deepseek.js`，并勾选 **0.10**。

---

## C. 常见失败

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| send 后页面无反应 | 受控组件未吃到 value | 检查 `nativeSetValue`；或改为逐字 InputEvent；点真实发送按钮 |
| waitComplete 超时 | busy 选择器不对 / 流式一直认为 busy | 放宽 `isBusy`；加大 `stableMs`；看是否有「停止」按钮 |
| 读到上一轮回复 | 未等新气泡出现 | 确认 `count` 增加或文本相对 baseline 变化 |
| probe host mismatch | 不在 deepseek 域名 | 确认 URL |

---

## D. 附录 — 实测记录（填写）

| 日期 | 环境 | 项 | 结果 | 备注 |
|------|------|-----|------|------|
| 2026-10-28 | Cursor IDE browser / Chromium | Mock 五连 | ✅ | `allOk: true` |
| 2026-10-28 | 同上（已登录 DeepSeek） | DeepSeek probe | ✅ | textarea「给 DeepSeek 发送消息」 |
| 2026-10-28 | 同上 | DeepSeek 三轮 | ✅ | 智能小助手 / 2 / OK；`sendAndWait` |
| | MeoBrowser WKWebView | Mock / DeepSeek 复验 | ⬜ | BR-1 前建议在 Meo 内再跑一遍 |

### 实测结论（DeepSeek DOM）

| 控件 | 可用选择器 |
|------|------------|
| 输入 | `textarea`（placeholder 含 DeepSeek） |
| 发送 | **`DIV.ds-button--primary`**（非 `<button>`，常无 aria-label） |
| 助手全文 | **`.ds-markdown.ds-assistant-message-main-content`** |
| 勿用 | `.ds-markdown-paragraph` 单独取最后一段（会误读结尾寒暄） |

### 失败模式

1. **发送找不到**：只查 `button` /「发送」文案会失败 → 必须点 primary `ds-button`。  
2. **回复截断/错文**：取 paragraph 而非整段 markdown。  
3. **短回复 timeout**：`waitComplete` 在 `send` 之后才采 baseline → 快速回复已写入，`sawGrowth` 永不成立 → 用 **`sendAndWait`（先 baseline 再 send）**。  
4. **busy 信号弱**：本轮 `sawBusy` 多为 false，完成判定主要靠「助手节点增长/文本变化 + stableMs」。
