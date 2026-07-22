#!/usr/bin/env bash
# 兼容入口：转发到仓库根目录的 talkback-on.sh / talkback-off.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# dirname = .../MeoCompanion → ../../../ = repo root? 
# $0 = companion/android/MeoCompanion/talkback-toggle.sh
# dirname = MeoCompanion, ../ = android, ../../ = companion, ../../../ = repo root
MODE=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    off|on) MODE="$1"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
if [[ -z "$MODE" ]]; then
  echo "用法: ./talkback-toggle.sh <off|on> [-s SERIAL]" >&2
  exit 1
fi
if [[ "$MODE" == "off" ]]; then
  exec "$ROOT/talkback-off.sh" "${ARGS[@]+"${ARGS[@]}"}"
else
  exec "$ROOT/talkback-on.sh" "${ARGS[@]+"${ARGS[@]}"}"
fi
