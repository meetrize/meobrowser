---
name: 页面插件 Page Pack
overview: 按 PP-0→PP-MVP-D 落地 Stylish+Tampermonkey 合一的页面插件：本地 Pack 多文件 CSS/JS、URL 匹配注入、侧栏浏览/编辑钻入、保存热生效；远程发现仅占位。
todos:
  - id: pp-0-store-matcher
    content: PP-0：PagePack 模型 + Store 落盘 + Match 规则
    status: completed
  - id: pp-mvp-a-injector
    content: PP-MVP-A：Injector + 导航挂钩 + 热更新/总开关
    status: completed
  - id: pp-mvp-b-sidebar-browse
    content: PP-MVP-B：侧栏浏览态 + 工具栏/⌘⇧P + trailing 互斥
    status: completed
  - id: pp-mvp-c-editor
    content: PP-MVP-C：编辑态多文件 + SBTextView + 保存即时生效
    status: completed
  - id: pp-mvp-d-polish
    content: PP-MVP-D：空态/危险 match/手测与文档勾选
    status: completed
isProject: true
---

# 页面插件（Page Pack）— Cursor 计划

> **已完成（PP-0～PP-MVP-D）**  
> 设计：[docs/minimal-browser/page-pack-design.md](../../docs/minimal-browser/page-pack-design.md)  
> 开发计划：[docs/minimal-browser/page-pack-development-plan.md](../../docs/minimal-browser/page-pack-development-plan.md)

## 实现摘要

- `SimpleBrowser/PagePack/`：Models / Matcher / Store / Settings / Injector / Sidebar  
- 入口：Chrome `extension`（页面插件）+ 查看菜单 + **⌘⇧P**；trailing 侧栏互斥  
- 注入：`didCommit` start + `didFinish` end/idle；保存热更新；无 `removeAllUserScripts`  
- 「发现」分段占位；远程 Catalog 属后续 PP-1  
