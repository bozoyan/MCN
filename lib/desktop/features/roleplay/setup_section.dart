// 职责: 桌面端角色扮演开局前的选角区 — 角色单选与已选标记，底部是开局输入栏。
// 关联文件:
//   lib/desktop/features/roleplay/panel.dart
//   lib/desktop/features/roleplay/composer.dart
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/shared/widgets/character/picker.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_roleplay_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/character/picker.dart';
import 'composer.dart';

class RoleplaySetupSection extends StatelessWidget {
  const RoleplaySetupSection({super.key, required this.run});

  final RoleplayRun run;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final t = context.t;
    final accent = colors.accentWarm;
    final selected = run.selectedCharacter;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RevericIcon(
                      RevericIcons.person_outline,
                      size: 14,
                      color: accent,
                    ),
                    const SizedBox(width: RevericSpacing.xs),
                    Text(
                      t(LocaleKeys.roleplaySelectCharacter),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(width: RevericSpacing.sm),
                      _SelectedChip(label: t(LocaleKeys.monologueSelectedChip)),
                    ],
                  ],
                ),
                const SizedBox(height: RevericSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(RevericSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(RevericRadius.x2l),
                  ),
                  child: run.characters.isEmpty
                      ? _EmptyCharactersHint(
                          text: t(LocaleKeys.roleplayNoCharacters),
                        )
                      : CharacterPicker(
                          characters: run.characters,
                          selectedIds: {?selected?.id},
                          accentColor: accent,
                          onToggle: run.toggleCharacter,
                        ),
                ),
              ],
            ),
          ),
        ),
        RoleplayComposer(run: run, characterName: selected?.name ?? ''),
      ],
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final accent = colors.accentWarm;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: typo.uiTiny.copyWith(color: accent, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyCharactersHint extends StatelessWidget {
  const _EmptyCharactersHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        style: typo.uiSmall.copyWith(color: colors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}
