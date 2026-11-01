// 职责: 验证 Chronicler 按 M1 契约维护已发布章节的连续性事实且不污染人物稳定档案。
// 关联文件:
//   assets/prompts/agent/chronicler.md
//   assets/bundled_skills/story-continuity/references/novel.md
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/services/ai/tools_graph.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  test('keeps stable profile fields separate from current state', () async {
    // 字段契约已从 agent prompt 移到 skill reference：prompt 只负责把 agent
    // 导向 skill，稳定字段与动态状态的分界由 reference 承载。
    final prompt = await File(
      'assets/prompts/agent/chronicler.md',
    ).readAsString();
    expect(prompt, contains('故事连续性维护'));
    expect(prompt, contains('不凭记忆替代指南写入'));
    expect(prompt, isNot(contains('current_state**')));

    final reference = await File(
      'assets/bundled_skills/story-continuity/references/novel.md',
    ).readAsString();

    expect(reference, contains('description**: 稳定外在描述'));
    expect(reference, contains('current_state**: 本章结束时的动态快照'));
    expect(reference, contains('以本章证据更新 current_state'));
    expect(reference, contains('禁止单次表现改写'));
    expect(reference, contains('单次情境反应不足以建标签'));
    expect(reference, contains('合并保留既有有效项'));
    expect(reference, contains('/characters?search='));
    expect(reference, contains('/locations?search='));
    expect(reference, isNot(contains('?name=')));
    expect(reference, isNot(contains('?aliases=')));
    expect(reference, isNot(contains('在 summary 中写清区分点')));
  });

  test(
    'published chapter extraction updates continuity facts but preserves stable profile',
    () async {
      final database = NovelContentDatabase.forTest(NativeDatabase.memory());
      final appDatabase = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(database.close);
      addTearDown(appDatabase.close);

      final contentService = NovelContentService(database);
      final overlay = WorkingOverlayService(
        database,
        contentService,
        novelActionsService: NovelActionsService(appDatabase),
      );
      final toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
      )..registerAllTools();
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '雪夜结盟',
      );
      await contentService.updateChapterContent(
        chapterId: chapterId,
        title: '雪夜结盟',
        outline: '',
        content: '陈峰替林遥挡下追兵，两人在城门关闭前约定共同追查账册。',
      );
      final chenId = await contentService.createCharacterProfile(
        name: '陈峰',
        description: '左眉有浅疤，说话很慢。',
        personality: '谨慎、自尊心强。',
        behaviorTags: const [
          CharacterBehaviorTag(tag: '先观察', context: '进入陌生环境时'),
        ],
        currentState: '独自在松江府调查账册。',
      );
      final linId = await contentService.createCharacterProfile(name: '林遥');

      // 与真实发布流程一致：先发布，再由编年史者执行确定性的工具写回。
      await contentService.updateChapterStat(
        chapterId: chapterId,
        stat: chapterStatPublished,
      );
      final stateResult = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': '/characters/$chenId/current_state',
          'value': '与林遥结盟，已离开松江府并掌握账册线索。',
        },
      );
      final relationResult = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': '/relations',
          'fields': {
            'source_type': 'character',
            'source_id': chenId,
            'target_type': 'character',
            'target_id': linId,
            'relation_type': 'friend',
            'chapter_id': chapterId,
            'proof': '两人在本章约定共同追查账册。',
          },
        },
      );
      final outlineResult = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': '/chapters/$chapterId/outline',
          'value': '陈峰救下林遥并共同突围，两人因账册线索结盟；章末已离开松江府。',
        },
      );

      expect(stateResult['updated'], isTrue);
      expect(relationResult['created'], isTrue);
      expect(outlineResult['updated'], isTrue);
      final character = await contentService.getCharacterProfileById(chenId);
      expect(character!.currentState, '与林遥结盟，已离开松江府并掌握账册线索。');
      expect(character.description, '左眉有浅疤，说话很慢。');
      expect(character.personality, '谨慎、自尊心强。');
      expect(character.behaviorTags, const [
        CharacterBehaviorTag(tag: '先观察', context: '进入陌生环境时'),
      ]);
      final relations = await contentService.entityRelationsService
          .getRelationsForChapterEvidence(chapterId);
      expect(relations, hasLength(1));
      expect(relations.single.sourceId, chenId);
      expect(relations.single.targetId, linId);
      final chapter = await contentService.getChapterById(chapterId);
      expect(chapter!.outline, '陈峰救下林遥并共同突围，两人因账册线索结盟；章末已离开松江府。');

      final lockedContentResult = await toolManager.executeTool(
        name: 'Write',
        input: {'path': '/chapters/$chapterId/content', 'value': '不应覆盖已发布正文'},
      );
      expect(lockedContentResult['ok'], isFalse);
      expect(lockedContentResult['error_code'], 'locked');
      expect(
        (await contentService.getChapterById(chapterId))!.content,
        '陈峰替林遥挡下追兵，两人在城门关闭前约定共同追查账册。',
      );
    },
  );
}
