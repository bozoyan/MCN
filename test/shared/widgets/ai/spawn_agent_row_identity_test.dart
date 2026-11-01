// 职责: 验证委派行的身份呈现 — 显示笔名、职能 chip 与子 Agent 头像
// 关联文件:
//   lib/shared/widgets/ai/tools/spawn_agent_identity.dart
//   lib/shared/widgets/ai/tool_activity_group.dart
//   lib/shared/providers/subagent_providers.dart
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
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/tool_activity_group.dart';
import 'package:reveric/shared/widgets/ai/tools/spawn_agent_identity.dart';
import 'package:reveric/shared/widgets/ai/tools/tool_card_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 名字与 `agent` 参数一致，用来验证按名称反查子 Agent 画像；slug 不在内置画像表里，
/// 因此 AgentAvatar 落到 emoji，断言不依赖图片资源。
const _writer = SubAgent(
  id: 'agent_writer',
  slug: 'custom_writer',
  name: '正文写手',
  description: '',
  prompt: '',
  scope: SubAgentScope.global,
  sortOrder: 0,
  avatarEmoji: '✍️',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  // 同一文件里第二个 testWidgets 重包 EasyLocalization 会拿到空子树，
  // 因此三种形态在同一个 test 内依次 pump。
  testWidgets('shows the pen name with its agent role, model and status', (
    tester,
  ) async {
    // 1. 运行中的新协议委派：笔名当主语，职能进 chip，不再显示「委派任务」。
    await _pumpGroup(
      tester,
      _spawnBlock(
        arguments: const {'agent': '正文写手', 'name': '唐家三少', 'task': '写第 98 章'},
        status: AiToolCallStatus.running,
      ),
    );
    expect(find.text('唐家三少'), findsOneWidget);
    expect(find.text('正文写手'), findsOneWidget);
    expect(find.text('✍️'), findsOneWidget);
    expect(find.byType(SpawnAgentAvatar), findsOneWidget);
    // 头像取代了通用状态点。
    expect(find.byType(AiToolStatusDot), findsNothing);
    expect(find.text('Delegate Agent'), findsNothing);

    // 2. 折叠后的一行摘要也点名到人，而不是四个字的「委派任务」。
    await tester.tap(find.text('Process'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('唐家三少'), findsOneWidget);
    expect(find.text('正文写手'), findsNothing);

    // 3. 子 Agent 配了自定义模型时并入同一枚职能 chip，信息量不比改动前少。
    await _pumpGroup(
      tester,
      _spawnBlock(
        arguments: const {'agent': '正文写手', 'name': '唐家三少', 'task': '写第 98 章'},
        status: AiToolCallStatus.success,
        metadata: const {'sub_agent_model': 'deepseek-v4'},
      ),
    );
    expect(find.text('唐家三少'), findsOneWidget);
    expect(find.text('正文写手 · deepseek-v4'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

AiToolCallBlock _spawnBlock({
  required Map<String, dynamic> arguments,
  required AiToolCallStatus status,
  Map<String, dynamic>? metadata,
}) {
  return AiToolCallBlock(
    id: 'block_spawn',
    callId: 'call_spawn',
    toolName: 'SpawnAgent',
    arguments: arguments,
    status: status,
    metadata: metadata,
  );
}

Future<void> _pumpGroup(WidgetTester tester, AiToolCallBlock block) async {
  await tester.pumpWidget(_wrap(AiToolActivityGroup(blocks: [block])));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            appDebugModeProvider.overrideWithValue(false),
            mergedSubAgentsProvider.overrideWithValue(const [_writer]),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(body: Center(child: child)),
            ),
          ),
        );
      },
    ),
  );
}
