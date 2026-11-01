// 职责: 章节树挂载 — 将扁平章节列表分组为根节点与各卷子节点，孤儿章节按根级散章处理
// 关联文件:
//   lib/shared/models/chapter.dart
//   lib/desktop/widgets/sidebar/chapter_tree.dart
//   lib/mobile/widgets/chapters_panel.dart
//   lib/desktop/widgets/workspace/chapter_list_dropdown.dart

import '../models/chapter.dart';

/// 章节树挂载结果：根节点（卷 + 根级散章）与各卷下子章节。
class ChapterTreeMount {
  const ChapterTreeMount({
    required this.roots,
    required this.childrenByVolume,
    required this.chapterIds,
    required this.numberedChapterCount,
    required this.hasVolume,
  });

  final List<Chapter> roots;
  final Map<String, List<Chapter>> childrenByVolume;
  final Set<String> chapterIds;
  final int numberedChapterCount;
  final bool hasVolume;
}

int compareChapterSiblingOrder(Chapter a, Chapter b) {
  return a.siblingOrder.compareTo(b.siblingOrder);
}

/// 将 [parentId] 无效（缺失或非卷节点）的章节当作根级散章挂载。
ChapterTreeMount mountChaptersForTree(List<Chapter> chapters) {
  final volumeIds = <String>{
    for (final chapter in chapters)
      if (chapter.isVolume) chapter.id,
  };
  final roots = <Chapter>[];
  final childrenByVolume = <String, List<Chapter>>{};
  final chapterIds = <String>{};
  var numberedChapterCount = 0;

  for (final chapter in chapters) {
    if (chapter.isNumberedChapter) {
      numberedChapterCount += 1;
    }
    if (chapter.isChapter) {
      chapterIds.add(chapter.id);
    }

    final parentId = chapter.parentId;
    if (parentId == null) {
      roots.add(chapter);
      continue;
    }
    if (!chapter.isChapter) {
      continue;
    }
    if (volumeIds.contains(parentId)) {
      (childrenByVolume[parentId] ??= <Chapter>[]).add(chapter);
    } else {
      roots.add(chapter);
    }
  }

  roots.sort(compareChapterSiblingOrder);
  for (final children in childrenByVolume.values) {
    children.sort(compareChapterSiblingOrder);
  }

  return ChapterTreeMount(
    roots: roots,
    childrenByVolume: childrenByVolume,
    chapterIds: chapterIds,
    numberedChapterCount: numberedChapterCount,
    hasVolume: volumeIds.isNotEmpty,
  );
}
