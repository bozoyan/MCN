// 职责: 桌面端小剧场单句台词 — 已完成台词与流式生成中的台词共用同一张卡片，避免生成完成时排版跳变。
// 关联文件:
//   lib/desktop/features/theater/line_list.dart
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/widgets/ai/theater_line_body.dart
//   lib/shared/widgets/ai/agent_message_menu.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/theater.json
//   assets/translations/zh-CN/theater.json
import 'package:flutter/material.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/theater_models.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/ai/theater_line_body.dart';
import '../../../shared/widgets/ai/agent_message_menu.dart';
import '../../../shared/widgets/character_avatar.dart';

const _density = AgentMessageDensity.panel;

Widget _avatar(BuildContext context, TheaterParticipant participant) {
  final colors = RevericTheme.colorsOf(context);
  return CharacterAvatar(
    avatarAssetId: participant.avatarAssetId,
    fallbackName: participant.name,
    size: AgentMessageCard.avatarSize(_density),
    backgroundColor: colors.accentWarm.withValues(alpha: 0.15),
  );
}

String _turnLabel(BuildContext context, int turn) =>
    '${context.t(LocaleKeys.theaterTurn)} $turn';

class TheaterLineCard extends StatelessWidget {
  final TheaterLine line;
  final TheaterParticipant participant;
  final AgentRunState? completedRun;

  /// 改写历史的菜单项；为 null 时不显示对应项（表演中全部为 null）。
  final VoidCallback? onRegenerate;
  final VoidCallback? onRewindAfter;

  const TheaterLineCard({
    super.key,
    required this.line,
    required this.participant,
    this.completedRun,
    this.onRegenerate,
    this.onRewindAfter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: line.characterId,
          agentName: line.characterName,
          round: line.turn,
          accumulatedText: [
            if (line.stageDirection != null && line.stageDirection!.isNotEmpty)
              '（${line.stageDirection}）',
            '「${line.dialogue}」',
          ].join('\n'),
          isComplete: true,
        );
    final menu = AgentMessageMenu(
      onRegenerate: onRegenerate,
      regenerateLabel: context.t(LocaleKeys.theaterLineRegenerate),
      onRewindAfter: onRewindAfter,
    );
    return AgentMessageCard(
      avatar: _avatar(context, participant),
      name: participant.name,
      accentColor: colors.accentWarm,
      density: _density,
      meta: _turnLabel(context, line.turn),
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: participant.name,
      ),
      trailing: menu.hasEntries ? menu : null,
      body: TheaterLineBody(
        dialogue: line.dialogue,
        stageDirection: line.stageDirection,
        density: _density,
      ),
    );
  }
}

/// 正在生成的台词：与 [TheaterLineCard] 同一外观，正文边收边解析。
class TheaterStreamingLineCard extends StatelessWidget {
  const TheaterStreamingLineCard({
    super.key,
    required this.run,
    required this.participant,
    required this.onOpenDetail,
  });

  final AgentRunState run;
  final TheaterParticipant participant;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return AgentMessageCard(
      avatar: _avatar(context, participant),
      name: participant.name,
      accentColor: colors.accentWarm,
      density: _density,
      meta: run.round > 0 ? _turnLabel(context, run.round) : null,
      thinking: run.accumulatedThinking,
      streaming: true,
      onOpenDetail: onOpenDetail,
      body: TheaterLineBody.streaming(run.accumulatedText, _density),
    );
  }
}
