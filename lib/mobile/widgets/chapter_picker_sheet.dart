// 职责: 移动端章节选择底部弹窗 — 分卷分组展示章节，供伏笔/角色等条目挑选关联章节（含「清除选择」）。
// 关联文件:
//   lib/mobile/widgets/chapter_toc_sheet.dart
//   lib/shared/models/chapter.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../shared/components/reveric_button.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/chapter.dart';
import '../../shared/theme/theme.dart';
import 'sheet.dart';

/// 打开章节选择底部弹窗。返回所选章节 id；返回 null 表示用户清除选择或取消。
Future<String?> showMobileChapterPickerSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required String? selectedChapterId,
  bool allowClear = true,
}) {
  return showMobileSheet<String>(
    context: context,
    builder: (_) => _ChapterPickerSheet(
      chapters: chapters,
      selectedChapterId: selectedChapterId,
      allowClear: allowClear,
    ),
  );
}

class _PickerGroup {
  const _PickerGroup({this.volume, required this.items});
  final Chapter? volume;
  final List<Chapter> items;
}

List<_PickerGroup> _buildGroups(List<Chapter> chapters) {
  final volumes = chapters.where((c) => c.isVolume).toList()
    ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  final byParent = <String, List<Chapter>>{};
  final root = <Chapter>[];
  for (final c in chapters) {
    if (c.isVolume) {
      continue;
    }
    final parentId = c.parentId;
    if (parentId == null) {
      root.add(c);
    } else {
      byParent.putIfAbsent(parentId, () => []).add(c);
    }
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  }
  root.sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));

  final groups = <_PickerGroup>[];
  if (root.isNotEmpty) {
    groups.add(_PickerGroup(items: root));
  }
  for (final v in volumes) {
    groups.add(_PickerGroup(volume: v, items: byParent[v.id] ?? const []));
  }
  return groups;
}

class _ChapterPickerSheet extends StatelessWidget {
  const _ChapterPickerSheet({
    required this.chapters,
    required this.selectedChapterId,
    required this.allowClear,
  });

  final List<Chapter> chapters;
  final String? selectedChapterId;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final groups = _buildGroups(chapters);

    return MobileSheetScaffold(
      header: MobileSheetHeader.closable(
        title: context.t(LocaleKeys.mobileEditorSelectChapter),
        onClose: () => Navigator.of(context).pop(),
        actions: [
          if (allowClear)
            RevericButton.text(
              label: context.t(LocaleKeys.commonClearSelection),
              onPressed: () => Navigator.of(context).pop(null),
            ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.lg,
          RevericSpacing.sm,
          RevericSpacing.lg,
          0,
        ),
        children: [
          for (final group in groups) ...[
            if (group.volume != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.md,
                  RevericSpacing.md,
                  RevericSpacing.md,
                  RevericSpacing.xs,
                ),
                child: Text(
                  group.volume!.displayTitle,
                  style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
                ),
              ),
            for (final chapter in group.items)
              _PickerRow(
                chapter: chapter,
                isActive: chapter.id == selectedChapterId,
                onTap: () => Navigator.of(context).pop(chapter.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.chapter,
    required this.isActive,
    required this.onTap,
  });

  final Chapter chapter;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: isActive ? colors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                chapter.chapterNum != null
                    ? context.t(
                        LocaleKeys.commonChapterNumber,
                        namedArgs: {'number': '${chapter.chapterNum}'},
                      )
                    : '·',
                textAlign: TextAlign.center,
                style: typo.uiSmallSemibold.copyWith(
                  color: isActive ? colors.accent : colors.textSubtle,
                ),
              ),
            ),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Text(
                chapter.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            if (isActive)
              RevericIcon(
                RevericIcons.check_circle,
                size: 18,
                color: colors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
