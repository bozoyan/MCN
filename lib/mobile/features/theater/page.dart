// 职责: 移动端「小剧场」页 — 多角色场景表演的发起、实时流式展示、追加轮次、切换写作模式与历史恢复。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/shared/hooks/use_theater_run.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/models/theater_models.dart
//   lib/shared/services/ai/chat.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/theater.json
//   assets/translations/zh-CN/theater.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/widgets/novel_open_boundary.dart';
import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/database/app_database.dart' show AiChatSession;
import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/ai_session_mode.dart';
import '../../../shared/models/queued_chat_message.dart';
import '../../../shared/models/theater_models.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/hooks/use_theater_run.dart';
import '../../../shared/providers/theater_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/theater_direction_note.dart';
import '../../../shared/widgets/ai/theater_director_bar.dart';
import '../../../shared/widgets/ai/theater_line_body.dart';
import '../../../shared/widgets/ai/agent_message_menu.dart';
import '../../../shared/widgets/ai/theater_write_button.dart';
import '../../../shared/widgets/character/picker.dart';
import '../../../shared/widgets/ai/user_respecting_auto_scroll_controller.dart';
import '../../../shared/widgets/ai/ai_mode_error_notice.dart';
import '../../../shared/widgets/character_avatar.dart';
import '../../providers/ai_mode_session_memory_provider.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/ai_session_history_sheet.dart';
import '../../widgets/mobile_ai_mode.dart';
import '../../widgets/mobile_ai_session_app_bar.dart';
import '../../widgets/model_selector.dart';
import '../../pages/ai_providers_settings_page.dart';
import '../../pages/novel_chat_page.dart';

part 'page_sections.dart';
part 'page_widgets.dart';

/// 移动端小剧场页：从「助手」Hub 的小剧场卡片或「最近对话」进入。
/// 复用桌面共享的 theater 编排器与 Provider，仅 UI 为移动端布局。
class MobileTheaterPage extends HookConsumerWidget {
  const MobileTheaterPage({
    super.key,
    required this.novelId,
    required this.novelName,
    required this.databasePath,
    this.novelDescription,
    this.chapterTitle,
    this.workspaceContent,
    this.initialSessionId,
    this.initialScene,
  });

  final String novelId;
  final String novelName;
  final String databasePath;
  final String? novelDescription;
  final String? chapterTitle;
  final String? workspaceContent;

  /// 非空表示从「最近对话」打开一条已存在的小剧场会话：进入后从持久化恢复表演历史。
  final String? initialSessionId;

  /// 由 chat 的下一步建议跳转带入的场景种子，用于预填场景输入框。
  final String? initialScene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovelOpenBoundary(
      novelId: novelId,
      child: HookConsumer(
        builder: (context, ref, _) => _buildContent(context, ref),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isConfigured = ref.watch(isAiConfiguredProvider);

    final run = useTheaterRun(
      ref,
      novelId: novelId,
      databasePath: databasePath,
      novelName: novelName,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
      initialSessionId: initialSessionId,
      initialScene: initialScene,
    );
    final session = run.session;
    final models = run.models;

    Widget buildSessionModelSelector() {
      final selector = MobileModelSelector.bar(
        models: models.availableModels
            .where((model) => model.kind == AiModelKind.chat)
            .toList(growable: false),
        selectedId: models.displayed?.id,
        selectedEffort: models.selectedEffort,
        disabledModelIds: const <String>{},

        onSelectModel: models.select,
        onSelectEffort: models.selectWithEffort,
      );
      return selector;
    }

    Future<void> startNewScene() async {
      await run.startNew();
      ref
          .read(mobileAiModeSessionMemoryProvider(novelId).notifier)
          .clear(AiSessionMode.theater);
    }

    final theaterSessions =
        ref
            .watch(
              mobileNovelModeSessionsProvider((
                novelId: novelId,
                mode: AiSessionMode.theater,
              )),
            )
            .asData
            ?.value ??
        const <AiChatSession>[];

    Future<void> openHistory() async {
      final picked = await showAiSessionHistorySheet(
        context,
        sessions: theaterSessions,
        currentSessionId: run.sessionId,
        mode: AiSessionMode.theater,
        modeLabel: mobileAiModeLabel(context, AiSessionMode.theater),
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
          .remember(AiSessionMode.theater, picked.id);
      await run.restore(picked.id);
    }

    /// [instruction] 为写成正文的指令，随交接自动发送；只带剧本时为 null。
    Future<void> switchToWriteMode(String? instruction) async {
      final handoff = await run.handoff(
        createTargetSession: instruction == null,
      );
      if (handoff == null || !context.mounted) return;
      final targetSessionId = handoff.targetSessionId;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileNovelChatPage(
            novelId: novelId,
            databasePath: databasePath,
            existingSessionId: targetSessionId,
            handoff: instruction == null
                ? null
                : PendingChatHandoff(
                    label: handoff.sourceTitle,
                    content: handoff.context.toMessageContent(),
                    initialText: instruction,
                    autoSend: true,
                  ),
          ),
        ),
      );
    }

    Future<void> showActiveRunDetailDialog(String title) async {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Consumer(
            builder: (dialogContext, ref, _) {
              final liveRun = ref.watch(
                theaterActiveRunProvider(run.sessionId),
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
          );
        },
      );
    }

    final participantsSubtitle = session?.participants
        .map((p) => p.name)
        .join('、');
    final novelContext = MobileAiNovelContext(
      novelId: novelId,
      novelName: novelName,
      databasePath: databasePath,
      novelDescription: novelDescription,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
    );

    return MobileAiSessionScaffold(
      title: context.t(LocaleKeys.aiSessionModeTheater),
      subtitle:
          participantsSubtitle != null && participantsSubtitle.trim().isNotEmpty
          ? participantsSubtitle
          : null,
      currentMode: AiSessionMode.theater,
      novelContext: novelContext,
      currentSessionId: run.sessionId,
      historyTooltip: context.t(LocaleKeys.aiSessionHistoryTitle),
      newSessionTooltip: context.t(LocaleKeys.theaterNew),
      onHistory: openHistory,
      onNew: startNewScene,
      body: !isConfigured
          ? _buildConfigHint(context, colors, typo)
          : session == null
          ? _buildSetup(context, ref, colors, typo, run: run)
          : _buildPerformance(
              context,
              colors,
              typo,
              run: run,
              session: session,
              modelSelector: buildSessionModelSelector(),
              onOpenActiveRunDetail: showActiveRunDetailDialog,
              onSwitchToWriteMode: session.lines.isNotEmpty
                  ? switchToWriteMode
                  : null,
            ),
    );
  }
}
