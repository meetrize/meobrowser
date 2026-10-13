# 分栏性能优化方案(已落地)

## 症状
9宫格等分栏标签存在时,切换标签卡顿,点击变拖拽(主线程被堵,mouseDown 响应超时)。

## 热点(实测定位)
1. `bringSplitContainerToFrontIfNeeded` 每次 `addSubview positioned:` 触发整树 layout,9×WKWebView 一次几百ms。
2. 同标签 `refreshTabsUI`(页面加载进度高频触发)走分栏全量路径,反复动 toolbar(触发布局)。
3. 后台分栏 9 个页面同时合成绘制,GPU/主线程被占满。
4. divider `mouseDragged` 高频 `setNeedsLayout`,9 个 webView 全量重排。
5. 标签切换时 `thumbnailCapture` 与重页抢 GPU(原 live>=8 才跳)。

## 落地(不改交互:不断网不销毁,切回秒开)
1. 前置幂等:已在最前(`subviews.lastObject==c`)跳过 addSubview。
2. 同标签 refresh 轻量:只做前置确认,toolbar 只在“确实藏错”时动。
3. 后台分栏停画:切走时 panes `webView.hidden=YES`(Compositor 停画,不断网不销毁);切回 reuse 路径 `hidden=NO`。
4. 拖拽合帧:一帧最多一次 layout(`_layoutScheduled` + 下一 runloop `layoutSubtreeIfNeeded`)。
5. 有后台分栏时跳过 thumbnail 快照(`anySplitBG`)。

## 未做(可选二期)
- processPool 限额 / 每栏 JS 暂停(会改页面行为,如断开 websocket,暂不做)。
- 九宫格懒加载(空栏占位,滚动进入视口才 load;改交互,暂不做)。
- 分栏标签页标题缩略图缓存复用 panes 首帧(需快照链路改造)。
