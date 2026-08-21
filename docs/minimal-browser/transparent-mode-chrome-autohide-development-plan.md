# 透明模式自动藏壳 — 开发计划

> 基于 [transparent-mode-chrome-autohide-design.md](transparent-mode-chrome-autohide-design.md)。  
> 前置：TC-0～TC-2（透明保留标签条）、精简模式、摸鱼监视可参考。  
> 状态：**TH-0 / TH-1 / TH-2 已完成**  
> Cursor 计划：[.cursor/plans/transparent-mode-chrome-autohide.plan.md](../../.cursor/plans/transparent-mode-chrome-autohide.plan.md)

---

## 行为定稿（摘要）

| 项 | 定稿 |
|----|------|
| 作用域 | 仅透明模式 |
| 标签条 / 交通灯 | 指针外藏、内显 |
| 地址栏 | 精简始终藏；非精简随指针 |
| Peek | 可显栏；Peek 中移出不藏栏 |
| 移出延迟 | 80～120ms；移入立即 |
| 藏条 | `hidden` + 高度 0，不卸 accessory |

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase TH-0 | 指针监视 + 统一显隐入口 | 完成 | 透明启停监视；`applyChromeVisibility` 公式落地 |
| Phase TH-1 | 藏条 / 藏栏 / 延迟 | 完成 | 条高度与灯；toolbar；防抖 |
| Phase TH-2 | Peek、精简联动、验收文档 | 完成 | Peek 优先；手测；文档勾选 |

**交付：TH-0 + TH-1 + TH-2。**

---

## Phase TH-0：监视与显隐入口

**目标**：透明开则听鼠标；有统一方法按公式刷新壳。

### 任务清单

1. 新增 `BrowserTransparentChromeAutoHideController`（或 WC 内聚）  
   - 启停与透明布尔绑定  
   - local + global `MouseMoved`（可仿 Afk MouseRouter）  
   - `pointerInside` 边沿回调 WC  
2. WC：`applyChromeVisibilityForCurrentMode`  
   - 非透明：现有精简 toolbar + 条可见 + 灯可见  
   - 透明：按 design §2.3  
3. `enterTransparentModeChrome` 末尾启动 auto-hide 并立即 evaluate  
4. `exitTransparentModeChrome` 停止并强制壳还原  
5. `make browser`  

### 验收

- [ ] 透明开后移出/移入有日志或可见条显隐（可先只藏条）  
- [ ] 退出透明监视停止  

---

## Phase TH-1：完整藏条 / 藏栏 / 延迟

**目标**：矩阵行为完整；擦边不闪。

### 任务清单

1. 藏条：`tabStripAccessoryRoot.hidden` + `heightConstraint = 0`；显则恢复 `effectiveStripHeight`  
2. 交通灯随条：`setStandardWindowButtonsHidden:`  
3. toolbar：透明公式接入（精简永不显，除非 Peek）  
4. 移出 delay 100ms；移入 cancel delay 并立即显  
5. 窗 `frame` 变化后仍用最新 frame 命中  
6. `make browser` + 手测矩阵  

### 验收

- [ ] §2.1 四格行为正确  
- [ ] 擦边上沿无明显闪烁  

---

## Phase TH-2：Peek、精简、文档

**目标**：边界与文档收尾。

### 任务清单

1. Peek 激活：`showToolbar` 强制 true；移出不关 Peek 栏  
2. `setCompactModeEnabled:` 在透明态调用统一 apply  
3. 摸鱼现身后再 evaluate 一次 pointer（若易测）  
4. 勾选 design §6；更新 README / 原 chrome-revision 交叉引用  
5. Cursor plan 标完成  

### 验收

- [ ] Peek 手测通过  
- [ ] 退出透明壳正确  
- [ ] 文档状态已更新  

---

## 手测清单

1. 透明非精简：内=条+栏，外=皆藏  
2. 透明精简：内=仅条，外=皆藏；栏永不因移入出现  
3. 透明中开关精简  
4. 精简+透明 Peek；Peek 时移出栏仍在直至 Esc/Return  
5. 退出透明  
6. 透明+摸鱼  
7. 多窗互不串  

---

## 关键文件（预期）

| 文件 | 改动 |
|------|------|
| `TransparentMode/BrowserTransparentChromeAutoHideController.*`（建议） | 监视 |
| `BrowserWindowController.m` | 启停、显隐公式、enter/exit |
| `Makefile` | 新源文件 |
| 文档 | design/plan/README |

---

## 实现顺序

```
TH-0 监视 + apply 入口 → make browser
TH-1 条/灯/栏 + 延迟 → make browser
TH-2 Peek/精简/文档 → 验收
```
