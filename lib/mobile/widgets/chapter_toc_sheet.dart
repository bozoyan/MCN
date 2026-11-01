// 职责: 移动端章节目录底部弹窗 — 分卷分组展示章节、切换当前章节、新建章节。
// 关联文件:
//   lib/mobile/pages/novel_editor_page.dart
//   lib/shared/models/chapter.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/chapter.dart';
import '../../shared/theme/theme.dart';

/// 打开章节目录底部弹窗。返回值无意义；切换/新建通过回调即时生效。
Future<void> showChapterTocSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required String? selectedChapterId,
  required ValueChanged<String> onSelect,
  required VoidCallback onCreateChapter,
}) {
  final colors = RevericTheme.colorsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.canvas,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _ChapterTocSheet(
      chapters: chapters,
      selectedChapterId: selectedChapterId,
      onSelect: onSelect,
      onCreateChapter: onCreateChapter,
    ),
  );
}

/// 把扁平的章节树（含卷与章）整理成「卷 → 章节」与根级散章的有序结构。
class _TocGroup {
  const _TocGroup({this.volume, required this.items});

  /// 卷节点；为 null 表示根级未分卷的散章分组。
  final Chapter? volume;
  final List<Chapter> items;
}

List<_TocGroup> _buildGroups(List<Chapter> chapters) {
  final volumes = chapters.where((c) => c.isVolume).toList()
    ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  final childrenByParent = <String, List<Chapter>>{};
  final rootChapters = <Chapter>[];
  for (final c in chapters) {
    if (c.isVolume) {
      continue;
    }
    final parentId = c.parentId;
    if (parentId == null) {
      rootChapters.add(c);
    } else {
      childrenByParent.putIfAbsent(parentId, () => []).add(c);
    }
  }
  for (final list in childrenByParent.values) {
    list.sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  }
  rootChapters.sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));

  final groups = <_TocGroup>[];
  if (rootChapters.isNotEmpty) {
    groups.add(_TocGroup(items: rootChapters));
  }
  for (final v in volumes) {
    groups.add(_TocGroup(volume: v, items: childrenByParent[v.id] ?? const []));
  }
  return groups;
}

class _ChapterTocSheet extends StatelessWidget {
  const _ChapterTocSheet({
    required this.chapters,
    required this.selectedChapterId,
    required this.onSelect,
    required this.onCreateChapter,
  });

  final List<Chapter> chapters;
  final String? selectedChapterId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreateChapter;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final groups = _buildGroups(chapters);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 抓手
            Padding(
              padding: const EdgeInsets.only(
                top: RevericSpacing.lg,
                bottom: RevericSpacing.sm,
              ),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题栏 + 新建章节
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x3l,
                RevericSpacing.xs,
                RevericSpacing.lg,
                RevericSpacing.lg,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.t(LocaleKeys.mobileEditorTocTitle),
                    style: typo.heading2.copyWith(color: colors.textPrimary),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      onCreateChapter();
                    },
                    borderRadius: BorderRadius.circular(RevericRadius.medium),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.xs,
                        vertical: RevericSpacing.xxs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RevericIcon(
                            RevericIcons.add,
                            size: 16,
                            color: colors.accentWarm,
                          ),
                          const SizedBox(width: RevericSpacing.xxs),
                          Text(
                            context.t(LocaleKeys.workspaceNewChapter),
                            style: typo.uiSmallSemibold.copyWith(
                              color: colors.accentWarm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.lg,
                  RevericSpacing.sm,
                  RevericSpacing.lg,
                  RevericSpacing.x5l,
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
                          style: typo.uiTinySemibold.copyWith(
                            color: colors.textSubtle,
                          ),
                        ),
                      ),
                    for (final chapter in group.items)
                      _ChapterRow(
                        chapter: chapter,
                        isActive: chapter.id == selectedChapterId,
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelect(chapter.id);
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
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
    // chapterTreeProvider 不加载 content，须用 wordCount 判断是否有正文。
    final isDraftEmpty = chapter.isDraft && chapter.wordCount == 0;
    final subtitle = isDraftEmpty
        ? context.t(LocaleKeys.mobileEditorDraftNotStarted)
        : context.t(
            LocaleKeys.mobileEditorWordCount,
            namedArgs: {'count': '${chapter.wordCount}'},
          );

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
                  color: isActive ? colors.accentWarm : colors.textSubtle,
                ),
              ),
            ),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSemibold.copyWith(
                      color: isDraftEmpty
                          ? colors.textSubtle
                          : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: typo.uiTiny.copyWith(color: colors.textSubtle),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(RevericRadius.pill),
                ),
                child: Text(
                  context.t(LocaleKeys.mobileEditorCurrent),
                  style: typo.uiTinySemibold.copyWith(color: colors.onAccent),
                ),
              )
            else if (chapter.isPublished)
              RevericIcon(
                RevericIcons.check_circle,
                size: 17,
                color: colors.success,
              ),
          ],
        ),
      ),
    );
  }
}
