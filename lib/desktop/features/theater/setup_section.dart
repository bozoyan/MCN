// 职责: 桌面端小剧场开演前的配置区 — 选角、场景描述、轮数与模型选择、开演按钮。
// 关联文件:
//   lib/desktop/features/theater/panel.dart
//   lib/shared/hooks/use_theater_run.dart
//   lib/shared/widgets/character/picker.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/hooks/use_theater_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/theater_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/character/picker.dart';

class TheaterSetupSection extends ConsumerWidget {
  const TheaterSetupSection({
    super.key,
    required this.run,
    required this.modelSelector,
  });

  final TheaterRun run;
  final Widget modelSelector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final characters = run.characters;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      borderSide: BorderSide(color: colors.borderInput),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.person_outline,
                size: 14,
                color: colors.accentWarm,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.theaterSelectCharacters),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          if (characters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
              child: Text(
                context.t(LocaleKeys.theaterNoCharacters),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            )
          else
            CharacterPicker(
              characters: characters,
              selectedIds: run.selectedCharacterIds,
              accentColor: colors.accentWarm,
              multiSelect: true,
              onToggle: run.toggleCharacter,
              onSelectAll: () =>
                  run.setSelectedCharacters({for (final c in characters) c.id}),
              onClear: () => run.setSelectedCharacters(const {}),
            ),
          const SizedBox(height: RevericSpacing.x2l),
          Text(
            context.t(LocaleKeys.theaterSceneDescription),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          TextField(
            controller: run.sceneController,
            maxLines: 3,
            minLines: 1,
            style: typo.ui.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: context.t(LocaleKeys.theaterSceneHint),
              hintStyle: typo.ui.copyWith(color: colors.textSubtle),
              filled: true,
              fillColor: colors.surface,
              border: inputBorder,
              enabledBorder: inputBorder,
              focusedBorder: inputBorder.copyWith(
                borderSide: BorderSide(color: colors.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.xl,
                vertical: RevericSpacing.lg,
              ),
            ),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          Row(
            children: [
              Text(
                '${context.t(LocaleKeys.theaterRounds)}: ${run.config.maxRounds}',
                style: typo.ui.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: RevericSpacing.md),
              Expanded(
                child: Slider(
                  value: run.config.maxRounds.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: run.config.maxRounds.toString(),
                  onChanged: (value) => ref
                      .read(theaterConfigProvider.notifier)
                      .updateMaxRounds(value.toInt()),
                ),
              ),
            ],
          ),
          modelSelector,
          const SizedBox(height: RevericSpacing.md),
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
                  : RevericIcon(
                      RevericIcons.theater_comedy_rounded,
                      size: 18,
                    ),
              label: Text(
                run.isRunning
                    ? context.t(LocaleKeys.theaterPerforming)
                    : context.t(LocaleKeys.theaterStart),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
