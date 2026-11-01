// 职责: 议会单条发言卡片 — 成员发言（生成中与生成后同一张 AgentMessageCard）与作者插话气泡，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/widgets/ai/council/participant.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
//   lib/shared/widgets/ai/markdown_text.dart
//   lib/shared/models/agent_council_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
import 'package:flutter/material.dart';

import '../../../agent/agent_run_state.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/agent_council_models.dart';
import '../../../theme/theme.dart';
import '../../../services/ai/mode_output_parser.dart';
import '../agent_message_card.dart';
import '../agent_message_menu.dart';
import '../agent_round_detail_dialog.dart';
import '../markdown_text.dart';
import '../chat/chat_message_parts.dart' show CopyIconButton;
import 'participant.dart';

/// 已落盘的一条发言：成员发言或作者插话。
class CouncilMessageCard extends StatelessWidget {
  const CouncilMessageCard({
    super.key,
    required this.message,
    required this.participant,
    required this.density,
    this.completedRun,
    this.databasePath,
    this.novelId,
    this.onRegenerate,
    this.onRewindAfter,
    this.onRemove,
  });

  final CouncilMessage message;
  final CouncilParticipant participant;
  final AgentMessageDensity density;
  final AgentRunState? completedRun;
  final String? databasePath;
  final String? novelId;

  /// 改写历史的菜单项；为 null 时不显示对应项（讨论进行中全部为 null）。
  final VoidCallback? onRegenerate;
  final VoidCallback? onRewindAfter;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final menu = AgentMessageMenu(
      onRegenerate: onRegenerate,
      regenerateLabel: context.t(LocaleKeys.councilMessageRegenerate),
      onRewindAfter: onRewindAfter,
      onRemove: onRemove,
    );
    final actions = _actions(menu.hasEntries ? menu : null);
    if (message.isUser) {
      return _UserMessageBubble(
        message: message,
        density: density,
        actions: actions,
      );
    }
    final colors = RevericTheme.colorsOf(context);
    final name = participant.resolveName(context.t);
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: message.participantId,
          agentName: message.participantName,
          round: message.round,
          accumulatedText: message.content,
          isComplete: true,
        );
    return AgentMessageCard(
      avatar: CouncilParticipantAvatar(
        participant: participant,
        size: AgentMessageCard.avatarSize(density),
      ),
      name: name,
      accentColor: councilParticipantColor(participant, colors),
      density: density,
      subtitle: participant.resolveDescription(context.t),
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: name,
        databasePath: databasePath,
        novelId: novelId,
      ),
      trailing: actions,
      body: AiMarkdownText(
        message.content,
        style: AgentMessageCard.bodyStyle(context, density),
      ),
    );
  }

  /// 桌面端带复制；移动端靠长按选择文字复制，只放菜单。
  Widget? _actions(Widget? menu) {
    if (density == AgentMessageDensity.mobile) return menu;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CopyIconButton(text: message.content),
        ?menu,
      ],
    );
  }
}

/// 正在生成的发言：与 [CouncilMessageCard] 同一外观，还没出字时显示跳动三点。
class CouncilStreamingCard extends StatelessWidget {
  const CouncilStreamingCard({
    super.key,
    required this.run,
    required this.participant,
    required this.density,
    required this.onOpenDetail,
  });

  final AgentRunState run;
  final CouncilParticipant participant;
  final AgentMessageDensity density;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    // 末行的「【请回应】」点名是给调度器的，生成中也不露出来。
    final text = parseCouncilOutput(run.accumulatedText, partial: true).content;
    return AgentMessageCard(
      avatar: CouncilParticipantAvatar(
        participant: participant,
        size: AgentMessageCard.avatarSize(density),
      ),
      name: participant.resolveName(context.t),
      accentColor: councilParticipantColor(participant, colors),
      density: density,
      subtitle: participant.resolveDescription(context.t),
      thinking: run.accumulatedThinking,
      streaming: true,
      onOpenDetail: onOpenDetail,
      // 生成中与完成后同一种渲染，落盘时不跳；内容还在增长，不开选区。
      body: text.isEmpty
          ? null
          : AiMarkdownText(
              text,
              style: AgentMessageCard.bodyStyle(context, density),
              selectable: false,
            ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({
    required this.message,
    required this.density,
    required this.actions,
  });

  final CouncilMessage message;
  final AgentMessageDensity density;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: density == AgentMessageDensity.mobile
            ? RevericSpacing.lg
            : RevericSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                context.t(LocaleKeys.councilUserSpeakerLabel),
                style: typo.uiSmall.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: RevericSpacing.xs),
                actions!,
              ],
            ],
          ),
          const SizedBox(height: RevericSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RevericSpacing.md),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(RevericRadius.x2l),
            ),
            child: SelectableText(
              message.content,
              style: AgentMessageCard.bodyStyle(context, density),
            ),
          ),
        ],
      ),
    );
  }
}
