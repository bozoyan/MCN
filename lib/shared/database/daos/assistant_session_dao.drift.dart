// dart format width=80
// ignore_for_file: type=lint
part of 'assistant_session_dao.dart';

mixin _$AssistantSessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $AssistantSessionsTable get assistantSessions =>
      attachedDatabase.assistantSessions;
  $AssistantMessagesTable get assistantMessages =>
      attachedDatabase.assistantMessages;
  AssistantSessionDaoManager get managers => AssistantSessionDaoManager(this);
}

class AssistantSessionDaoManager {
  final _$AssistantSessionDaoMixin _db;
  AssistantSessionDaoManager(this._db);
  $$AssistantSessionsTableTableManager get assistantSessions =>
      $$AssistantSessionsTableTableManager(
        _db.attachedDatabase,
        _db.assistantSessions,
      );
  $$AssistantMessagesTableTableManager get assistantMessages =>
      $$AssistantMessagesTableTableManager(
        _db.attachedDatabase,
        _db.assistantMessages,
      );
}
