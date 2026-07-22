#!/usr/bin/env bash
# 打开 Google TalkBack（+ 可选 MIUI 读屏增强 + Meo 微信回复无障碍）
# 会校验 dumpsys 是否真正 Bound，避免「settings 写了但没生效」。
set -euo pipefail

COMPANION_A11Y='com.meobrowser.companion/com.meobrowser.companion.a11y.WeChatReplyAccessibilityService'
# 短组件名在 HyperOS / 新版 TalkBack 上更稳
TB='com.google.android.marvin.talkback/.TalkBackService'
MIUI='com.miui.accessibility/com.miui.accessibility.enhance.tb.MiuiEnhanceTBService'

DEVICE="${ANDROID_SERIAL:-}"

usage() {
  cat <<'EOF'
用法: ./talkback-on.sh [-s SERIAL]

打开 TalkBack，并保留/拉起 Meo「微信回复」无障碍与 MIUI 读屏增强。
多台手机时必须用 -s 或 ANDROID_SERIAL，否则可能改到另一台设备。

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
  echo "示例: ./talkback-on.sh -s $(printf '%s\n' "$devices" | head -1)" >&2
  exit 1
fi

serial="$("${ADB[@]}" get-serialno)"
echo "设备: $serial"

talkback_bound() {
  "${ADB[@]}" shell dumpsys accessibility 2>/dev/null | grep -q 'label=TalkBack'
}

talkback_installed() {
  "${ADB[@]}" shell pm path com.google.android.marvin.talkback >/dev/null 2>&1
}

if ! talkback_installed; then
  echo "错误: 未安装 Google TalkBack (com.google.android.marvin.talkback)" >&2
  echo "请先在应用商店安装「TalkBack / Android Accessibility Suite」。" >&2
  exit 1
fi

echo "1/4 强制重启 TalkBack 进程…"
"${ADB[@]}" shell am force-stop com.google.android.marvin.talkback >/dev/null 2>&1 || true
sleep 0.4

echo "2/4 先单独启用 TalkBack…"
"${ADB[@]}" shell settings put secure accessibility_enabled 1
"${ADB[@]}" shell settings put secure touch_exploration_enabled 1
"${ADB[@]}" shell settings put secure enabled_accessibility_services "$TB"
sleep 0.8

# 再拨一次 accessibility 总开关，促使系统重新绑定
"${ADB[@]}" shell settings put secure accessibility_enabled 0
sleep 0.4
"${ADB[@]}" shell settings put secure accessibility_enabled 1
"${ADB[@]}" shell settings put secure enabled_accessibility_services "$TB"
"${ADB[@]}" shell settings put secure touch_exploration_enabled 1

bound=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if talkback_bound; then
    bound=1
    echo "   TalkBack 已绑定 (尝试 $i)"
    break
  fi
  sleep 0.4
done

if [[ "$bound" -ne 1 ]]; then
  echo "警告: settings 写入后仍未 Bound，尝试打开 TalkBack 设置页供手动确认…" >&2
  "${ADB[@]}" shell am start -n \
    com.google.android.marvin.talkback/com.android.talkback.TalkBackPreferencesActivity \
    >/dev/null 2>&1 || \
  "${ADB[@]}" shell am start -a android.settings.ACCESSIBILITY_DETAILS_SETTINGS \
    -e android.intent.extra.COMPONENT_NAME "$TB" >/dev/null 2>&1 || \
  "${ADB[@]}" shell am start -a android.settings.ACCESSIBILITY_SETTINGS >/dev/null 2>&1 || true
  sleep 1.5
  if talkback_bound; then
    bound=1
    echo "   TalkBack 已绑定"
  fi
fi

echo "3/4 叠加 Meo 微信回复无障碍 + MIUI 读屏增强（不踢掉 TalkBack）…"
"${ADB[@]}" shell settings put secure enabled_accessibility_services "$TB:$COMPANION_A11Y:$MIUI"
"${ADB[@]}" shell settings put secure accessibility_enabled 1
"${ADB[@]}" shell settings put secure touch_exploration_enabled 1
sleep 1.2

echo "4/4 校验…"
echo "settings: $("${ADB[@]}" shell settings get secure enabled_accessibility_services)"
echo "touch_exploration=$("${ADB[@]}" shell settings get secure touch_exploration_enabled)"
"${ADB[@]}" shell dumpsys accessibility 2>/dev/null | grep -E 'Bound services:|Enabled services:|Crashed services:' | head -6 || true
pid="$("${ADB[@]}" shell pidof com.google.android.marvin.talkback 2>/dev/null || true)"
echo "TalkBack pid: ${pid:-无}"

if talkback_bound && [[ -n "${pid:-}" ]]; then
  echo "成功: TalkBack 已在跑。手指需先点选再双击；用 ./talkback-off.sh 可临时关掉。"
  exit 0
fi

echo "失败: TalkBack 仍未真正打开。" >&2
echo "请在手机上手动: 设置 → 更多设置 → 无障碍 → TalkBack → 打开" >&2
echo "若有多台手机，请加: ./talkback-on.sh -s <序列号>" >&2
exit 1
