# 数据库 migration 规则

- 向已有 Drift 表添加字段时，必须同时做三件事：
  1. 在 `lib/shared/database/novel_content_database.dart`（或对应 database 文件）中提升 `schemaVersion`（当前值加 1）
  2. 在 `onUpgrade` 回调中添加对应版本号的 migration 步骤，使用 `migrator.addColumn(table, table.newColumn)` 或 `customStatement` 执行 `ALTER TABLE`
  3. 在该表对应的 `@DataClass` 或模型 Dart 类中添加新字段
- 不满足以上三点的 schema 修改**禁止合入**。只改 Dart 表定义不改版本号和 migration，会导致已有数据库静默不生效，新列根本不存在，写入无报错但数据丢失。
- 开发过程中如果已部署的数据库与当前 schemaVersion 不一致，可用 `PRAGMA user_version` 确认数据库当前版本。

## 历史表重建与当前 schema

- Drift 的历史 migration 会使用当前生成的表定义。给表新增字段后，旧版本中的裸 `TableMigration(table)` 也会把该字段加入 copy SQL；如果旧表没有该列，跨版本升级可能直接失败，或在启用 SQLite 双引号字符串兼容时把列名文本写入数据。
- 给已有表新增、重命名或删除字段时，必须搜索该表的全部历史 `TableMigration`，以及手写的 rename/create/copy 表重建。逐个核对对应源版本实际拥有的列，禁止假设只执行最新 migration 就足够。
- 表重建的目标字段在源版本中不存在时，必须在 `TableMigration` 中同时通过 `newColumns` 声明，并用 `columnTransformer` 为已有行提供明确值；也可以在重建前先以幂等方式补列。非空字段不得依赖 SQLite 隐式行为或双引号字符串兼容。
- 历史 migration 需要兼容 schema 漂移：在把字段视为新增前先检查实际列是否存在；已存在时必须保留原值，缺失时才执行补列或默认值转换。
- 手写表重建必须在 `INSERT ... SELECT` 两侧显式列出字段；目标表中未参与复制的字段必须可空、有数据库默认值或显式回填，禁止依赖当前 `createTable` 生成结果碰巧兼容旧行。

## 发布升级回归

- 每次数据库变更必须测试从所有仍受支持的正式发布 schema 直接升级到当前 schema，不能只测相邻版本。至少覆盖上一正式版、受影响表最近一次重建前的正式版，以及本次字段变更前的正式版。
- migration 测试必须使用旧版真实结构的 SQLite fixture，并至少断言：最终 `user_version`、主键/索引等结构、旧记录数量与关键字段值、以及新增字段的 SQLite 类型和值。只断言“打开成功”或“列存在”不足以防止数据污染。
- 对 Drift 表执行重建后，必须通过对应 Typed DAO 读取至少一条迁移记录。这样可捕获 SQLite 将缺失的双引号标识符当成文本后，结构检查仍通过的假绿灯。
