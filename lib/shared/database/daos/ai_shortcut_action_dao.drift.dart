// dart format width=80
// ignore_for_file: type=lint
part of 'ai_shortcut_action_dao.dart';

mixin _$AiShortcutActionDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiShortcutActionsTable get aiShortcutActions =>
      attachedDatabase.aiShortcutActions;
  AiShortcutActionDaoManager get managers => AiShortcutActionDaoManager(this);
}

class AiShortcutActionDaoManager {
  final _$AiShortcutActionDaoMixin _db;
  AiShortcutActionDaoManager(this._db);
  $$AiShortcutActionsTableTableManager get aiShortcutActions =>
      $$AiShortcutActionsTableTableManager(
        _db.attachedDatabase,
        _db.aiShortcutActions,
      );
}
