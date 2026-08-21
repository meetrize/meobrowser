#!/usr/bin/env bash
# MeoBrowser 保存即编译并重启（调试 UI / 地址栏微调用）。
#
# 用法：
#   ./tools/watch-browser.sh              # 监听 SimpleBrowser + SBKit，改完自动 rebuild + 重启
#   ./tools/watch-browser.sh --once       # 只编一次并启动
#   ./tools/watch-browser.sh --no-relaunch # 只编译，不杀进程重启
#   make watch-browser
#
# 说明：
# - 当前 Makefile 是整包 clang 一次链出，单次约 30–50s，不是方法级热重载。
# - 「立刻生效」= 编译成功后自动关掉旧 MeoBrowser 再 open 新包。
# - 依赖：优先 fswatch（brew install fswatch）；没有则 1s 轮询 mtime。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="${ROOT}/build/MeoBrowser.app"
APP_NAME="MeoBrowser"
WATCH_DIRS=(SimpleBrowser SBKit)
DEBOUNCE_SEC="${WATCH_DEBOUNCE:-0.8}"
POLL_SEC="${WATCH_POLL:-1}"
RELAUNCH=1
ONCE=0

for arg in "$@"; do
  case "$arg" in
    --once) ONCE=1 ;;
    --no-relaunch) RELAUNCH=0 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg（可用 --once / --no-relaunch）" >&2
      exit 1
      ;;
  esac
done

ts() { date '+%H:%M:%S'; }

kill_app() {
  local pids
  pids="$(pgrep -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi
  echo "[$(ts)] 结束旧进程: ${pids}"
  # shellcheck disable=SC2086
  kill ${pids} 2>/dev/null || true
  sleep 0.25
  # shellcheck disable=SC2086
  kill -9 ${pids} 2>/dev/null || true
}

build_and_run() {
  local reason="${1:-manual}"
  echo ""
  echo "[$(ts)] ── 编译（${reason}）──"
  local start end elapsed
  start="$(date +%s)"
  if ! make browser; then
    echo "[$(ts)] ✗ 编译失败，保持旧进程，改完会再试"
    return 1
  fi
  end="$(date +%s)"
  elapsed=$((end - start))
  echo "[$(ts)] ✓ 编译成功（${elapsed}s）"

  if [[ "${RELAUNCH}" -eq 1 ]]; then
    kill_app
    echo "[$(ts)] 启动 ${APP_BUNDLE}"
    open "${APP_BUNDLE}"
  else
    echo "[$(ts)] 已跳过重启（--no-relaunch）"
  fi
}

snapshot_mtimes() {
  find "${WATCH_DIRS[@]}" Makefile \
    \( -name '*.m' -o -name '*.h' -o -name 'Makefile' \) \
    -print0 2>/dev/null \
    | xargs -0 stat -f '%N|%m' 2>/dev/null \
    | sort
}

wait_for_change() {
  if command -v fswatch >/dev/null 2>&1; then
    # 任一变更即返回；随后由主循环 sleep 防抖
    fswatch -1 -r \
      --event Updated --event Created --event Removed --event Renamed \
      "${WATCH_DIRS[@]}" Makefile >/dev/null || true
  else
    local before after
    before="$(snapshot_mtimes)"
    while true; do
      sleep "${POLL_SEC}"
      after="$(snapshot_mtimes)"
      if [[ "${before}" != "${after}" ]]; then
        return 0
      fi
    done
  fi
}

echo "[$(ts)] MeoBrowser watch 调试"
echo "[$(ts)] 仓库: ${ROOT}"
echo "[$(ts)] 监听: ${WATCH_DIRS[*]} + Makefile"
echo "[$(ts)] 防抖: ${DEBOUNCE_SEC}s  relaunch=$([[ ${RELAUNCH} -eq 1 ]] && echo ON || echo OFF)"

if command -v fswatch >/dev/null 2>&1; then
  echo "[$(ts)] 使用 fswatch"
else
  echo "[$(ts)] 未找到 fswatch → ${POLL_SEC}s 轮询（建议: brew install fswatch）"
fi

build_and_run "首次"

if [[ "${ONCE}" -eq 1 ]]; then
  exit 0
fi

echo "[$(ts)] 等待文件变更…（Ctrl+C 退出）"
while true; do
  wait_for_change
  sleep "${DEBOUNCE_SEC}"
  build_and_run "文件变更" || true
  echo "[$(ts)] 等待下一次变更…"
done
