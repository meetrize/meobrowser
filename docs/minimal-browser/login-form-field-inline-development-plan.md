# 登录表单逐字段内联 — 开发计划（IF-D）

> 基于 [login-form-field-inline-design.md](login-form-field-inline-design.md)。

## 总览

| 阶段 | 名称 | 状态 |
|------|------|------|
| IF-D0 | 文档 + prefs | **完成** |
| IF-D1 | Detector 多字段 + targets | **完成** |
| IF-D2 | fillField | **完成** |
| IF-D3 | ＋ 单字段保存 | **完成** |
| IF-D4 | 保存本表 | **完成** |
| IF-D5 | 次要菜单 + legacy | **完成** |
| IF-D6 | 测试页 + 验收 | **完成** |

## 验收摘要

1. 无 Recipe：用户名/密码旁为 ＋  
2. 存用户名后仅该框变填入；点填入只写该框  
3. 「保存本表」一次写入帐密并两图标变填入  
4. OTP 无 ＋；legacy 模式回退单钥匙  
5. 风险域无注入；备忘 ＋ 不出现在登录字段  
