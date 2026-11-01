// 职责: 验证人物档案新增字段通过 NovelContentService 完整读写与校验。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/character_behavior_tag.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  late NovelContentDatabase database;
  late NovelContentService service;

  setUp(() {
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = NovelContentService(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates and updates the complete character writing model', () async {
    final firstAppearChapterId = await service.createChapter(
      siblingOrder: 0,
      title: '初见',
    );
    final id = await service.createCharacterProfile(
      name: '陈峰',
      aliases: const ['陈先生', '峰哥', '陈先生'],
      tags: const [' 云岚宗 ', '内门弟子', '云岚宗'],
      biography: '曾任松江府画师。',
      appearance: '身形修长，黑发束冠。',
      description: '左眉有一道浅疤，说话很慢。',
      personality: '谨慎、自尊心强，但会保护弱者。',
      behaviorTags: const [
        CharacterBehaviorTag(tag: '嘴硬护短', context: '亲近者受伤时先责备，随后主动补救。'),
      ],
      currentState: '右臂受伤，滞留松江府。',
      firstAppearChapterId: firstAppearChapterId,
    );

    var character = await service.getCharacterProfileById(id);
    expect(character, isNotNull);
    expect(character!.aliases, ['陈先生', '峰哥']);
    expect(character.tags, ['云岚宗', '内门弟子']);
    expect(character.description, '左眉有一道浅疤，说话很慢。');
    expect(character.appearance, '身形修长，黑发束冠。');
    expect(character.personality, '谨慎、自尊心强，但会保护弱者。');
    expect(character.behaviorTags, const [
      CharacterBehaviorTag(tag: '嘴硬护短', context: '亲近者受伤时先责备，随后主动补救。'),
    ]);
    expect(character.currentState, '右臂受伤，滞留松江府。');
    expect(character.firstAppearChapterId, firstAppearChapterId);

    await service.updateCharacterProfile(
      entryId: id,
      name: character.name,
      role: character.role,
      gender: character.gender,
      aliases: const ['陈先生'],
      biography: character.biography,
      appearance: '身形清瘦，改戴斗笠。',
      description: character.description,
      personality: '谨慎，但已经愿意承担风险。',
      behaviorTags: const [
        CharacterBehaviorTag(tag: '遇强则静', context: '对手明显更强时减少试探性玩笑，优先观察破绽。'),
      ],
      currentState: '伤势恢复，准备离开松江府。',
    );

    character = await service.getCharacterProfileById(id);
    expect(character!.aliases, ['陈先生']);
    expect(character.appearance, '身形清瘦，改戴斗笠。');
    expect(character.personality, '谨慎，但已经愿意承担风险。');
    expect(character.behaviorTags.single.tag, '遇强则静');
    expect(character.currentState, '伤势恢复，准备离开松江府。');

    await service.updateCharacterTags(
      entryId: id,
      tags: const [' 云岚宗 ', '宗门长老', '云岚宗'],
    );
    character = await service.getCharacterProfileById(id);
    expect(character!.tags, ['云岚宗', '宗门长老']);
  });

  test(
    'drops aliases equal to the character name instead of failing',
    () async {
      // AI 生成角色档案时经常把本名重复写进 aliases；整条 Create 不应因此失败。
      final id = await service.createCharacterProfile(
        name: '陈峰',
        aliases: const ['陈峰', '老陈', '陈峰'],
      );

      final character = await service.getCharacterProfileById(id);
      expect(character!.aliases, ['老陈']);
    },
  );

  test('rejects behavior tags without context', () async {
    await expectLater(
      service.createCharacterProfile(
        name: '陈峰',
        behaviorTags: const [CharacterBehaviorTag(tag: '嘴硬护短', context: '  ')],
      ),
      throwsArgumentError,
    );
  });

  test('first appearance only accepts an existing chapter or extra', () async {
    final volumeId = await service.createVolume(title: '第一卷');

    await expectLater(
      service.createCharacterProfile(
        name: '陈峰',
        firstAppearChapterId: 'missing-chapter',
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.createCharacterProfile(
        name: '陈峰',
        firstAppearChapterId: volumeId,
      ),
      throwsArgumentError,
    );
  });
}
