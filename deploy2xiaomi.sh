#!/usr/bin/env bash
# 一键部署 Meo Companion 到小米手机（serial: 64e9b4e6）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ANDROID_APP="${ROOT}/companion/android/MeoCompanion"
DEPLOY="${ANDROID_APP}/one-click-deploy.sh"

[[ -x "$DEPLOY" ]] || {
  echo "错误: 未找到部署脚本: ${DEPLOY}" >&2
  exit 1
}

exec "$DEPLOY" -s 64e9b4e6 "$@"
