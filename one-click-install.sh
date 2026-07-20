#!/usr/bin/env bash
# 本地一键编译并安装 MeoBrowser 到 /Applications（含 root 密码，勿提交）
set -euo pipefail

ROOT_PASSWORD="dddd"
APP_NAME="MeoBrowser"
BUNDLE="build/${APP_NAME}.app"
INSTALL_DIR="/Applications/${APP_NAME}.app"

cd "$(dirname "$0")"

echo "==> 编译 ${APP_NAME} ..."
make browser

if [[ ! -d "$BUNDLE" ]]; then
  echo "错误: 未找到 ${BUNDLE}" >&2
  exit 1
fi

echo "==> 安装到 ${INSTALL_DIR} ..."
# 若正在运行则先退出，避免覆盖失败
if pgrep -xq "$APP_NAME" >/dev/null 2>&1; then
  echo "正在退出已运行的 ${APP_NAME} ..."
  osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
  sleep 1
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "$ROOT_PASSWORD" | sudo -S -p '' bash -c "
  rm -rf '${INSTALL_DIR}'
  cp -R '${BUNDLE}' '${INSTALL_DIR}'
  chown -R root:wheel '${INSTALL_DIR}'
"

echo "==> 安装完成: ${INSTALL_DIR}"
echo "可执行: open -a ${APP_NAME}"
