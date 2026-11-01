// 职责: 测试章节树挂载 — 孤儿章节按根级散章处理
// 关联文件:
//   lib/shared/utils/chapter_tree_layout.dart
//   lib/shared/models/chapter.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/utils/chapter_tree_layout.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);

  Chapter buildNode({
    required String id,
    required String type,
    String? parentId,
    int siblingOrder = 1,
    String? title,
  }) {
    return Chapter(
      id: id,
      type: type,
      parentId: parentId,
      siblingOrder: siblingOrder,
      title: title,
      createdAt: now,
      updatedAt: now,
      deletedAt: notDeletedSentinel,
    );
  }

  group('mountChaptersForTree', () {
    test('mounts numbered chapters under their volume', () {
      final mount = mountChaptersForTree([
        buildNode(
          id: 'vol_1',
          type: nodeTypeVolume,
          siblingOrder: 1,
          title: '第一卷',
        ),
        buildNode(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: 'vol_1',
          siblingOrder: 1,
          title: '第一章',
        ),
      ]);

      expect(mount.numberedChapterCount, 1);
      expect(mount.roots.single.id, 'vol_1');
      expect(mount.childrenByVolume['vol_1']!.single.id, 'ch_1');
    });

    test('treats orphan chapters with missing volume parent as root', () {
      final mount = mountChaptersForTree([
        buildNode(
          id: 'vol_1',
          type: nodeTypeVolume,
          siblingOrder: 1,
          title: '第一卷',
        ),
        buildNode(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: 'vol_1',
          siblingOrder: 1,
          title: '卷内章',
        ),
        buildNode(
          id: 'ch_orphan',
          type: nodeTypeChapter,
          parentId: 'missing_vol',
          siblingOrder: 2,
          title: '孤儿章',
        ),
      ]);

      expect(mount.numberedChapterCount, 2);
      expect(mount.roots.map((chapter) => chapter.id), ['vol_1', 'ch_orphan']);
      expect(mount.childrenByVolume['vol_1'], hasLength(1));
      expect(mount.childrenByVolume.containsKey('missing_vol'), isFalse);
    });

    test('treats orphan extra chapters with missing volume parent as root', () {
      final mount = mountChaptersForTree([
        buildNode(
          id: 'extra_1',
          type: nodeTypeExtra,
          parentId: 'missing_vol',
          siblingOrder: 1,
          title: '番外',
        ),
      ]);

      expect(mount.numberedChapterCount, 0);
      expect(mount.roots.single.id, 'extra_1');
      expect(mount.chapterIds, {'extra_1'});
    });
  });
}
