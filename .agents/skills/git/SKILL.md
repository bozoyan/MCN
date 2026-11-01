---
name: git
description: "Git 操作规范与指南：rebase 冲突处理、DB migration 版本冲突解决、工作流程。适用于 rebase、merge、DB migration 版本号冲突等场景。"
---

# Git 规范

## Rebase 冲突处理规则

- 解决 git rebase 冲突时，禁止执行 `git rebase --continue`。因为该命令会打开交互式编辑器，而非交互式环境无法处理。
- 冲突解决后应报告给用户，由用户手动执行 `git rebase --continue` 操作。

## Rebase 冲突的内容取舍判据

rebase 把旧提交叠到新基之上，方向与 merge 相反，冲突双方含义也相反：

- `<<<<<<< HEAD` = **新基**（要叠上去的底）
- `>>>>>>> <commit>` = **自己的旧提交**（被回放者）

取舍判据不是「哪边更新取哪边」，而是「新基的决定是基准，旧提交只能增量」：

- 旧提交**纯新增**了新基没有的内容 -> 保留
- 旧提交把新基已删除 / 迁移 / 重命名的内容又带回来 -> 丢弃（不得复活新基已删除的内容）

「旧提交更完整」可能是把新基刻意删掉的东西补了回来，不是合并收益。先 `git show <new-base>:<file>` 看新基对该区域的实际动作（删除 / 搬迁 / 未触碰），再决定取舍。

## Rebase 中的 DB Migration 版本冲突解决

在 rebase 过程中，两个分支可能同时添加了同一个 schema 版本号（如双方都写了 `migrateToV13`），导致冲突。

### 识别冲突

冲突表现为以下之一：
- `app_database_migrations.dart` 中出现两个同名 `migrateToV{n}` 方法
- `app_database.dart` 的 `schemaVersion` 数值冲突
- `onUpgrade` 调用链中两个分支对同一版本号做了不同的事

### 解决原则

1. **保留 base（上游分支）的版本号**。被 rebase 到的目标分支（通常是 `development` / `master`）的迁移版本号保持不变。
2. **feature 分支的 schema 改动移到下一个可用版本号**。将冲突的 `migrateToV{n}` 重命名为 `migrateToV{n+1}`，同步更新：
   - `schemaVersion`（提升到 `n+1`）
   - `onUpgrade` 中添加对应版本的调用：`if (from < n+1) { await migrations.migrateToV{n+1}(migrator); }`

### 原因

base 分支（上游分支）的 schema 已在发布或已部署的数据库中生效。改变 base 的版本号会破坏已有用户的数据库升级路径。feature 分支尚未发布，其 schema 变更可以延后到下一个版本号。

### 操作步骤

1. 定位冲突的 `migrateToV{n}` 方法
2. 保留 base 版本，将 feature 版本重命名为 `migrateToV{n+1}`（更新注释和方法名）
3. 在 `app_database.dart` 中将 `schemaVersion` 更新为 `n+1`
4. 在 `onUpgrade` 中添加调用：`if (from < n+1) { await migrations.migrateToV{n+1}(migrator); }`
5. 检查 migration 测试是否引用 `schemaVersion`（通常用 `db.schemaVersion` 动态获取，无需改动）
6. Stage 修改：`git add <files>`
7. 报告用户手动执行 `git rebase --continue`
