// 职责: 验证运行条展示本会话运行、取消运行中的任务，并在结束后短暂保留回执。
// 关联文件:
//   lib/shared/widgets/ai/chat/tool_operation_strip.dart
//   lib/shared/services/ai/tool_operations.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'dart:async';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/tool_permission.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/tool_operation_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'lists live runs, cancels one and keeps a short receipt',
    (tester) async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      // 运行条只关心已开始的运行；全局放行，避免停在审批上。
      await db
          .into(db.novels)
          .insert(
            NovelsCompanion.insert(id: 'work', title: 'Work', description: ''),
          );
      for (final action in ['generation.video', 'files.read']) {
        await db.toolPermissionDao.setRule(
          action,
          const ToolPermissionScope.global(),
          ToolPermissionDecision.allow,
        );
      }
      final operations = container
          .read(aiChatRuntimeProvider('owner').notifier)
          .operations;
      final finishes = <Completer<Map<String, dynamic>>>[];
      for (final (index, label) in [(1, 'Hall'), (2, 'notes.txt')]) {
        final finish = Completer<Map<String, dynamic>>();
        finishes.add(finish);
        unawaited(
          operations.start(
            context: ToolExecutionContext(
              sessionId: 'owner',
              sourceTurnId: 'turn',
            ),
            callId: 'call$index',
            workId: 'work',
            kind: 'kind$index',
            targetPath: '/target$index',
            toolName: 'Run',
            background: true,
            permission: ToolActionRequest(
              action: index == 1 ? 'generation.video' : 'files.read',
              context: const ToolPermissionContext(workId: 'work'),
              targetPath: '/target$index',
              targetLabel: label,
              summary: const {},
            ),
            verifyTarget: () async {},
            execute: (operation) {
              operation.cancellation.onCancel(
                () => finish.complete({'ok': false, 'cancelled': true}),
              );
              return finish.future;
            },
          ),
        );
      }
      await tester.pumpWidget(
        _wrap(container, const ToolOperationStrip(sessionId: 'owner')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 tasks'), findsOneWidget);
      expect(find.text('Generate video · Hall'), findsOneWidget);
      expect(find.text('Read files · notes.txt'), findsOneWidget);
      expect(find.text('Running'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Cancel').first);
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('1 tasks'), findsOneWidget);
      expect(finishes[1].isCompleted, isFalse);

      // 回执停留结束后只剩仍在运行的那条，不再出汇总行。
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsNothing);
      expect(find.text('Read files · notes.txt'), findsOneWidget);
      expect(find.text('1 tasks'), findsNothing);

      finishes[1].complete({'ok': true});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
      container.dispose();
      await tester.pumpAndSettle();
      await db.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Widget _wrap(ProviderContainer container, Widget child) {
  final theme = RevericThemeData.reveric;
  return UncontrolledProviderScope(
    container: container,
    child: EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: theme.toThemeData().copyWith(platform: TargetPlatform.macOS),
          home: RevericTheme(
            data: theme,
            child: Scaffold(body: Column(children: [child])),
          ),
        ),
      ),
    ),
  );
}
