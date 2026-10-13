# Split View + Sync Input — Development Plan

Date: 2026-10-13. Choices: 1c 2a 3a 4a 5a 6a.
Scope: single-window multi-pane (single/LR/UD/LCR/UMD/quad/nine), per-pane single page, chrome autohide default, JS-mirror sync, presets in menu (max 20), 1px divider.

## Milestones

### MW1 — Scaffold + layout engine (no sync)
- New dir `SimpleBrowser/SplitView/`:
  - `BrowserSplitContainerView.h/m` — owns panes, weights, layout IDs, divider drag.
  - `BrowserPaneView.h/m` — chrome (addr bar + back/fwd + close/focus) + content host (WKWebView or Launchpad placeholder).
  - `BrowserThinDivider.h/m` — 1px `separatorColor`, hover 2px blue hint, drag to resize.
  - `BrowserSplitLayout.h/m` — enum + helpers: single, LR, UD, LCR, UMD, quad, nine; weights default equal; serialize/deserialize.
- `BrowserWindowController` changes:
  - Add `splitContainer` property; method `setSplitLayoutID:weights:urls:`; `currentSplitSnapshot`; single-pane path must keep 100% current behavior (regression gate).
  - Content area hosts splitContainer instead of single webView host when layout != single.
  - Focus ring on active pane; `Cmd+1..9` focus pane; `Cmd+Opt+Left/Right` move focus.
- Divider: mouseDown/drag updates weights, min pane 120pt, persist per-layout weights in UserDefaults.
- Acceptance: all 7 layouts render; drag works; single mode pixel-identical; no leaks on switch.

### MW2 — Per-pane navigation + chrome modes + menus
- Each pane: own `BrowserTab`-lite (single WKWebView sharing `defaultDataStore`/`processPool`), own URL field, back/fwd, reload.
- ChromeMode per pane: Always / Autohide / Hidden. Autohide: hover near top 8px reveals with fade; mouse exit hides. Menu `View > Split View > Address Bar: Always/Autohide/Hidden (this pane|all panes)`.
- Menus `BrowserMenus.m`: `View > Split View > {Single, LR, UD, LCR, UMD, Quad, Nine} + Save as Preset… + presets list (checkmark) + Manage (rename/delete in submenu)`.
- Toolbar: tab-strip right side sync icon slot (disabled until MW3, greyed with tooltip).
- Acceptance: each pane independent nav; chrome modes work; menus checkmarked.

### MW3 — Presets (5a)
- `BrowserSplitPresetStore` (extend `BrowserWindowLayoutPresetStore` or new): `UserDefaults key meo.split.presets.v1`, max 20, item `{name, layoutID, weights[], urls[], chromeMode}`.
- Save flow: prompt sheet for name (default `Preset N + layout name`); overwrite confirm if same name.
- Load flow: apply layout + weights + load urls in order (empty -> Launchpad/blank); toast on load.
- Acceptance: save/load/rename/delete; restart persistence; 20-cap with alert.

### MW4 — Sync input JS mirror (4a)
- New `BrowserPaneSyncCoordinator.h/m` + `Resources/split-sync.js` injected via `WKUserScript` + `WKScriptMessageHandler (meoSync)`.
- Flow: toolbar sync icon toggles pick mode -> overlay badges 1..9 on panes -> click on form field captures fingerprint `{tag,id,name,xpath,css}` via JS -> coordinator pairs by css/xpath fallback to nth-input heuristic -> live `input` event from master broadcasts `{value, fingerprint}` -> slaves `setValue + dispatch InputEvent + change` using `nativeInputValueSetter` for React.
- Enter/Cmd+Enter broadcast submit; password/otp/captcha excluded with toast.
- Status: icon highlighted + `Sync n/n` label; Esc exits.
- Acceptance: same-site dual-pane (e.g. two search boxes) mirrors incl. IME commit + Enter; hetero-site best-effort with manual reselect prompt.

### MW5 — Polish + QA
- Memory guard: nine-pane warns if >6 heavy pages; lazy load offscreen panes.
- Perf: divider drag 60fps (layer-backed, no re-layout of webviews beyond frame set).
- Regression: session restore, transparent mode, fullscreen, find-bar, sidebars unaffected in single mode.
- Docs: update `acceptance.md` checklist.

## File checklist
- Add: `SimpleBrowser/SplitView/*`, `SimpleBrowser/SplitView/Resources/split-sync.js`, `BrowserSplitPresetStore.{h,m}` (or extend existing), this plan + design doc.
- Edit: `BrowserWindowController.{h,m}`, `BrowserMenus.m`, `BrowsingPreferences.{h,m}`, ChromeActions toolbar, `SimpleBrowser.xcodeproj`.

## Test plan
1. Each layout snapshot. 2. Divider drag both axes. 3. Per-pane nav isolation. 4. Autohide hover. 5. Preset round-trip + restart. 6. Sync same-site + Enter; password excluded. 7. Single-mode regression.


## MW5 落实记录(2026-10-13)
- Esc 退出:local keyDown monitor keyCode 53,同步中拦截并 stop。
- 状态:BrowserTransientToast 常驻 + 栏角标(○未配对/●已配对/主) + 工具栏 ⇄ 高亮。
- 九宫格内存 guard:进入前二次确认。
- 布局切换自动停同步(指纹失效)。
- Divider:layer-backed 自绘 1px,拖拽仅改 frame,不重建 webview。

## 验收清单
- [ ] 7 布局快照正常,单栏零回归
- [ ] 细线双向拖拽,最小 120pt
- [ ] 各栏独立导航/历史
- [ ] 地址栏三态 + 默认自动隐藏
- [ ] 预设 round-trip + 重启 + 20 上限 + 同名覆盖
- [ ] 同站同步打字(含拼音)+回车齐提交,密码排除
- [ ] Esc 退出,角标/toast 状态正确
