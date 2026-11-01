// 职责: 测试 AI 聊天面板会话切换器 — 验证下拉浮层的会话过滤、切换回调与删除回退。
// 关联文件:
//   lib/desktop/widgets/ai/chat/session_switcher.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/ai/chat/session_switcher.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSessionPersistence extends AiSessionPersistenceService {
  _FakeSessionPersistence(super.appDatabase, super.novelId);

  final deletedSessionIds = <String>[];

  @override
  Future<void> deleteSession(String id) async {
    deletedSessionIds.add(id);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  // 注：本文件保持单个 testWidgets，避免 keepAlive provider 跨用例共享脏状态
  // （见 .agents/rules/testing.md），相关断言并入本用例。
  testWidgets(
    'switches sessions from the title dropdown and falls back after deleting the active one',
    (tester) async {
      final appDb = AppDatabase.forTest(NativeDatabase.memory());
      final persistence = _FakeSessionPersistence(appDb, 'novel_1');
      addTearDown(() async => appDb.close());

      AiChatSession session(String id, String title, {String mode = 'chat'}) {
        final now = DateTime(2026, 8, 10, 12);
        return AiChatSession(
          id: id,
          novelId: 'novel_1',
          title: title,
          mode: mode,
          createdAt: now,
          updatedAt: now,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }

      final sessions = [
        session('s1', 'Chapter planning'),
        session('s2', 'Character brainstorm'),
        // council 会话不应出现在切换浮层中（浮层只展示 chat mode）。
        session('s3', 'Council session', mode: 'council'),
      ];

      final selected = <String?>[];
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              aiChatSessionsPageProvider(
                novelId: 'novel_1',
                databasePath: 'db_path',
                limit: 50,
              ).overrideWith(
                (ref) => Stream.value((sessions: sessions, hasMore: false)),
              ),
              aiSessionPersistenceServiceProvider(
                novelId: 'novel_1',
                databasePath: 'db_path',
              ).overrideWithValue(persistence),
            ],
            child: ChatSessionSwitcher(
              novelId: 'novel_1',
              databasePath: 'db_path',
              activeSessionId: 's1',
              onSelectSession: (id) async => selected.add(id),
              child: const Text('Current session'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开浮层：展示 chat 会话，过滤 council 会话。
      await tester.tap(find.text('Current session'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter planning'), findsOneWidget);
      expect(find.text('Character brainstorm'), findsOneWidget);
      expect(find.text('Council session'), findsNothing);

      // 点行切换会话，浮层关闭。
      await tester.tap(find.text('Character brainstorm'));
      await tester.pumpAndSettle();
      expect(selected, ['s2']);
      expect(find.text('Chapter planning'), findsNothing);

      // 删除走行内右键菜单：回调后备会话 id（剩余的 chat 会话之一）。
      await tester.tap(find.text('Current session'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Chapter planning'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(persistence.deletedSessionIds, ['s1']);
      expect(selected.length, 2);
      expect(selected.last, 's2');

      // 删除非当前会话不触发切换。
      await tester.tap(
        find.text('Character brainstorm'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(persistence.deletedSessionIds, ['s1', 's2']);
      expect(selected.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
