// 职责: 小说编辑侧边栏 — 构建折叠按钮、工作区标题和小说切换菜单。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/desktop/widgets/sidebar/rail.dart
//   lib/desktop/widgets/context_column/context_column_scaffold.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/desktop-window-frame.md
//   .agents/rules/icons.md
//   .agents/rules/state-management.md
part of 'sidebar.dart';

Widget _buildSidebarCollapseButton(
  BuildContext context, {
  required VoidCallback onTap,
}) {
  final colors = RevericTheme.colorsOf(context);
  return Tooltip(
    message: context.t(LocaleKeys.commonCollapseSidebar),
    child: SizedBox.square(
      dimension: RevericSizes.iconButtonSize,
      child: InkWell(
        key: const ValueKey('sidebar-collapse-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.all(RevericSizes.iconButtonPadding),
          child: SvgPicture.asset(
            'assets/icons/collapse.svg',
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(colors.textMuted, BlendMode.srcIn),
          ),
        ),
      ),
    ),
  );
}

extension _LeftSidebarHeader on _LeftSidebarState {
  Widget _buildWorkspaceHeader(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final resolvedCoverPath = watchMediaAssetFile(ref, widget.coverAssetId);
    final coverFile = resolvedCoverPath == null
        ? null
        : File(resolvedCoverPath);
    final hasCover = coverFile != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.xl,
      ),
      child: Row(
        children: [
          if (hasCover)
            ClipRRect(
              borderRadius: BorderRadius.circular(RevericRadius.small),
              child: Image.file(
                coverFile,
                width: RevericSizes.avatarRadiusLg * 2,
                height: RevericSizes.avatarRadiusLg * 2,
                fit: BoxFit.cover,
                cacheWidth: (RevericSizes.avatarRadiusLg * 4).toInt(),
              ),
            )
          else
            CircleAvatar(
              radius: RevericSizes.avatarRadiusLg,
              backgroundColor: colors.accent,
              child: Text(
                widget.novelTitle.characters.firstOrNull?.toUpperCase() ?? 'N',
                style: typo.uiSemibold.copyWith(color: colors.onAccent),
              ),
            ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Text(
              widget.novelTitle,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildNovelSwitcher(context),
        ],
      ),
    );
  }

  Widget _buildNovelSwitcher(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return InkWell(
      key: const ValueKey('sidebar-novel-switcher'),
      onTap: () {
        _showNovelSwitcherMenu(context);
      },
      borderRadius: BorderRadius.circular(RevericRadius.small),
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.xs),
        child: _themedSvgIcon(
          _iconCaretDown,
          size: 20,
          color: colors.textSubtle,
        ),
      ),
    );
  }

  void _showNovelSwitcherMenu(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RevericRadius.x2l),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(RevericSpacing.x2l),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t(LocaleKeys.libraryMyNovels),
                        style: typo.uiSemibold.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: _themedSvgIcon(
                        _iconX,
                        size: 20,
                        color: colors.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: RevericSizes.dividerThickness,
                color: colors.borderSubtle,
              ),
              Flexible(
                // 订阅随菜单路由挂载与卸载，书库更新只重建菜单列表。
                child: Consumer(
                  builder: (context, ref, _) {
                    final novels = [
                      for (final novel
                          in ref.watch(novelsProvider).asData?.value ??
                              const <Novel>[])
                        if (novel.id == widget.currentNovelId ||
                            (!novel.draft &&
                                novel.deletedAt == notDeletedSentinel))
                          novel,
                    ];
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: novels.length,
                      itemBuilder: (context, index) {
                        final novel = novels[index];
                        final isCurrent = novel.id == widget.currentNovelId;
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            if (!isCurrent) {
                              widget.onSwitchNovel(novel);
                            }
                          },
                          child: Container(
                            color: isCurrent
                                ? colors.selected
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: RevericSpacing.x2l,
                              vertical: RevericSpacing.lg,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: colors.accent,
                                  child: Text(
                                    novel.title.characters.firstOrNull
                                            ?.toUpperCase() ??
                                        'N',
                                    style: typo.uiSmallSemibold.copyWith(
                                      color: colors.onAccent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: RevericSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        novel.title,
                                        style:
                                            (isCurrent
                                                    ? typo.uiSemibold
                                                    : typo.ui)
                                                .copyWith(
                                                  color: isCurrent
                                                      ? colors.textPrimary
                                                      : colors.textSecondary,
                                                ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (novel.description.isNotEmpty)
                                        Text(
                                          novel.description,
                                          style: typo.uiSmall.copyWith(
                                            color: colors.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (isCurrent)
                                  _themedSvgIcon(
                                    _iconCheck,
                                    size: 18,
                                    color: colors.accent,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: RevericSpacing.lg),
            ],
          ),
        );
      },
    );
  }

  void _showRootContextMenu(
    BuildContext context,
    TapDownDetails details,
    NovelWorkspaceSection section,
  ) {
    final colors = RevericTheme.colorsOf(context);

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        if (widget.onImportDocument != null)
          RevericMenuItem(
            icon: _iconFileText,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceImportFile),
            onTap: () => widget.onImportDocument!(section, null),
          ),
        if (widget.onCreateFolder != null)
          RevericMenuItem(
            icon: _iconFolderPlus,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceNewFolder),
            onTap: () => widget.onCreateFolder!(section),
          ),
        if (widget.onCreateDocument != null)
          RevericMenuItem(
            icon: _iconNotePencil,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceNewDocument),
            onTap: () => widget.onCreateDocument!(section),
          ),
      ],
    );
  }
}
