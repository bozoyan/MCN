// 职责: 小说编辑侧边栏 — 构建文档树节点、叶子项和底部品牌栏。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
part of 'sidebar.dart';

extension _LeftSidebarTreeItems on _LeftSidebarState {
  Widget _buildDocumentItem(
    BuildContext context,
    Document document,
    NovelWorkspaceSection section,
    int depth, {
    required bool hasChildren,
  }) {
    final isFolder = document.isFolder;
    final isExpanded = _expandedFolderIds(section).contains(document.id);
    final isSelected =
        widget.selection.section == section &&
        widget.selection.itemId == document.id &&
        !_hasAuxiliaryContentSelection;

    if (isFolder) {
      return _buildTreeRowWithContextMenu(
        context,
        depth: depth,
        iconAsset: isExpanded ? _iconFolderOpen : _iconFolder,
        label: document.title.isEmpty
            ? context.t(LocaleKeys.sidebarUntitledFolder)
            : document.title,
        isExpanded: isExpanded,
        isSelected: isSelected,
        showArrow: hasChildren,
        document: document,
        onTap: () {
          _toggleExpandedFolder(section, document.id);
          widget.onSelect(
            WorkspaceSelection(section: section, itemId: document.id),
          );
        },
      );
    }

    return _buildLeafWithContextMenu(
      context,
      depth: depth,
      label: document.title.isEmpty
          ? context.t(LocaleKeys.sidebarUntitledDocument)
          : document.title,
      section: section,
      itemId: document.id,
      document: document,
    );
  }

  Widget _buildLeaf(
    BuildContext context, {
    required int depth,
    required String label,
    required NovelWorkspaceSection section,
    String? itemId,
    Widget? trailingWidget,
    RevericColors? colors,
    RevericTypography? typo,
  }) {
    final c = colors ?? RevericTheme.colorsOf(context);
    final t = typo ?? RevericTheme.typographyOf(context);
    final child = _buildTreeRow(
      context,
      colors: c,
      typo: t,
      depth: depth,
      iconAsset: _iconFileText,
      label: label,
      trailingWidget: trailingWidget,
      isSelected:
          widget.selection.section == section &&
          widget.selection.itemId == itemId &&
          !_hasAuxiliaryContentSelection,
      onTap: () {
        widget.onSelect(WorkspaceSelection(section: section, itemId: itemId));
      },
    );

    if (itemId == null) return child;
    final reference = AiContextReference(
      section: section,
      itemId: itemId,
      label: label,
    );

    return Draggable<AiContextReference>(
      data: reference,
      feedback: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(color: c.accent),
            boxShadow: [
              BoxShadow(
                color: c.textPrimary.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _themedSvgIcon(_iconFileText, size: 14, color: c.accent),
              const SizedBox(width: RevericSpacing.xs),
              Text(label, style: t.uiSmall.copyWith(color: c.textPrimary)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildCharacterLeaf(
    BuildContext context, {
    required int depth,
    required String label,
    required String itemId,
  }) {
    final child = _buildLeaf(
      context,
      depth: depth,
      label: label,
      section: NovelWorkspaceSection.characters,
      itemId: itemId,
    );

    if (widget.onOpenMonologueWithId == null && widget.onDeleteItem == null) {
      return child;
    }

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showCharacterContextMenu(context, details, itemId, label);
      },
      child: child,
    );
  }

  void _showCharacterContextMenu(
    BuildContext context,
    TapDownDetails details,
    String characterId,
    String characterName,
  ) {
    final colors = RevericTheme.colorsOf(context);

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        if (widget.onOpenMonologueWithId != null)
          RevericMenuItem(
            icon: _iconUser,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.aiSessionModeMonologue),
            onTap: () => widget.onOpenMonologueWithId?.call(characterId),
          ),
        if (widget.onOpenMonologueWithId != null && widget.onDeleteItem != null)
          const RevericMenuDivider(),
        if (widget.onDeleteItem != null)
          RevericMenuItem(
            icon: _iconTrashSimple,
            iconColor: colors.warningText,
            labelColor: colors.warningText,
            label: context.t(LocaleKeys.commonDelete),
            onTap: () => _confirmDeleteItem(
              context,
              label: characterName,
              section: NovelWorkspaceSection.characters,
              itemId: characterId,
            ),
          ),
      ],
    );
  }

  Widget _buildItemLeaf(
    BuildContext context, {
    required int depth,
    required String label,
    required NovelWorkspaceSection section,
    required String itemId,
  }) {
    final child = _buildTreeRow(
      context,
      depth: depth,
      iconAsset: _iconFileText,
      label: label,
      isSelected:
          widget.selection.section == section &&
          widget.selection.itemId == itemId &&
          !_hasAuxiliaryContentSelection,
      onTap: () {
        widget.onSelect(WorkspaceSelection(section: section, itemId: itemId));
      },
    );

    if (widget.onDeleteItem == null) return child;

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final reference = AiContextReference(
      section: section,
      itemId: itemId,
      label: label,
    );

    final draggable = Draggable<AiContextReference>(
      data: reference,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(color: colors.accent),
            boxShadow: [
              BoxShadow(
                color: colors.textPrimary.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _themedSvgIcon(_iconFileText, size: 14, color: colors.accent),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                label,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );

    if (widget.onDeleteItem == null) return draggable;

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showDeleteItemContextMenu(context, details, label, section, itemId);
      },
      child: draggable,
    );
  }

  Widget _buildTreeRow(
    BuildContext context, {
    RevericColors? colors,
    RevericTypography? typo,
    required int depth,
    required String iconAsset,
    required String label,
    String? trailing,
    Widget? trailingWidget,
    bool isExpanded = false,
    bool isSelected = false,
    bool showArrow = false,
    VoidCallback? onTap,
  }) {
    final c = colors ?? RevericTheme.colorsOf(context);
    final t = typo ?? RevericTheme.typographyOf(context);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? c.selected : Colors.transparent,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: RevericSpacing.md + depth * RevericSpacing.x2l,
              right: RevericSpacing.x2l,
              top: RevericSpacing.xs,
              bottom: RevericSpacing.xs,
            ),
            child: Row(
              children: [
                if (showArrow) ...[
                  _themedSvgIcon(
                    isExpanded ? _iconCaretDown : _iconCaretRight,
                    size: 14,
                    color: c.textSubtle,
                  ),
                  const SizedBox(width: RevericSpacing.xxs),
                ],
                _themedSvgIcon(iconAsset, size: 16, color: c.accent),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: (isSelected ? t.uiSemibold : t.ui).copyWith(
                      color: isSelected ? c.textPrimary : c.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailingWidget != null) ...[
                  const SizedBox(width: RevericSpacing.xxs),
                  trailingWidget,
                ],
                if (trailing != null)
                  Text(trailing, style: t.uiTiny.copyWith(color: c.textSubtle)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
