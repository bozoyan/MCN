// 职责: 验证记忆提取/消化在 client 无响应时超时返回，不把调度器永久挂住。
// 关联文件:
//   lib/shared/services/ai/memory_extraction_service.dart
//   lib/shared/services/ai/memory_dreaming_service.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/memory_dreaming_service.dart';
import 'package:reveric/shared/services/ai/memory_extraction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;

  setUp(() => appDb = AppDatabase.forTest(NativeDatabase.memory()));
  tearDown(() async => appDb.close());

  test('记忆提取：client 不返回时超时并给出空结果', () async {
    const novelId = 'novel_timeout';
    await appDb.aiChatSessionDao.upsert(
      id: 'session_1',
      novelId: novelId,
      title: '对话',
    );
    final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(contentDb.close);
    await contentDb.aiChatMessageDao.replace(
      sessionId: 'session_1',
      messages: [
        AiChatMessagesCompanion.insert(
          id: 'msg_1',
          sessionId: 'session_1',
          role: 'user',
          content: const Value('我想用第一人称写。'),
        ),
      ],
    );

    final hang = Completer<AiClient?>();
    final service = MemoryExtractionService(
      appDb: appDb,
      clientFactory: () => hang.future,
      timeout: const Duration(milliseconds: 30),
    );

    final result = await service.extractFromChat(
      novelId: novelId,
      contentDb: contentDb,
    );

    expect(result, isEmpty);
  });

  test('记忆消化：client 不返回时超时并返回 0 变更', () async {
    const novelId = 'novel_timeout';
    await appDb.memoryDao.create(
      id: 'mem_1',
      category: memoryCategoryFact,
      content: '主角是林风',
      novelId: novelId,
    );
    await appDb.memoryDao.create(
      id: 'mem_2',
      category: memoryCategoryFact,
      content: '主角林风是退役特种兵',
      novelId: novelId,
    );

    final hang = Completer<AiClient?>();
    final service = MemoryDreamingService(
      appDb: appDb,
      clientFactory: () => hang.future,
      timeout: const Duration(milliseconds: 30),
    );

    expect(await service.dream(novelId: novelId), 0);
  });
}
