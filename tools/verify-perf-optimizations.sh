#!/usr/bin/env bash
# MeoBrowser 性能/内存优化验收脚本（代码级）。
# Instruments 手工场景见文末 echo；本脚本验证关键路径已落地且工程可编译。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1) 编译 =="
make browser

echo "== 2) 关键实现断言 =="
fail=0
assert_grep() {
  local pattern="$1"
  local file="$2"
  local desc="$3"
  if rg -q "$pattern" "$file"; then
    echo "  OK  $desc"
  else
    echo "  FAIL $desc ($file)"
    fail=1
  fi
}

assert_grep 'prepareForClose' SimpleBrowser/Tabs/BrowserTab.m "关闭时主动释放 WebView"
assert_grep 'about:blank' SimpleBrowser/Tabs/BrowserTab.m "关闭前加载 about:blank"
assert_grep 'ensureWebView' SimpleBrowser/Tabs/BrowserTab.m "NTP/唤醒延迟创建 WebView"
assert_grep 'hibernate' SimpleBrowser/Tabs/BrowserTab.m "标签休眠"
assert_grep 'materialize:NO' SimpleBrowser/Tabs/BrowserTabController.m "会话恢复占位"
assert_grep 'kMaxLiveWebViews' SimpleBrowser/Tabs/BrowserTabController.m "活跃 WebView 上限"
assert_grep 'kHibernateIdleSeconds' SimpleBrowser/Tabs/BrowserTabController.m "空闲休眠计时"
assert_grep 'detachWebViewIfNeeded' SimpleBrowser/BrowserWindowController.m "仅挂载当前 WebView"
assert_grep 'schedulePersistTabSession' SimpleBrowser/BrowserWindowController.m "会话持久化防抖"
assert_grep 'defaultDataStore' SimpleBrowser/BrowserWindowController.m "显式 WebsiteDataStore"
assert_grep 'NSURLCache' SimpleBrowser/BrowserWindowController.m "URLCache 上限"
assert_grep 'loadImageForHost' SimpleBrowser/Favicon/BrowserFaviconCache.m "Favicon 异步读盘"
assert_grep 'sCachedShortcuts' SimpleBrowser/NewTab/BrowserShortcutStore.m "快捷方式内存缓存"
assert_grep 'clearWebsiteDataWithCompletion' SimpleBrowser/BrowsingPreferences.m "清除网站数据 API"
assert_grep 'clearWebsiteDataClicked' SimpleBrowser/BrowserSettingsWindowController.m "设置页清除入口"
assert_grep 'displayLoadGeneration' SimpleBrowser/NewTab/BrowserWallpaperStore.m "墙纸异步解码"
assert_grep 'trafficLightScheduleGeneration' SimpleBrowser/BrowserWindowController.m "交通灯定位风暴收敛"

# imageForHost 不得再 dispatch_sync 读文件
if rg -n 'imageForHost:' -A 25 SimpleBrowser/Favicon/BrowserFaviconCache.m | rg -q 'initWithContentsOfURL'; then
  echo "  FAIL imageForHost 仍含同步读盘"
  fail=1
else
  echo "  OK  imageForHost 无同步读盘"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== 验收失败 =="
  exit 1
fi

cat <<'EOF'
== 3) Instruments 手工场景（建议） ==
1. Allocations：开 10 个重站标签 → Activity Monitor 看 WebContent 进程数
2. 切到新标签页（NTP）→ NTP 不应新建额外 WebContent（延迟创建）
3. 关闭若干标签 → WebContent 进程应在短时间内退出
4. 闲置 >10 分钟或开超 8 个有内容标签 → 非选中标签应休眠（WebView 销毁）
5. Time Profiler：地址栏快速输入 → 主线程无 UserDefaults/favicon 文件 I/O 尖峰
6. 设置 → 清除网站数据 → Cookie/缓存被清空

== 验收通过（代码级） ==
EOF
