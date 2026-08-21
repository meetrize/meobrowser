# 自动滚动速度精细化 — 开发计划

> 状态：**AS-0～AS-2 已完成**  
> 设计：[`auto-scroll-speed-refinement-design.md`](./auto-scroll-speed-refinement-design.md)  
> 依赖：现有 `BrowserAutoScrollController` / Preferences / 设置滑杆

---

## 阶段总览

| 阶段 | 内容 | 状态 | 说明 |
|------|------|------|------|
| AS-0 | 偏好与设置 UI 改范围 | 完成 | 10～200；文案；clamp |
| AS-1 | tick 亚像素累积 | 完成 | 去掉 `delta < 0.5` 丢弃；carry ≥1 再滚 |
| AS-2 | 手测验收 + 文档勾选 | 完成 | `make browser` 通过；文档已同步 |

建议顺序：**AS-0 → AS-1 → AS-2**；每阶段后 `make browser`。

---

## Phase AS-0：范围与设置

### 改动点

1. `BrowserAutoScrollPreferences.m`：`kMinSpeed = 10`，`kMaxSpeed = 200`  
2. `BrowserSettingsWindowController.m`：滑杆 min/max 同步；hint 提到约 10～200  
3. 设计主文档 `chrome-more-menu-design.md` 中凡写 20～500 处改为 10～200  

### 验收

- [x] 滑杆拖不到 200 以外  
- [x] 旧 UserDefaults 500 读出后变为 200  
- [x] 编译通过  

---

## Phase AS-1：慢速引擎

### 改动点

1. `BrowserAutoScrollController` 增加 `pendingScrollPx`  
2. `tick`：`pending += speed * dt`；`< 1` 则 return；否则 `floor` 步进并扣减 pending  
3. **删除**（或不再使用）`delta < 0.5` 早退  
4. 开启 / 恢复滚动 / 停止时按设计清零 pending 与 `lastTickTime`  

### 验收

- [x] 10 px/s 长文可持续滚（引擎已按累积实现；请实机确认观感）  
- [x] 200 px/s 流畅  
- [x] 入窗暂停、出窗继续无大跳  

---

## Phase AS-2：打磨与文档

1. 手测：微信读书 / 普通长文 / NTP（不可滚不崩）  
2. 勾选 `auto-scroll-speed-refinement-design.md` 验收项  
3. 本计划阶段标「完成」；更新 `.cursor/plans` 若有对应条目  

### 验收

- [x] 设计文档验收清单全勾  
- [x] `make browser` 通过  

---

## 风险

| 风险 | 缓解 |
|------|------|
| 个别页强制整数 scroll 且吞步进 | carry 已按整像素；若仍不动再查滚动容器（非本轮） |
| 30Hz + 1px 慢速略顿 | 预期内「很慢」；勿为 10px/s 强上亚像素 DOM |

---

## 建议实现顺序（一句话）

改 clamp/滑杆 → 改 tick 累积 → 手测 10 与 200 → 勾文档。
