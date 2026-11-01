// 职责: 移动端独白页的视图分区 — 未配置提示、Setup 配置区、独白展示区。
// 关联文件:
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/monologue/page_widgets.dart
//   lib/shared/hooks/use_monologue_run.dart
//   lib/shared/models/monologue_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
part of 'page.dart';

extension _MobileMonologuePageSections on MobileMonologuePage {
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
    required MonologueRun run,
  }) {
    final characters = run.characters;
    final models = run.models;
    final t = context.t;

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
                  title: t(LocaleKeys.monologueSelectCharacter),
                  trailing:
                      characters.any((c) => c.id == run.selectedCharacterId)
                      ? _SelectedChip(
                          label: t(LocaleKeys.monologueSelectedChip),
                          accentColor: colors.accent,
                          colors: colors,
                          typo: typo,
                        )
                      : null,
                  child: characters.isEmpty
                      ? Text(
                          t(LocaleKeys.monologueNoCharacters),
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        )
                      : CharacterPicker(
                          characters: characters,
                          selectedIds: {?run.selectedCharacterId},
                          accentColor: colors.accent,
                          maxListHeight: null,
                          gridColumnCount: null,
                          onToggle: run.toggleCharacter,
                        ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _setupSection(
                  colors: colors,
                  typo: typo,
                  icon: RevericIcons.chat_bubble_outline,
                  accentColor: colors.accentWarm,
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
              ],
            ),
          ),
        ),
        _MonologueStartBar(
          isRunning: run.isRunning,
          canStart: run.canStart,
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

  Widget _buildMonologue(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo, {
    required MonologueRun run,
    required MonologueSession session,
    required Widget modelSelector,
    required Future<void> Function(String title) onOpenActiveRunDetail,
    Future<void> Function()? onSwitchToWriteMode,
  }) {
    final isGenerating = session.phase == MonologuePhase.generating;

    // 议题可能很长：header 是 Column 的固定 child，必须给议题文本限高，
    // 否则长议题会把 Expanded 消息列表压到 0 高度，无法滚动查看生成内容。
    // LayoutBuilder 必须包在 Column 外层：Column 给非 flex 子节点的高度约束
    // 无界（maxHeight = infinity），包在里面算出的比例限高不会生效。
    return LayoutBuilder(
      builder: (context, constraints) {
        final topicMaxHeight = constraints.maxHeight * 0.3;
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
                    context.t(LocaleKeys.monologueTopic),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: topicMaxHeight),
                    // Column 的 start 对齐给的是宽松宽度，滚动视口会缩到最长行
                    // 宽，滚动条悬浮在文字中间；必须显式撑满宽度。
                    // shrinkWrap 让短议题按内容收缩，不会始终占满上限高度。
                    child: SizedBox(
                      width: double.infinity,
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          Text(
                            session.topic,
                            style: typo.body.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _MonologueList(
                session: session,
                activeRun: run.activeRun,
                runHistory: run.runHistory,
                colors: colors,
                typo: typo,
                onOpenActiveRunDetail: onOpenActiveRunDetail,
              ),
            ),
            if (isGenerating)
              _MonologueActiveBar(
                session: session,
                modelSelector: modelSelector,
                onPause: run.pause,
                onCancel: run.cancel,
              )
            else
              _MonologueCompletedBar(
                isRunning: run.isRunning,
                modelSelector: modelSelector,
                onContinue: run.continueRun,
                onSwitchToWriteMode: onSwitchToWriteMode,
              ),
          ],
        );
      },
    );
  }
}

InputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(RevericRadius.xl),
  borderSide: BorderSide(color: color),
);
