#!/usr/bin/env bash
# 一键编译、安装并启动 Meo Companion（debug）到已连接的 Android 手机
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ID="com.meobrowser.companion"
LAUNCHER="${APP_ID}/.browser.BrowserActivity"
APK_DEBUG="${ROOT}/app/build/outputs/apk/debug/app-debug.apk"

DEVICE=""
NO_LAUNCH=0
BUILD_ONLY=0
INSTALL_ALL=0

usage() {
  cat <<'EOF'
用法: ./one-click-deploy.sh [选项]

一键：assembleDebug → adb install -r → 启动 App

选项:
  -s, --serial <id>   指定设备序列号（多机时必填，或设 ANDROID_SERIAL）
  -a, --all           安装到所有已连接设备
  -b, --build-only    只编译，不安装
  -n, --no-launch     安装后不自动启动
  -h, --help          显示帮助

示例:
  ./one-click-deploy.sh
  ./one-click-deploy.sh -s 4eed0b60
  ./one-click-deploy.sh -a
  ANDROID_SERIAL=64e9b4e6 ./one-click-deploy.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial)
      DEVICE="${2:-}"
      [[ -n "$DEVICE" ]] || { echo "错误: --serial 需要设备序列号" >&2; exit 1; }
      shift 2
      ;;
    -a|--all)
      INSTALL_ALL=1
      shift
      ;;
    -b|--build-only)
      BUILD_ONLY=1
      shift
      ;;
    -n|--no-launch)
      NO_LAUNCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

log() { printf '==> %s\n' "$*"; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }

# --- 环境 ---
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="${ANDROID_HOME}/platform-tools:${PATH}"

if [[ -z "${JAVA_HOME:-}" ]]; then
  if [[ -d "$HOME/Library/Java/JavaVirtualMachines/jbr-17.0.14/Contents/Home" ]]; then
    export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/jbr-17.0.14/Contents/Home"
  elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
  fi
fi

command -v adb >/dev/null 2>&1 || die "未找到 adb。请安装 Android SDK platform-tools，或设置 ANDROID_HOME。"
[[ -x "${ROOT}/gradlew" ]] || die "未找到 gradlew：${ROOT}/gradlew"

if [[ ! -f "${ROOT}/local.properties" ]]; then
  log "写入 local.properties（sdk.dir=${ANDROID_HOME}）"
  printf 'sdk.dir=%s\n' "${ANDROID_HOME}" > "${ROOT}/local.properties"
fi

list_devices() {
  adb devices | awk 'NR>1 && $2=="device" { print $1 }'
}

resolve_targets() {
  local devices device found
  devices="$(list_devices)"
  if [[ -z "$devices" ]]; then
    die "没有已授权的设备。请用 USB 连接手机并开启「USB 调试」，在手机上点允许。"
  fi

  if [[ -n "$DEVICE" ]]; then
    found=0
    while IFS= read -r device; do
      if [[ "$device" == "$DEVICE" ]]; then
        found=1
        break
      fi
    done <<< "$devices"
    [[ $found -eq 1 ]] || die "指定设备不在线: ${DEVICE}"$'\n'"当前:"$'\n'"${devices}"
    echo "$DEVICE"
    return
  fi

  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    echo "$ANDROID_SERIAL"
    return
  fi

  if [[ $INSTALL_ALL -eq 1 ]]; then
    echo "$devices"
    return
  fi

  local count
  count="$(printf '%s\n' "$devices" | grep -c . || true)"
  if [[ "$count" -eq 1 ]]; then
    echo "$devices"
    return
  fi

  echo "检测到多台设备，请用 -s <serial> 指定，或加 -a 安装到全部：" >&2
  adb devices -l >&2
  die "多设备时必须指定目标"
}

# --- 编译 ---
cd "$ROOT"
log "编译 debug APK（JDK: ${JAVA_HOME:-系统默认}）..."
./gradlew --quiet assembleDebug

[[ -f "$APK_DEBUG" ]] || die "未找到 APK: ${APK_DEBUG}"
log "APK: ${APK_DEBUG}"

if [[ $BUILD_ONLY -eq 1 ]]; then
  log "仅编译完成（--build-only）"
  exit 0
fi

# --- 安装 / 启动 ---
TARGETS="$(resolve_targets)"
COUNT=0
while IFS= read -r serial; do
  [[ -z "$serial" ]] && continue
  COUNT=$((COUNT + 1))
  log "安装到 ${serial} ..."
  adb -s "$serial" install -r "$APK_DEBUG"

  if [[ $NO_LAUNCH -eq 0 ]]; then
    log "启动 ${LAUNCHER} @ ${serial}"
    adb -s "$serial" shell am start -n "$LAUNCHER" >/dev/null
  fi
done <<< "$TARGETS"

log "完成（${COUNT} 台设备）"
printf '%s\n' "$TARGETS"
