// 职责: 验证聊天作品身份统一取自完整作品，同时保留本轮章节和用户规则。
// 关联文件:
//   lib/shared/models/ai_chat_models.dart
//   test/helpers/novel_fixture.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/novel_type.dart';

import '../../helpers/novel_fixture.dart';

void main() {
  for (final kind in [contentKindNovel, contentKindScreenplay]) {
    test('uses the complete $kind work and preserves turn context', () {
      final work = buildTestNovel(
        id: 'current_work',
        title: 'Current title',
        type: kind == contentKindScreenplay
            ? novelTypeAdaptation
            : novelTypeOriginal,
        contentKind: kind,
        sourceNovelId: kind == contentKindScreenplay ? 'source_work' : null,
      );
      const input = AiSessionContext(
        workId: 'route_work',
        novelName: 'Route title',
        sourceNovelId: 'route_source',
        databasePath: '/test/content.sqlite',
        workspacePath: '/works/route_work',
        chapterId: 'selected_chapter',
        currentSeasonId: 'selected_season',
        currentEpisodeId: 'selected_episode',
        userRules: 'Keep the chosen style',
      );

      final context = input.withWork(work);

      expect(context.workId, work.id);
      expect(context.novelName, work.title);
      expect(context.contentKind, kind);
      expect(context.workType, work.type);
      expect(context.hasExplicitContentKind, isTrue);
      expect(context.sourceNovelId, work.sourceNovelId);
      expect(context.workspacePath, '/works/current_work');
      expect(context.databasePath, input.databasePath);
      expect(context.chapterId, input.chapterId);
      expect(context.currentSeasonId, input.currentSeasonId);
      expect(context.currentEpisodeId, input.currentEpisodeId);
      expect(context.userRules, input.userRules);
    });
  }
}
