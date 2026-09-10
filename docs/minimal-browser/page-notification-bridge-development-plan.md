# 网页系统通知桥 — 分阶段开发计划

> 设计：[page-notification-bridge-design.md](page-notification-bridge-design.md)  
> 阶段：PN-0～PN-2

---

## PN-0 — Presenter

- [x] 新建 `BrowserPageNotificationPresenter.{h,m}`
- [x] `requestAuthorizationIfNeeded` / `presentWithTitle:body:tag:host:`
- [x] category `MEO_PAGE_NOTIFICATION`；identifier `page-notify-{host}-{tag}`
- [x] 可选安装 `UNUserNotificationCenterDelegate`（前台横幅；点击仅激活 App）

验收：单元/手工从 ObjC 调 `present…` 能弹出系统通知（需已授权）。

---

## PN-1 — Bridge + 挂载

- [x] 新建 `BrowserPageNotificationBridge.{h,m}`
- [x] handler 名 `meoPageNotify`；`LoginAssistScriptMessageProxy`
- [x] 允许列表 + 10s 限流 + 载荷校验/截断
- [x] 注入 `window.MeoBrowser.notify`
- [x] `BrowserWindowController` `installOnConfiguration:`
- [x] `Makefile` 加入两个 `.m`

验收：控制台对允许主机执行 `MeoBrowser.notify({title:'t',body:'b',tag:'t1'})` 弹出通知；非允许主机无反应。

---

## PN-2 — FeedGen 联调

- [x] FeedGen 阅读器自动刷新走 `meoPageNotify`
- [ ] 同 tag 覆盖、限流不刷屏（需 MeoBrowser 真机手测）
- [ ] 与手机镜像通知并存、互不影响开关（需真机手测）

验收清单见 FeedGen `docs/ARTICLE_REFRESH_NOTIFY.md` §6。
