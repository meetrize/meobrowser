# SBKit 文本输入架构

> 项目底层规范：所有 AppKit 应用的输入框默认支持 macOS 标准编辑快捷键。

## 问题背景

无菜单栏的极简 macOS 应用里，`NSTextField` 获得焦点后 **⌘C / ⌘V / ⌘X / ⌘A** 往往无效，因为快捷键依赖 **「编辑」菜单** 将动作转发给第一响应者（field editor / `NSTextView` / `WKWebView`）。

## 架构总览

```
AppDelegate.applicationWillFinishLaunching
        │
        ▼
SBApplicationMenus          ← 安装 应用 / 编辑 / 窗口 菜单
        │
        ▼  ⌘C ⌘V ⌘X ⌘A ⌘Z …
   第一响应者（地址栏 / 网页 / 未来输入框）

UI 层只使用 SBKit 控件：
  SBTextField / SBSecureTextField / SBTextView
        │
        ▼
SBTextInputConfiguration    ← 统一默认属性
```

## 模块说明

| 文件 | 用途 |
|------|------|
| `SBApplicationMenus` | 标准菜单栏；**每个 App 启动时调用一次** |
| `SBTextInputConfiguration` | 单行 / 密码 / 多行默认配置 |
| `SBTextField` | 标准单行输入（地址栏等） |
| `SBSecureTextField` | 标准密码输入 |
| `SBTextView` | 标准多行输入 |

目录：`SBKit/`（与 `SimpleBrowser/` 并列，可被多个 target 链接）。

## 默认支持的快捷键

| 快捷键 | 动作 | 说明 |
|--------|------|------|
| ⌘Z | 撤销 | 依赖字段 `allowsUndo` / 窗口 UndoManager |
| ⌘⇧Z | 重做 | |
| ⌘X | 剪切 | |
| ⌘C | 拷贝 | |
| ⌘V | 粘贴 | |
| ⌘A | 全选 | |
| Delete | 删除 | 菜单项「删除」，无组合键 |
| ⌃A / ⌃E | 行首 / 行尾 | 系统 field editor 内置（Emacs 风格） |
| ⌥← / ⌥→ | 按词移动 | 系统内置 |

> `WKWebView` 获得焦点时，同样通过「编辑」菜单使用网页内拷贝/粘贴等能力。

## 使用示例

### 1. AppDelegate 安装菜单

```objc
#import "SBApplicationMenus.h"

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [SBApplicationMenus installStandardMenusWithAppName:@"SimpleBrowser"];
}
```

### 2. 地址栏 / 任意单行输入

```objc
#import "SBTextField.h"

SBTextField *field = [SBTextField standardField];
field.placeholderString = @"输入网址";
field.delegate = self;
```

### 3. 多行文本（未来扩展）

```objc
#import "SBTextView.h"

NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:frame];
scrollView.hasVerticalScroller = YES;
SBTextView *textView = [SBTextView standardTextView];
scrollView.documentView = textView;
```

### 4. Makefile 链接 SBKit

```makefile
SBKIT_DIR := SBKit
BROWSER_SOURCES += $(SBKIT_DIR)/SBApplicationMenus.m ...
BROWSER_CFLAGS += -I$(SBKIT_DIR)
```

## 扩展规则

1. **新增输入类型**：在 `SBTextInputConfiguration` 增加 `configure…` 方法，并新增对应 `SB*` 子类。
2. **禁止**在 `*WindowController` 里重复设置 `editable` / `selectable` / `font`，除非为该控件特有需求。
3. **特殊按键**（如地址栏回车）：在 `NSTextFieldDelegate` 的 `control:textView:doCommandBySelector:` 处理 `insertNewline:`，不要拦截 ⌘ 组合键。
4. **新 App target**：复制 SimpleBrowser 的 SBKit 链接方式，并调用 `SBApplicationMenus`。

## Cursor 规则

AI 与协作者请遵循：

- **全局**：`.cursor/rules/global-development.mdc` — 新功能输入框一律用 `SBTextField` / `SBTextView`
- **细节**：`.cursor/rules/appkit-text-input.mdc`

## 当前采用情况

| 应用 | 菜单 | 输入控件 |
|------|------|----------|
| SimpleBrowser | ✅ `SBApplicationMenus` | ✅ 地址栏 `SBTextField` |
| SimpleWindow | ❌ 待迁移 | ❌ 仍用 XIB 原生控件 |
