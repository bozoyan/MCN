// 职责: 小说编辑侧边栏 — 构建章节树、分卷行、章节行与章节上下文操作。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/chapter.json
//   assets/translations/zh-CN/chapter.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/sidebar.json
//   assets/translations/zh-CN/sidebar.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
part of 'sidebar.dart';

extension _LeftSidebarChapterTree on _LeftSidebarState {
  Widget _buildChapterSectionPanel(BuildContext context) {
    const section = NovelWorkspaceSection.chapters;
    final canCreateChapter = widget.onCreateChapterInVolume != null;
    final hasQuery = _hasSearchQueryForSection(section);
    final visibleChapters = hasQuery
        ? _filterChaptersBySearch(context, widget.chapters)
        : widget.chapters;
    final expandedFolderIds = hasQuery
        ? visibleChapters
              .where((chapter) => chapter.isVolume)
              .map((c) => c.id)
              .toSet()
        : _expandedFolderIds(section);

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final sortDescending = ref.watch(chapterSortDescendingProvider);

    final data = _ChapterTreeData.from(
      chapters: visibleChapters,
      expandedFolderIds: expandedFolderIds,
      canCreateChapter: canCreateChapter && !hasQuery,
      canCreateRootChapter: !hasQuery,
      descending: sortDescending,
      chapterLabelOf: (chapter) => _chapterDisplayLabel(context, chapter),
    );
    final chapterCount = widget.chapters
        .where((chapter) => chapter.isNumberedChapter)
        .length;

    return ListView.builder(
      padding: const EdgeInsets.only(top: RevericSpacing.sm),
      addAutomaticKeepAlives: false,
      itemCount: 2 + (data.rows.isEmpty ? 1 : data.rows.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildPanelSectionHeader(
            context,
            title: context.t(LocaleKeys.workspaceChapters),
            count: chapterCount,
            useProminentMetrics: true,
            onAddFolder: widget.onCreateVolume == null
                ? null
                : () => unawaited(widget.onCreateVolume!()),
            onToggleSort: () => unawaited(
              ref
                  .read(appSettingsNotifierProvider.notifier)
                  .setChapterSortDescending(!sortDescending),
            ),
            sortDescending: sortDescending,
          );
        }
        if (index == 1) {
          return _buildSectionSearchField(context, section: section);
        }
        if (data.rows.isEmpty) {
          return _buildEmptyHint(context);
        }

        final row = data.rows[index - 2];
        return switch (row.kind) {
          _ChapterTreeRowKind.volume => _buildVolumeItem(
            context,
            row.chapter!,
            data,
            colors: colors,
            typo: typo,
          ),
          _ChapterTreeRowKind.chapter => _buildChapterLeaf(
            context,
            row.chapter!,
            depth: row.depth,
            label: row.label,
            colors: colors,
            typo: typo,
          ),
          _ChapterTreeRowKind.addChapter => _buildAddChapterRow(
            context,
            depth: row.depth,
            onTap: () {
              unawaited(widget.onCreateChapterInVolume!(row.volumeId!));
            },
            colors: colors,
            typo: typo,
          ),
          _ChapterTreeRowKind.addRootChapter => _buildAddChapterRow(
            context,
            depth: row.depth,
            onTap: () {
              unawaited(widget.onCreateChapter());
            },
            colors: colors,
            typo: typo,
          ),
        };
      },
    );
  }

  List<Chapter> _filterChaptersBySearch(
    BuildContext context,
    List<Chapter> chapters,
  ) {
    final byId = {for (final chapter in chapters) chapter.id: chapter};
    final visibleIds = <String>{};

    void addWithAncestors(Chapter chapter) {
      var current = chapter;
      while (visibleIds.add(current.id)) {
        final parentId = current.parentId;
        if (parentId == null) {
          break;
        }
        final parent = byId[parentId];
        if (parent == null) {
          break;
        }
        current = parent;
      }
    }

    for (final chapter in chapters) {
      final label = chapter.isVolume
          ? chapter.displayTitle
          : _chapterDisplayLabel(context, chapter);
      if (_matchesSearchQuery(NovelWorkspaceSection.chapters, label)) {
        addWithAncestors(chapter);
      }
    }

    return chapters
        .where((chapter) => visibleIds.contains(chapter.id))
        .toList();
  }

  Widget _buildChapterStatBadge(
    BuildContext context,
    String stat, {
    RevericColors? colors,
  }) {
    final c = colors ?? RevericTheme.colorsOf(context);
    final isPublished = stat == chapterStatPublished;

    return _themedSvgIcon(
      isPublished ? _iconCheckCircle : _iconFileText,
      size: 14,
      color: isPublished ? c.additionBorder : c.textMuted,
    );
  }

  Widget _buildVolumeItem(
    BuildContext context,
    Chapter volume,
    _ChapterTreeData data, {
    RevericColors? colors,
    RevericTypography? typo,
  }) {
    final c = colors ?? RevericTheme.colorsOf(context);
    final t = typo ?? RevericTheme.typographyOf(context);
    final isExpanded = _expandedFolderIds(
      NovelWorkspaceSection.chapters,
    ).contains(volume.id);
    final children = data.childrenByVolume[volume.id] ?? const <Chapter>[];
    final canCreateChapter = widget.onCreateChapterInVolume != null;

    final headerRow = _buildTreeRow(
      context,
      colors: c,
      typo: t,
      depth: 0,
      iconAsset: _iconBookOpen,
      label: volume.displayTitle,
      isExpanded: isExpanded,
      isSelected:
          widget.selection.section == NovelWorkspaceSection.chapters &&
          widget.selection.itemId == volume.id &&
          !_hasAuxiliaryContentSelection,
      showArrow: children.isNotEmpty || canCreateChapter,
      onTap: () {
        _toggleExpandedFolder(NovelWorkspaceSection.chapters, volume.id);
        widget.onSelect(
          WorkspaceSelection(
            section: NovelWorkspaceSection.chapters,
            itemId: volume.id,
          ),
        );
      },
    );
    final reference = AiContextReference(
      section: NovelWorkspaceSection.chapters,
      itemId: volume.id,
      label: volume.displayTitle,
      path: '/volumes/${volume.id}',
    );

    final draggableHeader = Draggable<AiContextReference>(
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
              _themedSvgIcon(_iconBookOpen, size: 14, color: c.accent),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                volume.displayTitle,
                style: t.uiSmall.copyWith(color: c.textPrimary),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: headerRow),
      child: headerRow,
    );

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showVolumeContextMenu(context, details, volume);
      },
      child: DragTarget<AiContextReference>(
        onWillAcceptWithDetails: (details) {
          final ref = details.data;
          if (ref.section != NovelWorkspaceSection.chapters) {
            return false;
          }
          if (ref.itemId == volume.id) {
            return false;
          }
          return data.chapterIds.contains(ref.itemId);
        },
        onAcceptWithDetails: (details) {
          final id = details.data.itemId;
          if (id == volume.id) {
            return;
          }
          _expandFolder(NovelWorkspaceSection.chapters, volume.id);
          unawaited(widget.onMoveToVolume?.call(id, volume.id));
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isHovering ? c.accent.withAlpha(25) : Colors.transparent,
            ),
            child: draggableHeader,
          );
        },
      ),
    );
  }

  Widget _buildAddChapterRow(
    BuildContext context, {
    required int depth,
    required VoidCallback onTap,
    RevericColors? colors,
    RevericTypography? typo,
  }) {
    final c = colors ?? RevericTheme.colorsOf(context);
    final t = typo ?? RevericTheme.typographyOf(context);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.hover,
        child: Padding(
          padding: EdgeInsets.only(
            left: RevericSpacing.md + depth * RevericSpacing.x2l,
            right: RevericSpacing.x2l,
            top: RevericSpacing.xs,
            bottom: RevericSpacing.xs,
          ),
          child: Row(
            children: [
              _themedSvgIcon(_iconPlus, size: 16, color: c.textSubtle),
              const SizedBox(width: RevericSpacing.xs),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.workspaceAddChapter),
                  style: t.ui.copyWith(color: c.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVolumeContextMenu(
    BuildContext context,
    TapDownDetails details,
    Chapter volume,
  ) {
    final colors = RevericTheme.colorsOf(context);
    final onCreate = widget.onCreateChapterInVolume;

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        if (onCreate != null)
          RevericMenuItem(
            icon: _iconPlus,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceNewChapter),
            onTap: () {
              _expandFolder(NovelWorkspaceSection.chapters, volume.id);
              unawaited(onCreate(volume.id));
            },
          ),
        RevericMenuItem(
          icon: _iconPencilSimple,
          iconColor: colors.accent,
          label: context.t(LocaleKeys.sidebarMoveToPosition),
          onTap: () => _showMoveToPositionDialog(context, volume),
        ),
        if (widget.onDeleteChapter != null)
          RevericMenuItem(
            icon: _iconTrashSimple,
            iconColor: colors.warningText,
            labelColor: colors.warningText,
            label: context.t(LocaleKeys.commonDelete),
            onTap: () => _confirmDeleteChapter(context, volume),
          ),
      ],
    );
  }

  Widget _buildChapterLeaf(
    BuildContext context,
    Chapter chapter, {
    int depth = 0,
    String? label,
    RevericColors? colors,
    RevericTypography? typo,
  }) {
    final resolvedLabel = label ?? _chapterDisplayLabel(context, chapter);
    final leaf = _buildLeaf(
      context,
      colors: colors,
      typo: typo,
      depth: depth,
      label: resolvedLabel,
      section: NovelWorkspaceSection.chapters,
      itemId: chapter.id,
      trailingWidget: _buildChapterStatBadge(
        context,
        chapter.stat,
        colors: colors,
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showChapterContextMenu(context, details, chapter);
      },
      child: leaf,
    );
  }

  void _showChapterContextMenu(
    BuildContext context,
    TapDownDetails details,
    Chapter chapter,
  ) {
    final colors = RevericTheme.colorsOf(context);
    final isPublished = chapter.stat == chapterStatPublished;

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        RevericMenuItem(
          icon: _iconPencilSimple,
          iconColor: colors.accent,
          label: context.t(LocaleKeys.sidebarMoveToPosition),
          onTap: () => _showMoveToPositionDialog(context, chapter),
        ),
        if (widget.onDeleteChapter != null)
          RevericMenuItem(
            icon: _iconTrashSimple,
            iconColor: colors.warningText,
            labelColor: colors.warningText,
            label: context.t(LocaleKeys.commonDelete),
            onTap: () => _confirmDeleteChapter(context, chapter),
          ),
        if (!isPublished && widget.onPublishChapter != null)
          RevericMenuItem(
            icon: _iconCheckCircle,
            iconColor: colors.additionBorder,
            label: context.t(LocaleKeys.chapterPublish),
            onTap: () => _confirmPublishChapter(context, chapter),
          ),
        if (isPublished && widget.onUpdateChapterStat != null)
          RevericMenuItem(
            icon: _iconArrowCounterClockwise,
            iconColor: colors.textMuted,
            label: context.t(LocaleKeys.chapterUnpublish),
            onTap: () =>
                widget.onUpdateChapterStat!(chapter.id, chapterStatDraft),
          ),
      ],
    );
  }

  void _confirmDeleteChapter(BuildContext context, Chapter chapter) {
    final title = chapter.isVolume
        ? chapter.displayTitle
        : _chapterDisplayLabel(context, chapter);
    final confirmKey = chapter.isVolume
        ? LocaleKeys.sidebarDeleteVolumeConfirm
        : LocaleKeys.sidebarDeleteChapterConfirm;

    unawaited(
      showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(confirmKey, namedArgs: {'title': title}),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
        onConfirm: () async {
          widget.onDeleteChapter?.call(chapter.id);
        },
      ),
    );
  }

  void _showMoveToPositionDialog(BuildContext context, Chapter node) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final siblings =
        widget.chapters.where((c) => c.parentId == node.parentId).toList()
          ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
    final currentPos = siblings.indexWhere((c) => c.id == node.id) + 1;
    final total = siblings.length;

    final controller = TextEditingController(text: '$currentPos');

    showRevericDialog<void>(
      context: context,
      builder: (dialogContext) {
        return RevericDialog(
          title: context.t(LocaleKeys.sidebarMoveToPosition),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(
                  LocaleKeys.sidebarCurrentPosition,
                  namedArgs: {'current': '$currentPos', 'total': '$total'},
                ),
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: RevericSpacing.md),
              RevericTextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                label: context.t(LocaleKeys.commonPosition),
              ),
            ],
          ),
          actions: [
            RevericButton.secondary(
              label: context.t(LocaleKeys.commonCancel),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            RevericButton.primary(
              label: context.t(LocaleKeys.commonConfirm),
              onPressed: () {
                final input = int.tryParse(controller.text.trim());
                if (input == null || input < 1 || input > total) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                if (input == currentPos) {
                  return;
                }
                unawaited(_moveToPosition(node.id, input));
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _moveToPosition(String nodeId, int newPosition) async {
    if (widget.databasePath == null) {
      return;
    }
    final service = ref.read(novelContentServiceProvider(widget.databasePath!));
    await service.moveSiblingToPosition(nodeId, newPosition);
  }

  void _confirmPublishChapter(BuildContext context, Chapter chapter) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = _chapterDisplayLabel(context, chapter);
    final canRunChronicler = chapter.wordCount > 0;

    var useChronicler = canRunChronicler;

    showRevericDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return RevericDialog(
              title: context.t(LocaleKeys.chapterPublish),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  ),
                  if (canRunChronicler) ...[
                    const SizedBox(height: RevericSpacing.md),
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: RevericCheckbox(
                            value: useChronicler,
                            onChanged: (v) {
                              setDialogState(() {
                                useChronicler = v;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              useChronicler = !useChronicler;
                            });
                          },
                          child: Text(
                            context.t(LocaleKeys.chapterRunChronicler),
                            style: typo.ui.copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                RevericButton.secondary(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                RevericButton.primary(
                  label: context.t(LocaleKeys.chapterPublish),
                  onPressed: () {
                    widget.onPublishChapter?.call(
                      chapter.id,
                      canRunChronicler && useChronicler,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  int? _chapterDisplayNumber(Chapter chapter) {
    if (chapter.isExtra) {
      return null;
    }
    if (chapter.parentId == null) {
      return chapter.chapterNum;
    }
    return chapter.volumeChapterNum ?? chapter.chapterNum;
  }

  String _chapterDisplayLabel(BuildContext context, Chapter chapter) {
    final title = chapter.title?.trim() ?? '';
    if (chapter.isExtra) {
      return title.isEmpty ? context.t(LocaleKeys.workspaceExtra) : title;
    }
    final chapterNumber = _chapterDisplayNumber(chapter);
    return '${context.t(LocaleKeys.commonChapterNumber, namedArgs: {'number': '${chapterNumber ?? "?"}'})} $title'
        .trim();
  }
}

final class _ChapterTreeData {
  const _ChapterTreeData({
    required this.rows,
    required this.childrenByVolume,
    required this.chapterIds,
    required this.numberedChapterCount,
  });

  final List<_ChapterTreeRow> rows;
  final Map<String, List<Chapter>> childrenByVolume;
  final Set<String> chapterIds;
  final int numberedChapterCount;

  factory _ChapterTreeData.from({
    required List<Chapter> chapters,
    required Set<String> expandedFolderIds,
    required bool canCreateChapter,
    required bool canCreateRootChapter,
    required String Function(Chapter) chapterLabelOf,
    bool descending = false,
  }) {
    final mount = mountChaptersForTree(chapters);

    final roots = descending ? mount.roots.reversed.toList() : mount.roots;

    final rows = <_ChapterTreeRow>[];
    for (final root in roots) {
      if (root.isVolume) {
        rows.add(_ChapterTreeRow.volume(root));
        if (expandedFolderIds.contains(root.id)) {
          final volumeChildren =
              mount.childrenByVolume[root.id] ?? const <Chapter>[];
          final children = descending
              ? volumeChildren.reversed.toList()
              : volumeChildren;
          if (canCreateChapter && descending) {
            rows.add(_ChapterTreeRow.addChapter(root.id, depth: 1));
          }
          for (final child in children) {
            rows.add(
              _ChapterTreeRow.chapter(
                child,
                depth: 1,
                label: chapterLabelOf(child),
              ),
            );
          }
          if (canCreateChapter && !descending) {
            rows.add(_ChapterTreeRow.addChapter(root.id, depth: 1));
          }
        }
      } else if (root.isChapter) {
        rows.add(
          _ChapterTreeRow.chapter(root, depth: 0, label: chapterLabelOf(root)),
        );
      }
    }
    if (canCreateRootChapter && !mount.hasVolume) {
      final addRootChapter = const _ChapterTreeRow.addRootChapter(depth: 0);
      if (descending) {
        rows.insert(0, addRootChapter);
      } else {
        rows.add(addRootChapter);
      }
    }

    return _ChapterTreeData(
      rows: rows,
      childrenByVolume: mount.childrenByVolume,
      chapterIds: mount.chapterIds,
      numberedChapterCount: mount.numberedChapterCount,
    );
  }
}

final class _ChapterTreeRow {
  const _ChapterTreeRow._({
    required this.kind,
    required this.depth,
    this.chapter,
    this.volumeId,
    this.label,
  });

  const _ChapterTreeRow.volume(Chapter chapter)
    : this._(kind: _ChapterTreeRowKind.volume, depth: 0, chapter: chapter);

  const _ChapterTreeRow.chapter(
    Chapter chapter, {
    required int depth,
    String? label,
  }) : this._(
         kind: _ChapterTreeRowKind.chapter,
         depth: depth,
         chapter: chapter,
         label: label,
       );

  const _ChapterTreeRow.addChapter(String volumeId, {required int depth})
    : this._(
        kind: _ChapterTreeRowKind.addChapter,
        depth: depth,
        volumeId: volumeId,
      );

  const _ChapterTreeRow.addRootChapter({required int depth})
    : this._(kind: _ChapterTreeRowKind.addRootChapter, depth: depth);

  final _ChapterTreeRowKind kind;
  final int depth;
  final Chapter? chapter;
  final String? volumeId;
  final String? label;
}

enum _ChapterTreeRowKind { volume, chapter, addChapter, addRootChapter }
