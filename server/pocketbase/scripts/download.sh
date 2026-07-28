#!/usr/bin/env bash
# 下载 PocketBase 到 server/pocketbase/bin/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/bin"
mkdir -p "$BIN_DIR"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

# 版本可按需调整；见 https://github.com/pocketbase/pocketbase/releases
VERSION="${POCKETBASE_VERSION:-0.25.8}"
ASSET="pocketbase_${VERSION}_${OS}_${ARCH}.zip"
URL="https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/${ASSET}"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# 支持本地代理：HTTPS_PROXY / ALL_PROXY，或默认探测 127.0.0.1:7890
if [[ -z "${HTTPS_PROXY:-}${https_proxy:-}${ALL_PROXY:-}${all_proxy:-}" ]]; then
  if curl -fsS -x http://127.0.0.1:7890 --connect-timeout 1 -o /dev/null http://127.0.0.1:7890 2>/dev/null \
     || nc -z 127.0.0.1 7890 2>/dev/null; then
    export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7890}"
    export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7890}"
    echo "Using local proxy $HTTPS_PROXY"
  fi
fi

echo "Downloading $URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL ${HTTPS_PROXY:+-x "$HTTPS_PROXY"} -o "$TMP/pb.zip" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$TMP/pb.zip" "$URL"
else
  echo "Need curl or wget"; exit 1
fi

unzip -o "$TMP/pb.zip" -d "$TMP"
mv "$TMP/pocketbase" "$BIN_DIR/pocketbase"
chmod +x "$BIN_DIR/pocketbase"
echo "Installed: $BIN_DIR/pocketbase"
"$BIN_DIR/pocketbase" --version || true
