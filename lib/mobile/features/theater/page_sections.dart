// 职责: 移动端小剧场页的视图分区 — 未配置提示、Setup 配置区、Performance 表演区，及模型选择底部弹窗。
// 关联文件:
//   lib/mobile/features/theater/page.dart
//   lib/mobile/features/theater/page_widgets.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/models/theater_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/theater.json
//   assets/translations/zh-CN/theater.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
part of 'page.dart';

extension _MobileTheaterPageSections on MobileTheaterPage {
  Widget _buildConfigHint(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x3l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.psychology_outlined,
              size: 48,
              color: colors.textMuted,
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.aiNotConfigured),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              context.t(LocaleKeys.aiPleaseConfigure),
              textAlign: TextAlign.center,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            RevericButton.primary(
              label: context.t(LocaleKeys.aiConfigureProvider),
              icon: RevericIcons.settings_outlined,
              onPressed: () => openMobileAiProvidersSettingsPage(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup(
    BuildContext context,
    WidgetRef ref,
    RevericColors colors,
    RevericTypography typo, {
    required TheaterRun run,
  }) {
    final characters = run.characters;
    final config = run.config;
    final models = run.models;
    final t = context.t;
    final selectedCount = run.selectedCharacterIds.length;
    final totalCount = characters.length;
    final hasEnough = selectedCount >= 2;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.person_outline,
                  accentColor: colors.accent,
                  title: t(LocaleKeys.theaterSelectCharacters),
                  trailing: characters.isEmpty
                      ? null
                      : Text(
                          t(
                            LocaleKeys.theaterCharactersCountFmt,
                            namedArgs: {
                              'selected': '$selectedCount',
                              'total': '$totalCount',
                            },
                          ),
                          style: typo.uiTiny.copyWith(color: colors.textMuted),
                        ),
                  child: characters.isEmpty
                      ? Text(
                          t(LocaleKeys.theaterNoCharacters),
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CharacterPicker(
                              characters: characters,
                              selectedIds: run.selectedCharacterIds,
                              accentColor: colors.accent,
                              multiSelect: true,
                              maxListHeight: null,
                              gridColumnCount: null,
                              onToggle: run.toggleCharacter,
                              onSelectAll: () => run.setSelectedCharacters({
                                for (final c in characters) c.id,
                              }),
                              onClear: () =>
                                  run.setSelectedCharacters(const {}),
                            ),
                            if (!hasEnough) ...[
                              const SizedBox(height: RevericSpacing.sm),
                              Text(
                                t(LocaleKeys.theaterMinCharactersHint),
                                style: typo.uiTiny.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.theater_comedy_rounded,
                  accentColor: colors.accentWarm,
                  title: t(LocaleKeys.theaterSceneDescription),
                  child: TextField(
                    controller: run.sceneController,
                    maxLines: 4,
                    minLines: 2,
                    style: typo.ui.copyWith(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: t(LocaleKeys.theaterSceneHint),
                      hintStyle: typo.ui.copyWith(color: colors.textSubtle),
                      filled: true,
                      fillColor: colors.surface,
                      border: _inputBorder(colors.borderInput),
                      enabledBorder: _inputBorder(colors.borderInput),
                      focusedBorder: _inputBorder(colors.accent),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.history_rounded,
                  accentColor: colors.accentAmber,
                  title: t(LocaleKeys.theaterRounds),
                  trailing: Text(
                    '${config.maxRounds}',
                    style: typo.uiSemibold.copyWith(color: colors.accentAmber),
                  ),
                  child: Slider(
                    value: config.maxRounds.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: config.maxRounds.toString(),
                    onChanged: (value) => ref
                        .read(theaterConfigProvider.notifier)
                        .updateMaxRounds(value.toInt()),
                  ),
                ),
              ],
            ),
          ),
        ),
        _TheaterStartBar(
          isRunning: run.isRunning,
          isEnabled: hasEnough,
          availableModels: models.availableModels
              .where((m) => m.kind == AiModelKind.chat)
              .toList(growable: false),
          displayedModel: models.displayed,
          selectedEffort: models.selectedEffort,
          disabledModelIds: const <String>{},

          onSelectModel: models.select,
          onSelectEffort: models.selectWithEffort,
          onStart: run.start,
        ),
      ],
    );
  }

  Widget _setupSection({
    required RevericColors colors,
    required RevericTypography typo,
    required String icon,
    required Color accentColor,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(icon, size: 14, color: accentColor),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            if (trailing != null) ...[const Spacer(), trailing],
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

  Widget _buildPerformance(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo, {
    required TheaterRun run,
    required TheaterSession session,
    required Widget modelSelector,
    required Future<void> Function(String title) onOpenActiveRunDetail,
    Future<void> Function(String? instruction)? onSwitchToWriteMode,
  }) {
    final isPerforming = session.phase == TheaterPhase.performing;
    final canEdit = !isPerforming && !run.isRunning;
    final directorBar = TheaterDirectorBar(run: run, session: session);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x2l,
            RevericSpacing.lg,
            RevericSpacing.x2l,
            RevericSpacing.lg,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(LocaleKeys.theaterSceneDescription),
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                session.sceneDescription,
                style: typo.body.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: RevericSpacing.md),
              Wrap(
                spacing: RevericSpacing.sm,
                runSpacing: RevericSpacing.sm,
                children: [
                  for (final participant in session.participants)
                    _TheaterParticipantBadge(
                      participant: participant,
                      colors: colors,
                      typo: typo,
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _TheaterLineList(
            session: session,
            activeRun: run.activeRun,
            runHistory: run.runHistory,
            colors: colors,
            typo: typo,
            onOpenActiveRunDetail: onOpenActiveRunDetail,
            databasePath: databasePath,
            novelId: novelId,
            onRegenerate: canEdit ? run.regenerate : null,
            onRewindAfter: canEdit ? run.rewindAfter : null,
            onRemoveDirection: canEdit ? run.removeLine : null,
          ),
        ),
        if (isPerforming)
          _TheaterActiveBar(
            session: session,
            activeRun: run.activeRun,
            directorBar: directorBar,
            modelSelector: modelSelector,
            onPause: run.pause,
            onCancel: run.cancel,
          )
        else
          _TheaterCompletedBar(
            isRunning: run.isRunning,
            directorBar: directorBar,
            modelSelector: modelSelector,
            session: session,
            onContinue: run.continueRun,
            onSwitchToWriteMode: onSwitchToWriteMode,
          ),
      ],
    );
  }
}

InputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(RevericRadius.xl),
  borderSide: BorderSide(color: color),
);
