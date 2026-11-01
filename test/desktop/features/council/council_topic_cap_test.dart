// 职责: 圆桌会议讨论区长议题限高回归测试 — 验证议题视口被限制在区域高度的 30% 以内且消息列表保有可见高度
// 关联文件:
//   lib/desktop/features/council/discussion_section.dart
//   lib/desktop/features/council/panel.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/council/panel.dart';
import 'package:reveric/desktop/widgets/ai/model/model_selector.dart';
import 'package:reveric/desktop/widgets/ai/shared/ai_panel_header.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_council_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/agent_council_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/novel_fixture.dart';

// 8d35c241 曾把限高 LayoutBuilder 放在 Column 内部：Column 给非 flex 子节点的
// 高度约束无界（maxHeight = infinity），算出的 30% 限高是 infinity，长议题
// 依然会把 Expanded 消息列表压到 0。本测试钉住修复后的布局契约：
// 议题视口 ≤ 区域高度 30%，消息列表保有可见高度。
const _chatModel = AiModelOption(
  providerId: 'deepseek',
  providerDisplayName: 'DeepSeek',
  model: 'deepseek-chat',
  kind: AiModelKind.chat,
);

/// 不触碰 AppDatabase 静态缓存的参与者 provider：布局测试只关心
/// session.participants 渲染的徽章，全局参与者列表与本契约无关。
class _EmptyCouncilParticipants extends AgentCouncilParticipantsNotifier {
  @override
  Future<List<CouncilParticipant>> build() async => const [];
}

AgentCouncilSession _sessionWithLongTopic(String topic) {
  final now = DateTime.utc(2026, 1, 1);
  return AgentCouncilSession(
    id: 'council_topic_cap',
    novelId: 'novel_1',
    topic: topic,
    participants: const [
      CouncilParticipant(
        id: 'p1',
        name: 'Plot Architect',
        description: '',
        prompt: '',
      ),
      CouncilParticipant(
        id: 'p2',
        name: 'Character Analyst',
        description: '',
        prompt: '',
      ),
    ],
    rounds: [
      CouncilRound(
        roundNumber: 1,
        isComplete: true,
        messages: [
          CouncilMessage(
            id: 'm1',
            participantId: 'p1',
            participantName: 'Plot Architect',
            content: 'Round one answer.',
            timestamp: now,
            round: 1,
          ),
          CouncilMessage(
            id: 'm2',
            participantId: 'p2',
            participantName: 'Character Analyst',
            content: 'Another answer.',
            timestamp: now,
            round: 1,
          ),
        ],
      ),
    ],
    phase: CouncilPhase.completed,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrapLocalized(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 400, height: 800, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('long topic is capped and the message list stays visible', (
    tester,
  ) async {
    // 默认 800x600 测试面板上底部操作栏占比过高，给面板足够的实际展示高度。
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final topic = List.generate(
      60,
      (i) => '第 ${i + 1} 行议题内容，描述需要讨论的上下文。',
    ).join('\n');
    final container = ProviderContainer(
      overrides: [
        availableAiModelsProvider.overrideWith((ref) => const [_chatModel]),
        defaultAiModelOptionIdProvider.overrideWith((ref, kind) => null),
        agentCouncilParticipantsProvider.overrideWith(
          () => _EmptyCouncilParticipants(),
        ),

        appBackgroundActiveProvider.overrideWith((ref) => false),
        appDebugModeProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(agentCouncilSessionProvider('council_topic_cap').notifier)
        .setSession(_sessionWithLongTopic(topic));

    await tester.pumpWidget(
      _wrapLocalized(
        container,
        AgentCouncilPanel(
          novel: buildTestNovel(),
          initialSessionId: 'council_topic_cap',
        ),
      ),
    );
    await tester.pump();

    // 正面对照：议题确实渲染了，且被限高在区域高度的 30% 以内。
    expect(find.text(topic), findsOneWidget);
    final headerHeight = tester.getSize(find.byType(AiPanelHeader)).height;
    final regionHeight = 800 - headerHeight - 1; // 1px divider
    final topicViewportHeight = tester
        .getSize(
          find.ancestor(of: find.text(topic), matching: find.byType(ListView)),
        )
        .height;
    expect(topicViewportHeight, lessThanOrEqualTo(regionHeight * 0.3 + 1));

    // 讨论内容区（结论）保有可见高度，不被议题压没。
    final listHeight = tester
        .getSize(
          find.ancestor(
            of: find.text('Round one answer.'),
            matching: find.byType(ListView),
          ),
        )
        .height;
    expect(listHeight, greaterThan(80));

    // 已有圆桌会话在追加轮次前仍可切换下一轮使用的模型。
    expect(find.byType(ModelSelector), findsOneWidget);

    container
        .read(agentCouncilSessionProvider('council_topic_cap').notifier)
        .setSession(
          _sessionWithLongTopic(topic).copyWith(phase: CouncilPhase.discussing),
        );
    await tester.pump();

    // 本轮生成中也保留选择器；切换只会由下一轮新建的 AI client 使用。
    expect(find.byType(ModelSelector), findsOneWidget);
  });
}
