// 职责: 移动端「圆桌会议」页 — 多智能体讨论的发起、实时流式展示、追加轮次、用户插话、切换写作模式与历史恢复；运行状态与操作来自共享的 useCouncilRun。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/database/app_database.dart' show AiChatSession, Novel;
import '../../../shared/hooks/use_ai_mode_model_selection.dart';
import '../../../shared/hooks/use_council_run.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/agent_council_models.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/ai_session_mode.dart';
import '../../../shared/providers/agent_council_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_avatar.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/ai/council/participant.dart';
import '../../../shared/widgets/ai/council/timeline.dart';
import '../../../shared/widgets/novel_open_boundary.dart';
import '../../pages/ai_providers_settings_page.dart';
import '../../pages/novel_chat_page.dart';
import '../../providers/ai_mode_session_memory_provider.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/ai_session_history_sheet.dart';
import '../../widgets/mobile_ai_mode.dart';
import '../../widgets/mobile_ai_session_app_bar.dart';
import '../../widgets/model_selector.dart';

part 'page_sections.dart';
part 'page_widgets.dart';

final _log = AppLogger.forModule('MobileCouncilPage');

/// 移动端圆桌会议页：从「助手」Hub 的圆桌会议卡片或「最近对话」进入。
/// 复用桌面共享的 council 编排器与 Provider，仅 UI 为移动端布局。
class MobileCouncilPage extends HookConsumerWidget {
  const MobileCouncilPage({
    super.key,
    required this.novelId,
    required this.novelName,
    required this.databasePath,
    this.novelDescription,
    this.chapterTitle,
    this.workspaceContent,
    this.initialSessionId,
    this.initialTopic,
  });

  final String novelId;
  final String novelName;
  final String databasePath;
  final String? novelDescription;
  final String? chapterTitle;
  final String? workspaceContent;

  /// 非空表示从「最近对话」打开一条已存在的圆桌会话：进入后从持久化恢复讨论历史。
  final String? initialSessionId;

  /// 由 chat 的下一步建议跳转带入的议题种子，用于预填议题输入框。
  final String? initialTopic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovelOpenBoundary(
      novelId: novelId,
      child: Consumer(
        builder: (context, ref, _) {
          final work = ref.watch(novelProvider(novelId));
          if (work.hasError) {
            _log.error(
              'Failed to load Council work id=$novelId',
              error: work.error,
              stackTrace: work.stackTrace,
            );
          }
          return work.when(
            skipLoadingOnReload: true,
            skipError: true,
            data: (novel) => novel == null
                ? _buildWorkLoadingState(
                    context,
                    message: context.t(LocaleKeys.editorNovelNotFound),
                  )
                : HookConsumer(
                    builder: (context, ref, _) =>
                        _buildContent(context, ref, novel),
                  ),
            loading: () => _buildWorkLoadingState(context),
            error: (_, _) => _buildWorkLoadingState(
              context,
              message: context.t(LocaleKeys.commonLoadFailed),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkLoadingState(BuildContext context, {String? message}) {
    return Scaffold(
      backgroundColor: RevericTheme.colorsOf(context).canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message == null)
              const CircularProgressIndicator()
            else
              Text(message),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(context.t(LocaleKeys.commonCancel)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Novel novel) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isConfigured = ref.watch(isAiConfiguredProvider);

    final run = useCouncilRun(
      ref,
      novel: novel,
      databasePath: databasePath,
      initialSessionId: initialSessionId,
      initialTopic: initialTopic,
    );
    final session = run.session;

    Future<void> startNewDiscussion() async {
      await run.startNew();
      ref
          .read(mobileAiModeSessionMemoryProvider(novelId).notifier)
          .clear(AiSessionMode.council);
    }

    final councilSessions =
        ref
            .watch(
              mobileNovelModeSessionsProvider((
                novelId: novelId,
                mode: AiSessionMode.council,
              )),
            )
            .asData
            ?.value ??
        const <AiChatSession>[];

    Future<void> openHistory() async {
      final picked = await showAiSessionHistorySheet(
        context,
        sessions: councilSessions,
        currentSessionId: run.sessionId,
        mode: AiSessionMode.council,
        modeLabel: mobileAiModeLabel(context, AiSessionMode.council),
        onDelete: (session) async {
          final service = ref.read(
            aiSessionPersistenceServiceProvider(
              novelId: novelId,
              databasePath: databasePath,
            ),
          );
          await service.deleteSession(session.id);
        },
      );
      if (picked == null || !context.mounted) return;
      if (picked.id == run.sessionId) return;
      ref
          .read(mobileAiModeSessionMemoryProvider(novelId).notifier)
          .remember(AiSessionMode.council, picked.id);
      await run.restore(picked.id);
    }

    Future<void> switchToWriteMode() async {
      final handoff = await run.handoff(createTargetSession: true);
      if (handoff == null || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileNovelChatPage(
            novelId: novelId,
            databasePath: databasePath,
            existingSessionId: handoff.targetSessionId,
          ),
        ),
      );
    }

    void showActiveRunDetailDialog(String title) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Consumer(
          builder: (dialogContext, ref, _) {
            final liveRun = ref.watch(
              agentCouncilActiveRunProvider(run.sessionId),
            );
            return AgentRoundDetailDialog(
              runState:
                  liveRun ??
                  AgentRunState(
                    agentId: '',
                    agentName: title,
                    round: 0,
                    isComplete: true,
                  ),
              title: title,
              databasePath: databasePath,
              novelId: novelId,
            );
          },
        ),
      );
    }

    final novelContext = MobileAiNovelContext(
      novelId: novelId,
      novelName: novelName,
      databasePath: databasePath,
      novelDescription: novelDescription,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
    );

    return MobileAiSessionScaffold(
      title: context.t(LocaleKeys.aiSessionModeCouncil),
      subtitle: _councilPhaseSubtitle(context, session),
      currentMode: AiSessionMode.council,
      novelContext: novelContext,
      currentSessionId: run.sessionId,
      historyTooltip: context.t(LocaleKeys.aiSessionHistoryTitle),
      newSessionTooltip: context.t(LocaleKeys.councilNewDiscussion),
      onHistory: openHistory,
      onNew: startNewDiscussion,
      body: !isConfigured
          ? _buildConfigHint(context, colors, typo)
          : session == null
          ? _buildSetup(context, colors, typo, run: run)
          : _buildDiscussion(
              context,
              colors,
              typo,
              run: run,
              session: session,
              onOpenActiveRunDetail: showActiveRunDetailDialog,
              onSwitchToWriteMode: session.rounds.isNotEmpty
                  ? switchToWriteMode
                  : null,
            ),
    );
  }
}
