// dart format width=80
// ignore_for_file: type=lint
part of 'assistant_inbox_dao.dart';

mixin _$AssistantInboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $AssistantInboxTable get assistantInbox => attachedDatabase.assistantInbox;
  AssistantInboxDaoManager get managers => AssistantInboxDaoManager(this);
}

class AssistantInboxDaoManager {
  final _$AssistantInboxDaoMixin _db;
  AssistantInboxDaoManager(this._db);
  $$AssistantInboxTableTableManager get assistantInbox =>
      $$AssistantInboxTableTableManager(
        _db.attachedDatabase,
        _db.assistantInbox,
      );
}
