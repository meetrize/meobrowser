# 重页 UI 响应性 — 开发计划

> 基于 [heavy-page-ui-responsiveness-design.md](heavy-page-ui-responsiveness-design.md)。  
> 状态：**HP-0～HP-3 已落地（代码）**；手测验收项待勾。  
> Cursor 计划：[.cursor/plans/heavy-page-ui-responsiveness.plan.md](../../.cursor/plans/heavy-page-ui-responsiveness.plan.md)  
> 前置：多标签、休眠预算、`refreshTabsUI`、标签拖拽、导航卡死治理 NH-0～4。

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 失活媒体 | pause + mute；**不**自动 play |
| 快照 | pause 发现媒体 / mediaHeavy → 跳过 `takeSnapshot`；无媒体则异步 capture |
| 切页 | 同步关键路径；非关键 `dispatch_async` |
| 拖拽 | 10 pt + ≥150 ms |
| 休眠 | mediaHeavy → 90 s；预算优先淘汰 |
| Process pool | **不做** |
| 设置 UI | 可选；默认开启行为即可 |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase HP-0 | 手势门控 + 切页关键路径 | 完成 | 误拖缓解；切标签更轻 |
| Phase HP-1 | 失活 pause 媒体 + 条件快照 | 完成 | 后台直播不再抢资源 |
| Phase HP-2 | mediaHeavy 加速休眠 | 完成 | 90s 销毁重页 WebView |
| Phase HP-3 | progress 节流 + 打磨验收 | 完成（代码） | 主线程更稳；文档待手测勾选 |

**交付：HP-0～HP-3（代码）。**

---

## Phase HP-0：手势门控 + `refreshTabsUI` 瘦身

### 任务

1. [x] `BrowserTabItemView`：`kReorderDragThreshold = 10`；自 mouseDown 起 `kReorderDragMinDuration = 0.15` 秒后才允许 `onReorderDragBegan`
2. [x] `refreshTabsUI`：拆出同步关键 vs `dispatch_async` 延后块；延后块校验 selectedTab 代际（`refreshTabsUIGeneration` + `tabID`）
3. [x] 延后：`reloadShortcuts`、overview reload、证书/错误同步、透明样式、overview 按钮外观
4. [x] `make browser`

### 验收

- [ ] 短按单击标签稳定选中，难误拖
- [ ] 长按拖拽排序仍可用
- [ ] 快速连切标签无错挂 WebView

---

## Phase HP-1：失活媒体 + 条件快照

### 任务

1. [x] 新建 `BrowserBackgroundMediaController`（pause/mute JS + completion `foundMedia`）
2. [x] `BrowserTab.mediaHeavy`；detach 前调用 pause；found → 置位
3. [x] 切走时若 foundMedia / mediaHeavy → 跳过 thumbnail capture；无媒体则 completion 内异步 capture
4. [x] 休眠/`discardWebView` 时清除 `mediaHeavy`
5. [x] `make browser`

### 验收

- [ ] 直播切走后 Activity Monitor 中 WebContent/GPU 明显下降
- [ ] 切回不自动播放

---

## Phase HP-2：加速休眠

### 任务

1. [x] `kHibernateIdleSecondsMediaHeavy = 90`
2. [x] `evaluateHibernation` 按 `mediaHeavy` 选用闲置阈值
3. [x] 预算淘汰：`mediaHeavy` 优先（rank 更低 / 窗内排序靠前）
4. [x] `hibernate` / `discardWebView` 时 `mediaHeavy = NO`
5. [x] `make browser`

### 验收

- [ ] 失活直播标签约 90s 后可休眠（非保护 host）
- [ ] 钉住 / resistsHibernation / 保护 host 不误杀

---

## Phase HP-3：节流与打磨

### 任务

1. [x] `estimatedProgress` UI 更新 coalesce（≈80ms 或 Δ≥0.02；终态立即）
2. [ ] 手测清单勾选
3. [x] `docs/README.md` 索引
4. [x] `make browser`

### 验收

- [ ] 直播页加载中进度条仍可读，主线程更少尖峰
- [ ] 设计文档验收项可勾

---

## 建议实现顺序

```text
HP-0 → HP-1 → HP-2 → HP-3
```

HP-1 对直播体感最大；HP-0 对「点成拖」最大。同迭代已落地。
