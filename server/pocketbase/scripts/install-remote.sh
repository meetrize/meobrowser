#!/usr/bin/env bash
# 在目标 Linux 主机上安装 / 升级 Meo PocketBase（由本地 sshpass 调用）
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/meo-pocketbase}"
VERSION="${POCKETBASE_VERSION:-0.25.8}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASS="${ADMIN_PASS:?请设置 ADMIN_PASS 环境变量}"
HTTP_ADDR="${HTTP_ADDR:-0.0.0.0:8090}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

echo "== install dirs =="
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/pb_migrations" "$INSTALL_DIR/pb_data" /var/backups/meo-pocketbase

if [[ ! -x "$INSTALL_DIR/bin/pocketbase" ]]; then
  echo "== download PocketBase v${VERSION} linux_${ARCH} =="
  TMP="$(mktemp -d)"
  ASSET="pocketbase_${VERSION}_linux_${ARCH}.zip"
  URL="https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/${ASSET}"
  curl -fsSL -o "$TMP/pb.zip" "$URL"
  unzip -o "$TMP/pb.zip" -d "$TMP"
  mv "$TMP/pocketbase" "$INSTALL_DIR/bin/pocketbase"
  chmod +x "$INSTALL_DIR/bin/pocketbase"
  rm -rf "$TMP"
fi

"$INSTALL_DIR/bin/pocketbase" --version || true

echo "== systemd unit =="
cat > /etc/systemd/system/meo-pocketbase.service <<EOF
[Unit]
Description=Meo PocketBase sync server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/pocketbase serve --http=$HTTP_ADDR --dir=$INSTALL_DIR/pb_data --migrationsDir=$INSTALL_DIR/pb_migrations
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable meo-pocketbase

# 先停再启，确保 migrations 生效
systemctl stop meo-pocketbase || true
# 首次启动前创建管理员（幂等）
cd "$INSTALL_DIR"
./bin/pocketbase superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS" --dir="$INSTALL_DIR/pb_data" || true

systemctl start meo-pocketbase
sleep 2
systemctl --no-pager --full status meo-pocketbase || true

# 防火墙（若存在）
if command -v ufw >/dev/null 2>&1; then
  ufw allow 8090/tcp || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=8090/tcp || true
  firewall-cmd --reload || true
fi

echo "== health =="
curl -fsS "http://127.0.0.1:8090/api/health" || curl -fsS "http://127.0.0.1:8090/" | head -c 200 || true
echo
echo "Installed at $INSTALL_DIR ; listen $HTTP_ADDR"
