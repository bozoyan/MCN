// 职责: 小剧场导演栏 — 导演指令输入与插入，表演间隙可点角色头像让其单独说一句。桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_theater_run.dart
//   lib/desktop/features/theater/performance_section.dart
//   lib/mobile/features/theater/page_widgets.dart
import 'package:flutter/material.dart';

import '../../hooks/use_theater_run.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/theater_models.dart';
import '../../theme/theme.dart';
import '../character_avatar.dart';

class TheaterDirectorBar extends StatelessWidget {
  const TheaterDirectorBar({
    super.key,
    required this.run,
    required this.session,
  });

  final TheaterRun run;
  final TheaterSession session;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final performing = session.isActive;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      borderSide: BorderSide(color: colors.borderInput),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: run.directionController,
          builder: (context, value, _) {
            final canInsert = value.text.trim().isNotEmpty;
            return TextField(
              controller: run.directionController,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => run.direct(),
              style: typo.uiSmall.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t(LocaleKeys.theaterDirectionHint),
                hintStyle: typo.uiSmall.copyWith(color: colors.textSubtle),
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.sm,
                  ),
                  child: RevericIcon(
                    RevericIcons.movie_outlined,
                    size: 16,
                    color: colors.accent,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(),
                suffixIcon: IconButton(
                  tooltip: context.t(LocaleKeys.theaterDirectionInsert),
                  visualDensity: VisualDensity.compact,
                  onPressed: canInsert ? run.direct : null,
                  icon: RevericIcon(
                    RevericIcons.send_rounded,
                    size: 16,
                    color: canInsert ? colors.accent : colors.textSubtle,
                  ),
                ),
                filled: true,
                fillColor: colors.surfaceDim,
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: colors.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.md,
                  vertical: RevericSpacing.sm,
                ),
              ),
            );
          },
        ),
        if (!performing) ...[
          const SizedBox(height: RevericSpacing.sm),
          Wrap(
            spacing: RevericSpacing.xs,
            runSpacing: RevericSpacing.xs,
            children: [
              for (final participant in session.participants)
                _SpeakerChip(
                  participant: participant,
                  enabled: !run.isRunning,
                  onTap: () => run.speak(participant.characterId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({
    required this.participant,
    required this.enabled,
    required this.onTap,
  });

  final TheaterParticipant participant;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Tooltip(
      message: context.t(
        LocaleKeys.theaterSpeakFmt,
        namedArgs: {'name': participant.name},
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.xxs,
              RevericSpacing.xxs,
              RevericSpacing.sm,
              RevericSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RevericRadius.pill),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CharacterAvatar(
                  avatarAssetId: participant.avatarAssetId,
                  fallbackName: participant.name,
                  size: 20,
                  backgroundColor: colors.accentWarm.withValues(alpha: 0.15),
                ),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  participant.name,
                  style: typo.uiTiny.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
