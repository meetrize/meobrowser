#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/pb_data"
OUT_DIR="$ROOT/backups"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$OUT_DIR/pb_data-${STAMP}.tgz"
if [[ ! -d "$DATA" ]]; then
  echo "No pb_data yet at $DATA"
  exit 1
fi
tar -C "$ROOT" -czf "$ARCHIVE" pb_data
echo "Backup written: $ARCHIVE"
