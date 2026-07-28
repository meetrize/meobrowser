#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/pocketbase"
if [[ ! -x "$BIN" ]]; then
  echo "Missing $BIN — run ./scripts/download.sh first"
  exit 1
fi
cd "$ROOT"
exec "$BIN" serve --http=127.0.0.1:8090
