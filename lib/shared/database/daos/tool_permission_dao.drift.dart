// dart format width=80
// ignore_for_file: type=lint
part of 'tool_permission_dao.dart';

mixin _$ToolPermissionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ToolPermissionRulesTable get toolPermissionRules =>
      attachedDatabase.toolPermissionRules;
  ToolPermissionDaoManager get managers => ToolPermissionDaoManager(this);
}

class ToolPermissionDaoManager {
  final _$ToolPermissionDaoMixin _db;
  ToolPermissionDaoManager(this._db);
  $$ToolPermissionRulesTableTableManager get toolPermissionRules =>
      $$ToolPermissionRulesTableTableManager(
        _db.attachedDatabase,
        _db.toolPermissionRules,
      );
}
