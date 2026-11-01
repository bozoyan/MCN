// 职责: 验证议会时间线 — 讨论中排队的插话排在正在生成的发言之后，与最终落盘顺序一致。
// 关联文件:
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/shared/providers/agent_council_providers.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_run_state.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/agent_council_models.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/agent_message_card.dart';
import 'package:reveric/shared/widgets/ai/council/timeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('queued interjection sits below the speech still generating', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 2);
    CouncilMessage message(String id, String participantId, String content) =>
        CouncilMessage(
          id: id,
          participantId: participantId,
          participantName: participantId,
          content: content,
          timestamp: now,
          round: 1,
        );
    final session = AgentCouncilSession(
      id: 's',
      novelId: 'n',
      topic: 'Topic',
      participants: const [
        CouncilParticipant(id: 'a', name: 'Alice', description: '', prompt: ''),
        CouncilParticipant(id: 'b', name: 'Bob', description: '', prompt: ''),
      ],
      rounds: [
        CouncilRound(
          roundNumber: 1,
          messages: [
            message('m1', 'a', 'Alice spoke'),
            message('u1', councilUserParticipantId, 'Author interjects'),
          ],
        ),
      ],
      phase: CouncilPhase.discussing,
      createdAt: now,
      updatedAt: now,
    );
    const streaming = AgentRunState(
      agentId: 'b',
      agentName: 'Bob',
      round: 1,
      accumulatedText: 'Bob is speaking',
    );

    Widget timeline(Set<String> queued) => CouncilTimeline(
      key: ValueKey(queued.length),
      session: session,
      activeRun: streaming,
      runHistory: const {},
      density: AgentMessageDensity.panel,
      onOpenActiveRunDetail: (_) {},
      queuedMessageIds: queued,
    );

    rootBundle.clear();
    final host = ValueNotifier<Set<String>>({'u1'});
    await tester.pumpWidget(
      ProviderScope(
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
                  body: ValueListenableBuilder<Set<String>>(
                    valueListenable: host,
                    builder: (_, queued, _) => timeline(queued),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Author interjects'), greaterThan(top('Bob is speaking')));

    // 已被编排器并入的插话（不再排队）在下一位发言之前。
    host.value = const {};
    await tester.pump();
    expect(top('Author interjects'), lessThan(top('Bob is speaking')));

    // 自动跟随滚动排了延时任务，卸载后推进时钟让它跑完。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
