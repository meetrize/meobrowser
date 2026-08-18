# 流式 / blob 附件下载 — 开发计划

> 基于 [download-design.md](download-design.md) V1.1。  
> 问题：页面在线生成的 zip 等在 Safari 可下为「合规监测报告_….zip」，本应用落成 `video.mp4` 并报 Load failed。  
> 状态：**DL-0～DL-2 已实现**（2026-08-18）

---

## 根因（相对 Safari）

| Safari | V1 MeoBrowser |
|--------|----------------|
| `shouldPerformDownload` → `WKNavigationActionPolicyDownload` | 所有 `blob:` `Cancel` 后进豆包视频 JS |
| 点击当拍从 Blob 寄存器读数据（早于 `revokeObjectURL`） | 异步 `fetch(blob)`，常已被 revoke → **Load failed** |
| 文件名 = `download` 属性 / `Content-Disposition` | 占位名硬编码 `video.mp4`，且非视频会被拒绝 |

典型站点代码：`fetch` 流式结果 → `Blob` → `<a download="….zip">` → 立刻 `revokeObjectURL`。

---

## 行为定稿

1. **优先 Safari 路径**：`shouldPerformDownload` 或应下载的 `blob:` 导航 → `WKNavigationActionPolicyDownload`。  
2. **文件名**：`<a download>` > `filename*` / `filename` > WebKit 建议名 > MIME/魔数。  
3. **通用 blob JS 回退**：任意 MIME（zip/pdf/xlsx…）；只有豆包等媒体站且无文档文件名才走视频启发式。  
4. **不在全站挂钩 `createObjectURL`**（Cloudflare 敏感）；原生下载不依赖该钩子。  
5. 豆包右键下视频行为保持不变。

---

## 总览

| 阶段 | 名称 | 产出 |
|------|------|------|
| DL-0 | 原生下载策略 | `shouldPerformDownload` / blob → `PolicyDownload`；`downloadAttribute` 传入 Manager |
| DL-1 | 通用 blob 回退 | 去掉 `video.mp4` 默认；zip 等可保存；媒体站仍可走 play_info |
| DL-2 | 文件名与 MIME | Content-Disposition、扩展名补全、PK/PDF 魔数 |

---

## 任务清单

- [x] **0.1** `shouldDownloadNavigationAction:`；`decidePolicy` 用 `WKNavigationActionPolicyDownload`
- [x] **0.2** `navigationAction:didBecomeDownload:` 传入 `downloadAttribute`
- [x] **0.3** `createWebView`：`shouldPerformDownload` 或 blob 不建弹窗，改下载
- [x] **1.1** `saveBlobURL` 接受建议文件名；非媒体站先读目标 blob
- [x] **1.2** `requiresMediaContent`：仅媒体站 + 无文档名时校验视频
- [x] **1.3** WKDownload 失败的 blob 再走 JS 回退
- [x] **2.1** 解析 `filename*` / `filename`；无扩展名按 MIME 补全
- [x] **2.2** zip / pdf / 办公文档 MIME 与 PK/PDF 魔数
- [x] **2.3** 更新 [download-design.md](download-design.md) §3.1～3.3
- [x] **2.4** `make browser`

---

## 手测

- [ ] 在线生成报表 zip：文件名与 Safari 一致（含中文），可打开
- [ ] 普通 HTTP `Content-Disposition: attachment` 附件
- [ ] 豆包视频右键下载仍成功
- [ ] 可内联 PDF 仍在页内打开，不被强制下载
