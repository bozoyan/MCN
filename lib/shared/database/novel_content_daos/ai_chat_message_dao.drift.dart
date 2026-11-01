// dart format width=80
// ignore_for_file: type=lint
part of 'ai_chat_message_dao.dart';

mixin _$AiChatMessageDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $AiChatMessagesTable get aiChatMessages => attachedDatabase.aiChatMessages;
  AiChatMessageDaoManager get managers => AiChatMessageDaoManager(this);
}

class AiChatMessageDaoManager {
  final _$AiChatMessageDaoMixin _db;
  AiChatMessageDaoManager(this._db);
  $$AiChatMessagesTableTableManager get aiChatMessages =>
      $$AiChatMessagesTableTableManager(
        _db.attachedDatabase,
        _db.aiChatMessages,
      );
}
