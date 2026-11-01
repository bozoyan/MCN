// 职责: 委派行身份呈现的黄金图（加载真实字体），人工目检头像状态环、笔名与职能 chip 的排布
// 关联文件:
//   lib/shared/widgets/ai/tools/spawn_agent_identity.dart
//   lib/shared/widgets/ai/tool_activity_group.dart

import 'dart:io';

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
import 'package:shared_preferences/shared_preferences.dart';

const _agents = [
  SubAgent(
    id: 'a1',
    slug: 'writer',
    name: '正文写手',
    description: '',
    prompt: '',
    scope: SubAgentScope.global,
    sortOrder: 0,
    avatarEmoji: '✍️',
  ),
  SubAgent(
    id: 'a2',
    slug: 'review',
    name: '内容核验',
    description: '',
    prompt: '',
    scope: SubAgentScope.global,
    sortOrder: 1,
    avatarEmoji: '🔍',
  ),
  SubAgent(
    id: 'a3',
    slug: 'chronicler',
    name: '编年史者',
    description: '',
    prompt: '',
    scope: SubAgentScope.global,
    sortOrder: 2,
    avatarEmoji: '📜',
  ),
];

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  setUp(() => rootBundle.clear());

  testWidgets('golden: 委派行的头像状态环与笔名 / 职能排布', (tester) async {
    tester.view.physicalSize = const Size(380, 310);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    await tester.pumpWidget(
      _wrap(
        const AiToolActivityGroup(
          blocks: [
            AiToolCallBlock(
              id: 'b1',
              callId: 'c1',
              toolName: 'SpawnAgent',
              arguments: {'agent': '内容核验', 'name': '鲁迅', 'task': '核对第 97 章'},
              status: AiToolCallStatus.success,
              result: {'ok': true, 'output': '三处时间线冲突已列出'},
            ),
            AiToolCallBlock(
              id: 'b2',
              callId: 'c2',
              toolName: 'SpawnAgent',
              arguments: {'agent': '编年史者', 'name': '天蚕土豆', 'task': '整理事实'},
              status: AiToolCallStatus.success,
              metadata: {'sub_agent_model': 'deepseek-v4'},
              result: {'ok': true, 'output': '已归档 12 条事实'},
            ),
            AiToolCallBlock(
              id: 'b3',
              callId: 'c3',
              toolName: 'SpawnAgent',
              arguments: {'agent': '内容核验', 'name': '余华', 'task': '核对事实'},
              status: AiToolCallStatus.success,
              result: {'ok': true, 'output': '事实核对完成'},
            ),
            AiToolCallBlock(
              id: 'b4',
              callId: 'c4',
              toolName: 'SpawnAgent',
              arguments: {'agent': '正文写手', 'name': '唐家三少', 'task': '写第 98 章'},
              status: AiToolCallStatus.running,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(AiToolActivityGroup),
      matchesGoldenFile('goldens/spawn_agent_row_identity.png'),
    );
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        // ui* 样式不指定 fontFamily，靠 DefaultTextStyle 继承；测试默认字体没有
        // 中日韩字形，这里把默认族换成仓库里的中文字体，黄金图才不是一堆豆腐块。
        final base = RevericThemeData.reveric.toThemeData();
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'LXGWWenKai'),
        );
        return ProviderScope(
          overrides: [
            appDebugModeProvider.overrideWithValue(false),
            mergedSubAgentsProvider.overrideWithValue(_agents),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: theme,
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(alignment: Alignment.topCenter, child: child),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
