#!/usr/bin/env bash
# 冒烟：注册 → 登录 → 写入 sync_records → 再读
set -euo pipefail
BASE="${POCKETBASE_URL:-http://127.0.0.1:8090}"
EMAIL="smoke-$(date +%s)@example.com"
PASS="password12345"

echo "== register $EMAIL =="
curl -fsS -X POST "$BASE/api/collections/users/records" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\",\"passwordConfirm\":\"$PASS\"}" >/dev/null

echo "== login =="
AUTH_JSON="$(curl -fsS -X POST "$BASE/api/collections/users/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$EMAIL\",\"password\":\"$PASS\"}")"
TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<<"$AUTH_JSON")"
USER_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["record"]["id"])' <<<"$AUTH_JSON")"
echo "user=$USER_ID"

RID="smoke-$(uuidgen | tr '[:upper:]' '[:lower:]')"
BODY=$(cat <<EOF
{
  "user": "$USER_ID",
  "app_id": "meobrowser",
  "record_id": "$RID",
  "kind": "shortcut",
  "updated_at": $(date +%s),
  "device_id": "smoke-device",
  "deleted": false,
  "schema_version": 1,
  "payload": {"title":"Smoke","url":"https://example.com","order":0,"kind":"link","folderId":"","iconURL":""}
}
EOF
)

echo "== create sync_records =="
curl -fsS -X POST "$BASE/api/collections/sync_records/records" \
  -H "Authorization: $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$BODY" >/dev/null

echo "== list =="
curl -fsS "$BASE/api/collections/sync_records/records?filter=(app_id%3D%27meobrowser%27)&perPage=5" \
  -H "Authorization: $TOKEN" | python3 -m json.tool | head -40

echo "OK smoke passed"
