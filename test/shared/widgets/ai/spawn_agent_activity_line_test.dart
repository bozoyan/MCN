// 职责: 验证 SpawnAgent 第二行动态 — 运行中跟随子 Agent 工具/推理，结束后回落到 tool result 摘要
// 关联文件:
//   lib/shared/widgets/ai/tools/spawn_agent_activity_line.dart
//   lib/shared/providers/spawn_agent_run_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tools/spawn_agent_activity_line.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  for (final thinking in [false, true]) {
    testWidgets(
      'emoji at the ${thinking ? 'thinking' : 'output'} tail boundary renders safely',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          _wrap(container, _block(status: AiToolCallStatus.running)),
        );
        await tester.pumpAndSettle();
        final notifier = container.read(
          spawnAgentActiveRunProvider('spawn_line').notifier,
        );
        final tail = 'x' * 59;
        final content = 'prefix😀$tail';
        notifier.apply(
          thinking ? AgentThinkingDelta(content) : AgentTextDelta(content),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('…$tail'), findsOneWidget);

        // 截断点在完整 emoji 之前时，应保留 emoji，不能一律丢掉首字符。
        notifier.clear();
        final shorterTail = 'x' * 58;
        final aligned = 'prefix😀$shorterTail';
        notifier.apply(
          thinking ? AgentThinkingDelta(aligned) : AgentTextDelta(aligned),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('…😀$shorterTail'), findsOneWidget);
      },
    );
  }

  testWidgets('reflects live sub-agent activity then the settled result', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // provider 是 autoDispose：必须在 widget 挂载并 watch 之后再取 notifier，
    // 与运行时每次事件重新 read 的用法一致。
    SpawnAgentActiveRun notifier() =>
        container.read(spawnAgentActiveRunProvider('spawn_line').notifier);

    // 1. 运行中但还没有任何子 Agent 事件 —— 占位为「执行中…」。
    await tester.pumpWidget(
      _wrap(container, _block(status: AiToolCallStatus.running)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Running…'), findsOneWidget);

    // 2. 子 Agent 正在推理 —— 显示推理尾部文本。
    notifier().apply(
      const AgentThinkingDelta('cross-checking the cast in chapter 12'),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('cross-checking the cast in chapter 12'), findsOneWidget);

    // 3. 子 Agent 调用工具 —— 显示动作动词 + 目标，覆盖推理文本。
    notifier().apply(
      const AgentToolCallStart(
        callId: 'nested_read',
        toolName: 'Read',
        arguments: {'path': '/chapters/chapter_12/content'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Looking up'), findsOneWidget);

    // 4. 终态：不再读实时状态，显示已落库输出的首行。
    await tester.pumpWidget(
      _wrap(
        container,
        _block(
          status: AiToolCallStatus.success,
          result: const {
            'ok': true,
            'output': 'Found 3 continuity issues\nDetails follow.',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Found 3 continuity issues'), findsOneWidget);

    // 5. 取消态优先于其他结果字段。
    await tester.pumpWidget(
      _wrap(
        container,
        _block(
          status: AiToolCallStatus.cancelled,
          result: const {'cancelled': true, 'error': 'User cancelled'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

AiToolCallBlock _block({
  required AiToolCallStatus status,
  Map<String, dynamic>? result,
}) {
  return AiToolCallBlock(
    id: 'block_spawn_line',
    callId: 'spawn_line',
    toolName: 'SpawnAgent',
    arguments: const {'name': '内容核验', 'task': 'review chapter 12'},
    status: status,
    result: result,
  );
}

Widget _wrap(ProviderContainer container, AiToolCallBlock block) {
  return UncontrolledProviderScope(
    container: container,
    child: EasyLocalization(
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
              child: Scaffold(body: SpawnAgentActivityLine(block: block)),
            ),
          );
        },
      ),
    ),
  );
}
