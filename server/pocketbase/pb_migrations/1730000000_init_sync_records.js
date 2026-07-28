/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  // MVP：开放注册（生产可改为仅管理员创建或邀请码）
  users.createRule = "";
  app.save(users);

  const collection = new Collection({
    type: "base",
    name: "sync_records",
    listRule: '@request.auth.id != "" && user = @request.auth.id',
    viewRule: '@request.auth.id != "" && user = @request.auth.id',
    createRule: '@request.auth.id != "" && user = @request.auth.id',
    updateRule: '@request.auth.id != "" && user = @request.auth.id',
    deleteRule: '@request.auth.id != "" && user = @request.auth.id',
    fields: [
      {
        name: "user",
        type: "relation",
        required: true,
        collectionId: users.id,
        cascadeDelete: true,
        maxSelect: 1,
      },
      { name: "app_id", type: "text", required: true },
      { name: "record_id", type: "text", required: true },
      { name: "kind", type: "text", required: true },
      { name: "updated_at", type: "number", required: true },
      { name: "device_id", type: "text", required: true },
      // PocketBase 将 required bool 的 false 视为空白，故 deleted 不可 required
      { name: "deleted", type: "bool", required: false },
      { name: "schema_version", type: "number", required: true },
      { name: "payload", type: "json", required: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_sync_records_user_app_record ON sync_records (user, app_id, record_id)",
    ],
  });
  app.save(collection);
}, (app) => {
  try {
    const collection = app.findCollectionByNameOrId("sync_records");
    app.delete(collection);
  } catch (_) {}
});
