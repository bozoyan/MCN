// 职责: 移动端角色扮演页的视图分区 — 未配置提示、Setup 选角区、Chat 对话区。
// 关联文件:
//   lib/mobile/features/roleplay/page.dart
//   lib/mobile/features/roleplay/page_widgets.dart
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
part of 'page.dart';

extension _MobileRoleplayPageSections on MobileRoleplayPage {
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
    RevericColors colors,
    RevericTypography typo, {
    required RoleplayRun run,
  }) {
    final t = context.t;
    final characters = run.characters;
    final selected = run.selectedCharacter;

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
                  accentColor: colors.accentWarm,
                  title: t(LocaleKeys.roleplaySelectCharacter),
                  child: characters.isEmpty
                      ? Text(
                          t(LocaleKeys.roleplayNoCharacters),
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        )
                      : CharacterPicker(
                          characters: characters,
                          selectedIds: {?selected?.id},
                          accentColor: colors.accentWarm,
                          maxListHeight: null,
                          gridColumnCount: null,
                          onToggle: run.toggleCharacter,
                        ),
                ),
              ],
            ),
          ),
        ),
        _RoleplayComposer(run: run, hintName: selected?.name ?? ''),
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

  Widget _buildChat(
    BuildContext context, {
    required RoleplayRun run,
    required RoleplaySession session,
    required Future<void> Function(String title) onOpenActiveRunDetail,
    Future<void> Function()? onSwitchToWriteMode,
  }) {
    return Column(
      children: [
        Expanded(
          child: _RoleplayMessageList(
            session: session,
            activeRun: run.activeRun,
            runHistory: run.runHistory,
            userAvatarPath: run.userAvatarPath,
            userName: run.userName,
            databasePath: databasePath,
            novelId: novelId,
            onOpenActiveRunDetail: onOpenActiveRunDetail,
          ),
        ),
        _RoleplayComposer(
          run: run,
          hintName: session.character.name,
          onSwitchToWriteMode: onSwitchToWriteMode,
        ),
      ],
    );
  }
}
