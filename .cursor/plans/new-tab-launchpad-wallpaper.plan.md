# Plan: Launchpad 新标签页背景图

> 依据 [docs/minimal-browser/new-tab-launchpad-wallpaper-design.md](../../docs/minimal-browser/new-tab-launchpad-wallpaper-design.md)  
> 任务拆解：[new-tab-launchpad-wallpaper-development-plan.md](../../docs/minimal-browser/new-tab-launchpad-wallpaper-development-plan.md)  
> **状态：已完成（2026-07-14）**

## Goal

为 Launchpad 新标签页支持自定义背景图：**导入时 ImageIO 降采样**、**进程内单例共享解码**、外观面板入口、压暗叠层；有壁纸时隐藏 `NSVisualEffectView`。

## Scope

- **做**：BG-0 + BG-1 + BG-2（Store、显示、面板、scrim、hidden 时 release）
- **不做**：动图/视频、每标签壁纸、浅色/深色双图、保留 original 重烘焙

## Architecture

```
AppearancePanel ──► BrowserWallpaperStore ──► ~/Library/Application Support/MeoBrowser/LaunchpadWallpaper/
                           │
                           ▼ Notification + shared NSImage
                   BrowserLaunchpadView（壁纸层 / scrim / effectView）
```

单窗口仅一个 `LaunchpadView`（显隐随 `isNewTabPage`）；Store 仍为单例以覆盖多窗口。

## Implementation Todos

### BG-0 Store
- [x] 新增 `BrowserWallpaperStore.h/.m`
- [x] ImageIO 缩略写 `display.jpg` + `meta.plist`
- [x] acquire/release、enabled、scrimAlpha、clear、通知
- [x] Makefile 链入 + `-framework ImageIO`

### BG-1 UI
- [x] `BrowserLaunchpadView`：wallpaper + effect 切换；`setHidden:` / `viewDidMoveToWindow` acquire-release
- [x] `BrowserLaunchpadAppearancePanel`：选图 / 清除 / 启用；增高面板
- [x] 空白区右键「设置/清除背景」

### BG-2
- [x] scrim 层 + 压暗滑杆
- [x] 验证：无壁纸路径不变；有壁纸不重复解码

### Verify
- [x] `make clean && make browser`（无警告）
- [x] 勾选设计 §9 / 开发计划 / acceptance 追加壁纸节

## Done when

- [x] 可选本地图并 aspectFill 显示
- [x] 导入后仅 display 降采样常驻；hidden 可卸图
- [x] 外观面板可开关/清除/压暗
- [x] 构建无警告；快捷方式与文件夹无回归
