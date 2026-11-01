// dart format width=80
// ignore_for_file: type=lint
part of 'ai_chat_session_dao.dart';

mixin _$AiChatSessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiChatSessionsTable get aiChatSessions => attachedDatabase.aiChatSessions;
  AiChatSessionDaoManager get managers => AiChatSessionDaoManager(this);
}

class AiChatSessionDaoManager {
  final _$AiChatSessionDaoMixin _db;
  AiChatSessionDaoManager(this._db);
  $$AiChatSessionsTableTableManager get aiChatSessions =>
      $$AiChatSessionsTableTableManager(
        _db.attachedDatabase,
        _db.aiChatSessions,
      );
}
