# 建表检查清单（Admin UI）

详见 docs/minimal-browser/server-sync-design.md §3.3～§3.4。

- [ ] Collection `sync_records` (Base)
- [ ] Fields: user, app_id, record_id, kind, updated_at, device_id, deleted, schema_version, payload
- [ ] Unique index on (user, app_id, record_id)
- [ ] API Rules: auth user owns row for list/view/create/update/delete
- [ ] Users: registration enabled for MVP (tighten later)
- [ ] Run scripts/smoke-test.sh
