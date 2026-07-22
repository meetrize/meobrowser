#!/usr/bin/env bash
# 临时关闭 TalkBack / MIUI 读屏，恢复手指点击（保留 Meo「微信回复」无障碍）
set -euo pipefail

COMPANION_A11Y='com.meobrowser.companion/com.meobrowser.companion.a11y.WeChatReplyAccessibilityService'
TB_PKG='com.google.android.marvin.talkback'

DEVICE="${ANDROID_SERIAL:-}"

usage() {
  cat <<'EOF'
用法: ./talkback-off.sh [-s SERIAL]

关掉 TalkBack / MIUI 读屏，恢复普通手指点击；仍保留 Meo「微信回复」无障碍。
多台手机时必须用 -s 或 ANDROID_SERIAL。

选项:
  -s, --serial <id>   设备序列号
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial)
      DEVICE="${2:-}"
      [[ -n "$DEVICE" ]] || { echo "错误: --serial 需要设备序列号" >&2; exit 1; }
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

ADB=(adb)
if [[ -n "$DEVICE" ]]; then
  ADB=(adb -s "$DEVICE")
fi

devices="$("${ADB[@]}" devices | awk 'NR>1 && $2=="device" {print $1}')"
count="$(printf '%s\n' "$devices" | awk 'NF' | wc -l | tr -d ' ')"
if [[ "$count" -eq 0 ]]; then
  echo "错误: 没有可用设备" >&2
  exit 1
fi
if [[ -z "$DEVICE" && "$count" -gt 1 ]]; then
  echo "错误: 检测到多台设备，请指定序列号：" >&2
  printf '%s\n' "$devices" >&2
  echo "示例: ./talkback-off.sh -s $(printf '%s\n' "$devices" | head -1)" >&2
  exit 1
fi

serial="$("${ADB[@]}" get-serialno)"
echo "设备: $serial"

"${ADB[@]}" shell settings put secure enabled_accessibility_services "$COMPANION_A11Y"
"${ADB[@]}" shell settings put secure accessibility_enabled 1
"${ADB[@]}" shell settings put secure touch_exploration_enabled 0
"${ADB[@]}" shell am force-stop "$TB_PKG" >/dev/null 2>&1 || true
sleep 0.5

echo "settings: $("${ADB[@]}" shell settings get secure enabled_accessibility_services)"
echo "touch_exploration=$("${ADB[@]}" shell settings get secure touch_exploration_enabled)"
if "${ADB[@]}" shell dumpsys accessibility 2>/dev/null | grep -q 'label=TalkBack'; then
  echo "警告: dumpsys 仍看到 TalkBack Bound，可再执行一次或手动关闭。" >&2
else
  echo "成功: 已关闭 TalkBack，手指可正常点击。"
fi
