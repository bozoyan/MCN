// 职责: 验证新对话的延续提议在来源页面卸载后仍能完成，并安全处理空来源、查询失败和应用退出。
// 关联文件:
//   lib/shared/providers/chat_continue_offer_provider.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/database/novel_content_daos/ai_chat_message_dao.dart

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/novel_content_daos/ai_chat_message_dao.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/providers/chat_continue_offer_provider.dart';
import 'package:reveric/shared/providers/novel_providers.dart';

void main() {
  testWidgets('offers the previous session after its page is removed', (
    tester,
  ) async {
    final database = _DelayedDatabase();
    final container = ProviderContainer(
      overrides: [
        novelContentDatabaseProvider('work-db').overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    late Future<void> Function() start;
    late BuildContext sourceContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            sourceContext = context;
            start = () => ref
                .read(chatContinueOfferProvider.notifier)
                .offerAfterNewSession(
                  novelId: 'work',
                  sourceSessionId: 'previous-session',
                  sourceTitle: 'Previous conversation',
                  databasePath: 'work-db',
                );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final pending = start();
    final completion = expectLater(pending, completes);
    expect(database.aiChatMessageDao.queries, ['previous-session']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sourceContext.mounted, isFalse);
    database.aiChatMessageDao.result.complete(true);
    await tester.pump();
    await completion;

    final offer = container.read(chatContinueOfferProvider);
    expect(offer?.sourceSessionId, 'previous-session');
    expect(offer?.novelId, 'work');
    expect(offer?.title, 'Previous conversation');
  });

  test('does not offer an empty or unsaved source', () async {
    final database = _DelayedDatabase();
    final container = ProviderContainer.test(
      overrides: [
        novelContentDatabaseProvider('work-db').overrideWithValue(database),
      ],
    );
    addTearDown(database.close);
    final notifier = container.read(chatContinueOfferProvider.notifier);
    for (final sourceId in [null, '__new__', '__handoff_draft__']) {
      await notifier.offerAfterNewSession(
        novelId: 'work',
        sourceSessionId: sourceId,
        sourceTitle: 'Previous conversation',
        databasePath: 'work-db',
      );
    }
    await notifier.offerAfterNewSession(
      novelId: 'work',
      sourceSessionId: 'previous-session',
      sourceTitle: 'Previous conversation',
      databasePath: null,
    );
    expect(database.aiChatMessageDao.queries, isEmpty);
    final pending = notifier.offerAfterNewSession(
      novelId: 'work',
      sourceSessionId: 'previous-session',
      sourceTitle: 'Previous conversation',
      databasePath: 'work-db',
    );
    database.aiChatMessageDao.result.complete(false);
    await pending;
    expect(database.aiChatMessageDao.queries, ['previous-session']);
    expect(container.read(chatContinueOfferProvider), isNull);
  });

  test('query failure does not create an offer or escape unhandled', () async {
    final database = _DelayedDatabase();
    final container = ProviderContainer.test(
      overrides: [
        novelContentDatabaseProvider('work-db').overrideWithValue(database),
      ],
    );
    addTearDown(database.close);
    final pending = container
        .read(chatContinueOfferProvider.notifier)
        .offerAfterNewSession(
          novelId: 'work',
          sourceSessionId: 'previous-session',
          sourceTitle: 'Previous conversation',
          databasePath: 'work-db',
        );
    database.aiChatMessageDao.result.completeError(StateError('query failed'));
    await pending;
    expect(container.read(chatContinueOfferProvider), isNull);
  });

  test(
    'application teardown during the query does not write disposed state',
    () async {
      final database = _DelayedDatabase();
      final container = ProviderContainer(
        overrides: [
          novelContentDatabaseProvider('work-db').overrideWithValue(database),
        ],
      );
      addTearDown(database.close);
      final pending = container
          .read(chatContinueOfferProvider.notifier)
          .offerAfterNewSession(
            novelId: 'work',
            sourceSessionId: 'previous-session',
            sourceTitle: 'Previous conversation',
            databasePath: 'work-db',
          );
      container.dispose();
      database.aiChatMessageDao.result.complete(true);
      await expectLater(pending, completes);
    },
  );
}

class _DelayedDatabase extends NovelContentDatabase {
  _DelayedDatabase() : super.forTest(NativeDatabase.memory());

  late final _messages = _DelayedMessages(this);

  @override
  _DelayedMessages get aiChatMessageDao => _messages;
}

class _DelayedMessages extends AiChatMessageDao {
  _DelayedMessages(super.db);

  final result = Completer<bool>();
  final queries = <String>[];

  @override
  Future<bool> hasSavedMessages(String sessionId) {
    queries.add(sessionId);
    return result.future;
  }
}
