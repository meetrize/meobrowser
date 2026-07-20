# Android MeoBrowser Chrome UI — 开发计划

> 基于 [android-browser-chrome-ui-design.md](android-browser-chrome-ui-design.md)  
> 状态：**UI-0～UI-3 已完成**（2026-07-20）；真机手测见 [android-browser-acceptance.md](android-browser-acceptance.md)

---

## 总览

| 阶段 | 名称 | 产出 | 状态 |
|------|------|------|------|
| UI-0 | 文档 | design + 本计划 | 完成 |
| UI-1 | 壳 | 顶栏 + 底栏布局与导航状态 | 完成 |
| UI-2 | 面板 | 功能 Sheet + 标签 Sheet | 完成 |
| UI-3 | 菜单与能力 | 六项菜单 + 全屏/旋转/字号/桌面快捷方式/open_url | 完成 |

---

## UI-0

- [x] design / development-plan 落盘
- [x] 可行性报告交叉引用

## UI-1

- [x] 重写 `activity_browser.xml`
- [x] `BrowserActivity` 去 `tabStrip`；底栏绑定
- [x] 前进/后退 enabled + alpha；标签数字

## UI-2

- [x] `bottom_sheet_tools.xml` + 逻辑
- [x] `bottom_sheet_tabs.xml` + 左滑关闭
- [x] 新标签按钮

## UI-3

- [x] ⋮ 六项
- [x] BrowserPrefs：fullscreen / orientation / textZoom
- [x] Android `open_url` + Mac 最小开标签
- [x] assembleDebug + acceptance 补充

---

## 关键文件

| 路径 | 动作 |
|------|------|
| `res/layout/activity_browser.xml` | 重写 |
| `res/layout/bottom_sheet_tools.xml` | 新增 |
| `res/layout/bottom_sheet_tabs.xml` | 新增 |
| `res/layout/item_tab_row.xml` | 新增 |
| `browser/BrowserActivity.kt` | 大改 |
| `browser/BrowserPrefs.kt` | 扩展 |
| `channel/*` + Mac `CompanionChannel.m` | open_url |
