#!/usr/bin/env bash
# MeoBrowser 实时调试：增量 .o 编译 +（可选）InjectionIII 热替换 / 否则快速重启。
#
# 哪个更快？
#   InjectionIII 方法热替换 ≈ 1–3s，无需重启（需安装 InjectionIII.app，对本 Makefile 工程偶发不稳）
#   增量 .o + 重启 ≈ 改 1 个文件后数秒～十几秒（可靠，本脚本默认路径）
#
# 用法：
#   make live-browser
#   ./tools/live-browser.sh              # 增量编；有 InjectionIII 则尽量不重启，否则重启
#   ./tools/live-browser.sh --relaunch   # 强制每次编译后重启（最稳）
#   ./tools/live-browser.sh --inject     # 强制 MEO_INJECT=1，不重启（依赖 InjectionIII）
#   ./tools/live-browser.sh --once
#
# 首次会全量编 .o（较慢）；之后只重编改动的 .m 再链接。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="${ROOT}/build/MeoBrowser.app"
APP_NAME="MeoBrowser"
WATCH_DIRS=(SimpleBrowser SBKit)
DEBOUNCE_SEC="${WATCH_DEBOUNCE:-0.6}"
POLL_SEC="${WATCH_POLL:-1}"
ONCE=0
MODE="auto" # auto | relaunch | inject

INJECTION_APP="/Applications/InjectionIII.app"
INJECTION_BUNDLE="${INJECTION_APP}/Contents/Resources/macOSInjection.bundle"

for arg in "$@"; do
  case "$arg" in
    --once) ONCE=1 ;;
    --relaunch) MODE="relaunch" ;;
    --inject) MODE="inject" ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      exit 1
      ;;
  esac
done

ts() { date '+%H:%M:%S'; }

has_injection() {
  [[ -d "${INJECTION_BUNDLE}" ]]
}

kill_app() {
  local pids
  pids="$(pgrep -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi
  echo "[$(ts)] 结束旧进程: ${pids}"
  # shellcheck disable=SC2086
  kill ${pids} 2>/dev/null || true
  sleep 0.2
  # shellcheck disable=SC2086
  kill -9 ${pids} 2>/dev/null || true
}

app_running() {
  pgrep -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1
}

effective_mode() {
  case "${MODE}" in
    relaunch) echo relaunch ;;
    inject) echo inject ;;
    auto)
      if has_injection; then
        echo inject
      else
        echo relaunch
      fi
      ;;
  esac
}

build_browser() {
  local inject_flag="$1"
  if [[ "${inject_flag}" -eq 1 ]]; then
    make browser MEO_INJECT=1
  else
    make browser MEO_INJECT=0
  fi
}

build_and_apply() {
  local reason="${1:-manual}"
  local emode
  emode="$(effective_mode)"
  local use_inject=0
  local do_relaunch=1

  if [[ "${emode}" == "inject" ]]; then
    use_inject=1
    do_relaunch=0
    if ! has_injection; then
      echo "[$(ts)] ⚠ 未找到 InjectionIII（${INJECTION_BUNDLE}），回退为重启模式"
      echo "[$(ts)]   安装: https://github.com/johnno1962/InjectionIII/releases  → /Applications"
      use_inject=0
      do_relaunch=1
    fi
  fi

  # 已在跑且要用热替换：不杀进程，只增量链接；InjectionIII 监听保存自行注入。
  # 若进程未在跑：必须启动一次（带 interposable）。
  if [[ "${use_inject}" -eq 1 ]] && app_running; then
    do_relaunch=0
  elif [[ "${use_inject}" -eq 1 ]] && ! app_running; then
    do_relaunch=1
  fi

  echo ""
  echo "[$(ts)] ── 增量编译（${reason}｜mode=${emode}｜MEO_INJECT=${use_inject}）──"
  local start end elapsed
  start="$(date +%s)"
  if ! build_browser "${use_inject}"; then
    echo "[$(ts)] ✗ 编译失败"
    return 1
  fi
  end="$(date +%s)"
  elapsed=$((end - start))
  echo "[$(ts)] ✓ 编译成功（${elapsed}s）"

  if [[ "${use_inject}" -eq 1 ]]; then
    echo "[$(ts)] InjectionIII：请确保已打开 ${INJECTION_APP}，并用菜单选中本仓库目录"
    echo "[$(ts)] 保存 .m 后看控制台 [MeoInject] / Injection 日志；UI 方法一般可热替换"
    if [[ "${do_relaunch}" -eq 0 ]]; then
      echo "[$(ts)] 未重启进程（热替换模式）。若未见生效：点一下窗口或再保存一次；仍无效则用 --relaunch"
      return 0
    fi
  fi

  if [[ "${do_relaunch}" -eq 1 ]]; then
    kill_app
    echo "[$(ts)] 启动 ${APP_BUNDLE}"
    open "${APP_BUNDLE}"
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

echo "[$(ts)] MeoBrowser live 调试"
echo "[$(ts)] 增量 .o 目录: build/obj/browser/"
echo "[$(ts)] 模式: ${MODE} → $(effective_mode)"
if has_injection; then
  echo "[$(ts)] InjectionIII: 已检测到"
else
  echo "[$(ts)] InjectionIII: 未安装（将用增量编译 + 重启；仍比整包 clang 快很多）"
fi
if command -v fswatch >/dev/null 2>&1; then
  echo "[$(ts)] 文件监听: fswatch"
else
  echo "[$(ts)] 文件监听: 轮询 ${POLL_SEC}s（建议 brew install fswatch）"
fi

build_and_apply "首次"

if [[ "${ONCE}" -eq 1 ]]; then
  exit 0
fi

echo "[$(ts)] 等待变更…（Ctrl+C 退出）"
while true; do
  wait_for_change
  sleep "${DEBOUNCE_SEC}"
  # inject 模式下：保存已由 InjectionIII 自己编译注入；此处再 make 保持 .o 与包同步，便于下次冷启动
  build_and_apply "文件变更" || true
  echo "[$(ts)] 等待下一次变更…"
done
