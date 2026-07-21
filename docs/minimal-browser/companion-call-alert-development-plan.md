# Companion 来电提醒（MVP）— 开发计划（Cursor 可执行）

> 基于 [companion-call-alert-feasibility-and-design.md](companion-call-alert-feasibility-and-design.md)。  
> **范围锁定**：Call Screening 取号 + Mac 系统通知 + 跨窗来电条 + 最简规则类型 + Mac 本地备注策略库 + 工具栏管理。  
> **不做**：phone.dat、黑名单/拒接、通讯录同步（CA-4+）、策略 LAN 同步（可选后续）。  
> 状态：**CA-0～CA-3 代码已落地**；真机来电手测待勾选  
> 协议：V2.2 `call_event` / `call_event_ok`

---

## 行为定稿

| 项 | 定稿 |
|----|------|
| 总开关 | Android / Mac 默认 **关** |
| 取号 | 仅 `ROLE_CALL_SCREENING`；一律放行，不拒接 |
| 无 Screening | 不推送无号码来电；设置页引导 |
| 类型判断 | Mac 侧 `simple_rules.json`；无省市区 |
| 策略库 | MVP **仅 Mac 本地** |
| 未连接 | 丢弃事件 |
| 黑名单 | 不做 |
| 未知 type | Mac 安全忽略 |

**首版交付：CA-0 + CA-1 + CA-2 + CA-3。**

---

## 总览

| 阶段 | 名称 | 状态 | 产出 |
|------|------|------|------|
| Phase CA-0 | 协议与骨架 | 完成 | 协议 V2.2；Settings/Presenter；prefs 开关 |
| Phase CA-1 | Android 推送 | 完成 | Call Screening + 状态机 + `call_event` |
| Phase CA-2 | Mac 通知与横幅 | 完成 | Presenter + 跨窗 Banner + 设置开关 |
| Phase CA-3 | 规则与策略库 | 完成 | Classifier + Store + 工具栏面板 |
| Phase CA-4+ | 同步/通讯录 | 不做 | 见设计稿后期 |

---

## Phase CA-0～CA-3

任务清单见仓库实现；文档与代码已对齐设计稿轻量规则方案。

---

## 附录：手动验收

- [ ] 默认关；开启后需授电话 + Screening
- [ ] 响铃 → Mac 通知含号码；多窗口横幅同步
- [ ] 挂断后横幅收起
- [ ] `400` / 手机号显示规则文案
- [ ] 工具栏可备注；重启仍在
- [ ] 无黑名单 UI；无 phone.dat
- [ ] 关开关后不再推送；日志无完整号码
