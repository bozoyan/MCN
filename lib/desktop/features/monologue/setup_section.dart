// 职责: 桌面端独白开始前的配置区 — 选角色、填议题、模型选择与开始按钮。
// 关联文件:
//   lib/desktop/features/monologue/panel.dart
//   lib/shared/hooks/use_monologue_run.dart
//   lib/shared/widgets/character/picker.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_monologue_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/character/picker.dart';

class MonologueSetupSection extends StatelessWidget {
  const MonologueSetupSection({
    super.key,
    required this.run,
    required this.modelSelector,
  });

  final MonologueRun run;
  final Widget modelSelector;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final t = context.t;
    final characters = run.characters;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      borderSide: BorderSide(color: colors.borderInput),
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Section(
                  icon: RevericIcons.person_outline,
                  title: t(LocaleKeys.monologueSelectCharacter),
                  trailing:
                      characters.any((c) => c.id == run.selectedCharacterId)
                      ? _SelectedChip(
                          label: t(LocaleKeys.monologueSelectedChip),
                        )
                      : null,
                  child: characters.isEmpty
                      ? _EmptyCharactersHint(
                          text: t(LocaleKeys.monologueNoCharacters),
                        )
                      : CharacterPicker(
                          characters: characters,
                          selectedIds: {?run.selectedCharacterId},
                          accentColor: colors.accent,
                          onToggle: run.toggleCharacter,
                        ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _Section(
                  icon: RevericIcons.chat_bubble_outline,
                  title: t(LocaleKeys.monologueTopic),
                  child: TextField(
                    controller: run.topicController,
                    maxLines: 4,
                    minLines: 2,
                    style: typo.ui.copyWith(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: t(LocaleKeys.monologueTopicHint),
                      hintStyle: typo.ui.copyWith(color: colors.textSubtle),
                      filled: true,
                      fillColor: colors.surface,
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder.copyWith(
                        borderSide: BorderSide(color: colors.accent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.md,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                modelSelector,
                const SizedBox(height: RevericSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: run.canStart ? run.start : null,
                    icon: run.isRunning
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.surface,
                            ),
                          )
                        : RevericIcon(RevericIcons.person_rounded, size: 18),
                    label: Text(
                      run.isRunning
                          ? t(LocaleKeys.monologueGenerating)
                          : t(LocaleKeys.monologueStart),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(icon, size: 14, color: colors.accent),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            if (trailing != null) ...[
              const SizedBox(width: RevericSpacing.sm),
              trailing!,
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
          child: child,
        ),
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
    final accent = colors.accent;
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
