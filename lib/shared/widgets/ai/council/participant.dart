// 职责: 议会成员的展示件 — 主题色、头像、讨论区顶部徽章与设置页的多选 chip，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/agent_council_models.dart';
import '../../../theme/theme.dart';
import '../../agent_avatar.dart';
import '../agent_message_card.dart';

Color councilParticipantColor(
  CouncilParticipant participant,
  RevericColors colors,
) {
  final hex = participant.colorHex;
  if (hex == null || hex.isEmpty) return colors.accent;
  return Color(
    int.tryParse(hex.replaceFirst('#', '0xFF')) ?? colors.accent.toARGB32(),
  );
}

/// 会话里找不到该发言人（成员已被移除）时，用消息上的名字兜底。
CouncilParticipant councilParticipantFor(
  AgentCouncilSession session,
  String participantId,
  String fallbackName,
) {
  return session.participants.where((p) => p.id == participantId).firstOrNull ??
      CouncilParticipant(
        id: participantId,
        name: fallbackName,
        description: '',
        prompt: '',
      );
}

class CouncilParticipantAvatar extends StatelessWidget {
  const CouncilParticipantAvatar({
    super.key,
    required this.participant,
    required this.size,
  });

  final CouncilParticipant participant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return AgentAvatar(
      avatarPath: participant.avatarPath,
      slug: participant.id,
      avatarEmoji: participant.avatarEmoji,
      size: size,
      backgroundColor: councilParticipantColor(
        participant,
        colors,
      ).withValues(alpha: 0.15),
    );
  }
}

/// 讨论区顶部的成员徽章；传入 [onTap] 时可点击让该成员发言。
class CouncilParticipantBadge extends StatelessWidget {
  const CouncilParticipantBadge({
    super.key,
    required this.participant,
    this.onTap,
  });

  final CouncilParticipant participant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final name = participant.resolveName(context.t);
    final badge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CouncilParticipantAvatar(participant: participant, size: 20),
          const SizedBox(width: RevericSpacing.xs),
          Text(
            name,
            style: typo.uiTiny.copyWith(
              color: councilParticipantColor(participant, colors),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return badge;
    return Tooltip(
      message: context.t(LocaleKeys.councilSpeakFmt, namedArgs: {'name': name}),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: badge,
      ),
    );
  }
}

/// 设置页的成员多选 chip：头像 + 名字 + 编辑入口。
class CouncilParticipantChip extends StatelessWidget {
  const CouncilParticipantChip({
    super.key,
    required this.participant,
    required this.isSelected,
    required this.density,
    required this.onToggle,
    required this.onEdit,
  });

  final CouncilParticipant participant;
  final bool isSelected;
  final AgentMessageDensity density;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mobile = density == AgentMessageDensity.mobile;
    final editIcon = RevericIcon(
      RevericIcons.edit_outlined,
      size: 14,
      color: mobile ? colors.textSubtle : null,
    );
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.12)
              : mobile
              ? colors.surface
              : colors.surfaceDim,
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          border: Border.all(
            color: isSelected
                ? colors.accent.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AgentAvatar(
              avatarPath: participant.avatarPath,
              slug: participant.id,
              avatarEmoji: participant.avatarEmoji,
              size: 24,
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              participant.resolveName(context.t),
              style: typo.uiSmall.copyWith(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: RevericSpacing.xxs),
            if (mobile)
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(RevericSpacing.xxs),
                  child: editIcon,
                ),
              )
            else
              IconButton(
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(RevericSpacing.xxs),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: colors.textSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                  ),
                ),
                icon: editIcon,
              ),
          ],
        ),
      ),
    );
  }
}
