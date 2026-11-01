// 职责: 章节列表搜索选择器 — 统一普通章节选项、显示文案与无效选中值处理。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/chapter.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/chapter_tree_layout.dart';
import '../../../shared/components/reveric_dialog.dart';

const _noneChapterValue = '';
const _chapterOptionIconSize = 16.0;
const _chapterSearchDialogWidth = 420.0;

/// 选项列表高度上限；列表短于此值时弹窗跟着收缩，不留大片空白。
const _chapterSearchListMaxHeight = 320.0;

class ChapterListDropdown extends StatelessWidget {
  const ChapterListDropdown({
    super.key,
    required this.selectedChapterId,
    required this.chapters,
    this.onChanged,
    this.onNavigate,
    this.contentPadding,
  });

  final String? selectedChapterId;
  final List<Chapter> chapters;
  final ValueChanged<String?>? onChanged;
  final ValueChanged<String>? onNavigate;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final options = _ChapterDropdownTree.from(chapters).options;
    final selectableChapterIds = {
      for (final option in options)
        if (option.kind == _ChapterDropdownOptionKind.chapter)
          option.chapter!.id,
    };
    final selectedId = _normalizeSelectedId(selectedChapterId);
    final effectiveValue = selectableChapterIds.contains(selectedId)
        ? selectedId
        : _noneChapterValue;
    final selectedChapter = options
        .where(
          (option) =>
              option.kind == _ChapterDropdownOptionKind.chapter &&
              option.chapter!.id == effectiveValue,
        )
        .firstOrNull
        ?.chapter;

    final dropdown = _ChapterSearchDropdown(
      effectiveValue: effectiveValue,
      options: options,
      selectableChapterIds: selectableChapterIds,
      onChanged: onChanged,
      contentPadding: contentPadding,
    );

    if (onNavigate == null || selectedChapter == null) {
      return dropdown;
    }

    return Row(
      children: [
        Expanded(child: dropdown),
        const SizedBox(width: RevericSpacing.xxs),
        Tooltip(
          message: context.t(LocaleKeys.workspaceNavigateToChapter),
          child: SizedBox(
            width: RevericSizes.iconButtonSize,
            height: RevericSizes.iconButtonSize,
            child: IconButton(
              onPressed: () => onNavigate!(selectedChapter.id),
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: RevericIcon(
                RevericIcons.arrow_forward_rounded,
                size: 16,
                color: colors.textSubtle,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                hoverColor: colors.accent.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterSearchDropdown extends StatelessWidget {
  const _ChapterSearchDropdown({
    required this.effectiveValue,
    required this.options,
    required this.selectableChapterIds,
    required this.onChanged,
    this.contentPadding,
  });

  final String? effectiveValue;
  final List<_ChapterDropdownOption> options;
  final Set<String> selectableChapterIds;
  final ValueChanged<String?>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final selectedOption = options.where((option) {
      return option.value == effectiveValue;
    }).firstOrNull;
    final selectedLabel = selectedOption == null
        ? context.t(LocaleKeys.commonNone)
        : _chapterOptionLabel(context, selectedOption);
    final selectedColor =
        selectedOption?.kind == _ChapterDropdownOptionKind.chapter
        ? colors.textPrimary
        : colors.textMuted;

    return InkWell(
      onTap: onChanged == null
          ? null
          : () async {
              final chapterId = await showRevericDialog<String?>(
                context: context,
                builder: (context) => _ChapterSearchDialog(
                  options: options,
                  selectedValue: effectiveValue,
                ),
              );
              if (!context.mounted) {
                return;
              }
              if (chapterId == null || chapterId == _noneChapterValue) {
                onChanged!(null);
                return;
              }
              if (selectableChapterIds.contains(chapterId)) {
                onChanged!(chapterId);
              }
            },
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            borderSide: BorderSide(color: colors.borderInput),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            borderSide: BorderSide(color: colors.borderInput),
          ),
          contentPadding: contentPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel,
                overflow: TextOverflow.ellipsis,
                style: typo.ui.copyWith(color: selectedColor),
              ),
            ),
            RevericIcon(
              RevericIcons.search,
              size: 16,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterSearchDialog extends HookWidget {
  const _ChapterSearchDialog({
    required this.options,
    required this.selectedValue,
  });

  final List<_ChapterDropdownOption> options;
  final String? selectedValue;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();
    final visible = _filteredOptions(context, options, search.query);
    final hasChapters = options.any(
      (option) => option.kind == _ChapterDropdownOptionKind.chapter,
    );
    // 一章都没有时「无」是唯一选项，列出来只是噪音，直接走空态。
    final isEmpty = !hasChapters || visible.isEmpty;

    return RevericDialog.panel(
      title: Text(context.t(LocaleKeys.workspaceSelectChapter)),
      content: SizedBox(
        width: _chapterSearchDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RevericSearchField(
              controller: search.controller,
              hint: context.t(LocaleKeys.workspaceSearchChapters),
              autofocus: true,
            ),
            const SizedBox(height: RevericSpacing.sm),
            if (isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RevericSpacing.x5l,
                ),
                child: Text(
                  context.t(
                    hasChapters
                        ? LocaleKeys.commonNoResults
                        : LocaleKeys.workspaceChapterPickerEmpty,
                  ),
                  textAlign: TextAlign.center,
                  style: typo.ui.copyWith(color: colors.textMuted),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _chapterSearchListMaxHeight,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final option = visible[index];
                    final isVolume =
                        option.kind == _ChapterDropdownOptionKind.volume;
                    return InkWell(
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                      hoverColor: colors.accent.withValues(alpha: 0.06),
                      onTap: isVolume
                          ? null
                          : () => Navigator.of(context).pop(option.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.sm,
                          vertical: RevericSpacing.sm,
                        ),
                        child: _buildChapterDropdownOptionRow(
                          context,
                          option: option,
                          colors: colors,
                          typo: typo,
                          isSelected:
                              !isVolume && option.value == selectedValue,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),

      width: _chapterSearchDialogWidth + RevericSpacing.x4l * 2,
    );
  }
}

Widget _buildChapterDropdownOptionRow(
  BuildContext context, {
  required _ChapterDropdownOption option,
  required RevericColors colors,
  required RevericTypography typo,
  bool isSelected = false,
}) {
  final selectedMark = !isSelected
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(left: RevericSpacing.sm),
          child: RevericIcon(
            RevericIcons.check,
            size: _chapterOptionIconSize,
            color: colors.accent,
          ),
        );

  return Padding(
    padding: EdgeInsets.only(left: option.depth * RevericSpacing.x2l),
    child: switch (option.kind) {
      _ChapterDropdownOptionKind.none => Row(
        children: [
          const SizedBox(width: _chapterOptionIconSize),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.commonNone),
              overflow: TextOverflow.ellipsis,
              style: typo.ui.copyWith(color: colors.textMuted),
            ),
          ),
          selectedMark,
        ],
      ),
      _ChapterDropdownOptionKind.volume => Row(
        children: [
          RevericIcon(
            RevericIcons.menu_book_outlined,
            size: _chapterOptionIconSize,
            color: colors.textMuted,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              option.chapter!.displayTitle,
              overflow: TextOverflow.ellipsis,
              style: typo.uiSemibold.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
      _ChapterDropdownOptionKind.chapter => Row(
        children: [
          RevericIcon(
            RevericIcons.text_snippet_outlined,
            size: _chapterOptionIconSize,
            color: isSelected ? colors.accent : colors.textSubtle,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              formatChapterListLabel(context, option.chapter!),
              overflow: TextOverflow.ellipsis,
              style: typo.ui.copyWith(
                color: isSelected ? colors.accent : colors.textPrimary,
              ),
            ),
          ),
          selectedMark,
        ],
      ),
    },
  );
}

List<_ChapterDropdownOption> _filteredOptions(
  BuildContext context,
  List<_ChapterDropdownOption> options,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return options;
  }
  final matched = <_ChapterDropdownOption>[];
  final matchedVolumeIds = <String>{};
  for (final option in options) {
    if (option.kind == _ChapterDropdownOptionKind.none) {
      continue;
    }
    final label = _chapterOptionLabel(context, option).toLowerCase();
    if (label.contains(normalizedQuery)) {
      matched.add(option);
      final parentId = option.chapter?.parentId;
      if (parentId != null) {
        matchedVolumeIds.add(parentId);
      }
    }
  }
  return [
    for (final option in options)
      if (matched.contains(option) ||
          option.chapter != null &&
              matchedVolumeIds.contains(option.chapter!.id))
        option,
  ];
}

String _chapterOptionLabel(
  BuildContext context,
  _ChapterDropdownOption option,
) {
  return switch (option.kind) {
    _ChapterDropdownOptionKind.none => context.t(LocaleKeys.commonNone),
    _ChapterDropdownOptionKind.volume => option.chapter!.displayTitle,
    _ChapterDropdownOptionKind.chapter => formatChapterListLabel(
      context,
      option.chapter!,
    ),
  };
}

final class _ChapterDropdownTree {
  const _ChapterDropdownTree({required this.options});

  final List<_ChapterDropdownOption> options;

  factory _ChapterDropdownTree.from(List<Chapter> chapters) {
    final mount = mountChaptersForTree(chapters);

    final options = <_ChapterDropdownOption>[
      const _ChapterDropdownOption.none(),
    ];
    if (!mount.hasVolume) {
      for (final root in mount.roots) {
        if (root.isNumberedChapter) {
          options.add(_ChapterDropdownOption.chapter(root, depth: 0));
        }
      }
      return _ChapterDropdownTree(options: options);
    }

    for (final root in mount.roots) {
      if (root.isVolume) {
        options.add(_ChapterDropdownOption.volume(root));
        final children = mount.childrenByVolume[root.id] ?? const <Chapter>[];
        for (final child in children) {
          options.add(_ChapterDropdownOption.chapter(child, depth: 1));
        }
        continue;
      }
      if (root.isNumberedChapter) {
        options.add(_ChapterDropdownOption.chapter(root, depth: 0));
      }
    }

    return _ChapterDropdownTree(options: options);
  }
}

final class _ChapterDropdownOption {
  const _ChapterDropdownOption._({
    required this.kind,
    required this.depth,
    this.chapter,
  });

  const _ChapterDropdownOption.none()
    : this._(kind: _ChapterDropdownOptionKind.none, depth: 0);

  const _ChapterDropdownOption.volume(Chapter chapter)
    : this._(
        kind: _ChapterDropdownOptionKind.volume,
        depth: 0,
        chapter: chapter,
      );

  const _ChapterDropdownOption.chapter(Chapter chapter, {required int depth})
    : this._(
        kind: _ChapterDropdownOptionKind.chapter,
        depth: depth,
        chapter: chapter,
      );

  final _ChapterDropdownOptionKind kind;
  final int depth;
  final Chapter? chapter;

  String get value => switch (kind) {
    _ChapterDropdownOptionKind.none => _noneChapterValue,
    _ChapterDropdownOptionKind.volume => chapter!.id,
    _ChapterDropdownOptionKind.chapter => chapter!.id,
  };
}

enum _ChapterDropdownOptionKind { none, volume, chapter }

String formatChapterListLabel(BuildContext context, Chapter chapter) {
  final chapterNumber = chapter.parentId == null
      ? chapter.chapterNum
      : chapter.volumeChapterNum ?? chapter.chapterNum;
  final numberLabel = context.t(
    LocaleKeys.commonChapterNumber,
    namedArgs: {'number': '${chapterNumber ?? "?"}'},
  );
  final title = chapter.title?.trim();
  if (title == null || title.isEmpty) {
    return numberLabel;
  }
  return '$numberLabel $title';
}

String? _normalizeSelectedId(String? selectedChapterId) {
  if (selectedChapterId == null || selectedChapterId.isEmpty) {
    return null;
  }
  return selectedChapterId;
}
