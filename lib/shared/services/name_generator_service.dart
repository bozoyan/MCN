// 职责: 起名助手服务 — 按实体类型提供随机/ AI 起名能力
// 关联文件:
//   lib/shared/services/ai/chat.dart
//   lib/shared/widgets/name_assistant_button.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/ai-calling.md
import 'dart:math';

import '../database/app_database.dart';
import '../models/ai_chat_models.dart';
import 'ai/chat.dart';

enum NameType { character, skill, item, creature, location }

class NameGeneratorService {
  NameGeneratorService._();

  static const aiNameBatchSize = 10;

  /// 起名是一次性短补全。走 [AiClient.chatCompletionDetached]，避免和对话共用
  /// ProviderClient 时 cancel 把正在写的聊天掐掉。
  static const nameGenerationTimeout = Duration(seconds: 20);

  static final _random = Random();

  // ---------------------------------------------------------------------------
  // Random name pools
  // ---------------------------------------------------------------------------

  static const _surnames = <String>[
    '张',
    '李',
    '王',
    '赵',
    '林',
    '萧',
    '叶',
    '苏',
    '顾',
    '沈',
    '江',
    '陆',
    '谢',
    '唐',
    '韩',
    '秦',
    '柳',
    '白',
    '许',
    '宋',
    '曹',
    '周',
    '吴',
    '朱',
    '陈',
    '杨',
    '刘',
    '黄',
    '孟',
    '石',
  ];

  static const _compoundSurnames = <String>[
    '慕容',
    '上官',
    '东方',
    '司马',
    '欧阳',
    '夏侯',
    '诸葛',
    '端木',
    '百里',
    '独孤',
  ];

  static const _givenNameFirst = <String>[
    '子',
    '小',
    '晓',
    '天',
    '云',
    '寒',
    '夜',
    '墨',
    '清',
    '明',
    '若',
    '亦',
    '如',
    '以',
    '紫',
    '白',
    '飞',
    '凌',
    '依',
    '映',
    '婉',
    '凝',
    '微',
    '雪',
    '青',
    '碧',
    '玄',
    '灵',
    '玉',
    '月',
  ];

  static const _givenNameSecond = <String>[
    '墨',
    '寒',
    '风',
    '云',
    '尘',
    '雪',
    '月',
    '影',
    '烟',
    '霜',
    '辰',
    '轩',
    '瑶',
    '薇',
    '萱',
    '婷',
    '涵',
    '琳',
    '琪',
    '珊',
    '仪',
    '兰',
    '蝶',
    '蓉',
    '剑',
    '歌',
    '琴',
    '棋',
    '帆',
    '遥',
  ];

  static const _skillPrefix = <String>[
    '九天',
    '万古',
    '混沌',
    '太虚',
    '无极',
    '乾坤',
    '星辰',
    '落日',
    '断岳',
    '覆海',
    '焚天',
    '寂灭',
    '长生',
    '不灭',
    '轮回',
    '涅槃',
    '天罡',
    '地煞',
    '紫霄',
    '碧落',
  ];

  static const _skillSuffix = <String>[
    '剑诀',
    '掌法',
    '拳经',
    '指法',
    '腿功',
    '刀法',
    '真解',
    '宝典',
    '神功',
    '秘典',
    '玄经',
    '神诀',
    '天功',
    '印法',
    '阵图',
    '遁术',
  ];

  static const _itemPrefix = <String>[
    '玄铁',
    '紫金',
    '寒玉',
    '星辰',
    '龙鳞',
    '凤羽',
    '天外',
    '万年',
    '九幽',
    '赤焰',
    '冰魄',
    '雷霆',
    '陨星',
    '蛟鳞',
    '麒麟',
    '白虎',
  ];

  static const _itemSuffix = <String>[
    '剑',
    '刀',
    '鼎',
    '镜',
    '珠',
    '环',
    '杖',
    '印',
    '幡',
    '琴',
    '笛',
    '伞',
    '钟',
    '塔',
    '壶',
    '炉',
    '牌',
    '符',
    '尺',
    '梭',
  ];

  static const _creaturePrefix = <String>[
    '烈焰',
    '冰霜',
    '雷霆',
    '暗影',
    '深渊',
    '幽冥',
    '炽焰',
    '极寒',
    '紫电',
    '玄冰',
    '赤血',
    '金翅',
    '九头',
    '三眼',
    '双翼',
    '独角',
  ];

  static const _creatureSuffix = <String>[
    '狼',
    '虎',
    '龙',
    '蛇',
    '鹰',
    '兽',
    '魔',
    '灵',
    '蟒',
    '豹',
    '狮',
    '雕',
    '鹏',
    '鳄',
    '蛟',
    '龟',
    '雀',
    '狐',
  ];

  static const _locationPrefix = <String>[
    '落霞',
    '青云',
    '紫霄',
    '碧波',
    '星辰',
    '皓月',
    '苍梧',
    '玄冥',
    '赤焰',
    '白鹭',
    '金乌',
    '玉龙',
    '凌霄',
    '飞云',
    '流萤',
    '听雨',
  ];

  static const _locationSuffix = <String>[
    '山',
    '谷',
    '城',
    '湖',
    '阁',
    '殿',
    '峰',
    '渊',
    '关',
    '岭',
    '川',
    '泽',
    '岛',
    '崖',
    '亭',
    '台',
    '洞',
    '宫',
    '寨',
    '洲',
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static String randomName(NameType type) {
    switch (type) {
      case NameType.character:
        final surname = _random.nextDouble() < 0.85
            ? _surnames[_random.nextInt(_surnames.length)]
            : _compoundSurnames[_random.nextInt(_compoundSurnames.length)];
        final first = _givenNameFirst[_random.nextInt(_givenNameFirst.length)];
        final second =
            _givenNameSecond[_random.nextInt(_givenNameSecond.length)];
        return '$surname$first$second';

      case NameType.skill:
        final prefix = _skillPrefix[_random.nextInt(_skillPrefix.length)];
        final suffix = _skillSuffix[_random.nextInt(_skillSuffix.length)];
        return '$prefix$suffix';

      case NameType.item:
        final prefix = _itemPrefix[_random.nextInt(_itemPrefix.length)];
        final suffix = _itemSuffix[_random.nextInt(_itemSuffix.length)];
        return '$prefix$suffix';

      case NameType.creature:
        final prefix = _creaturePrefix[_random.nextInt(_creaturePrefix.length)];
        final suffix = _creatureSuffix[_random.nextInt(_creatureSuffix.length)];
        return '$prefix$suffix';

      case NameType.location:
        final prefix = _locationPrefix[_random.nextInt(_locationPrefix.length)];
        final suffix = _locationSuffix[_random.nextInt(_locationSuffix.length)];
        return '$prefix$suffix';
    }
  }

  static List<String> randomNames(
    NameType type, {
    int count = aiNameBatchSize,
  }) {
    final names = <String>[];
    final seen = <String>{};
    var attempts = 0;
    while (names.length < count && attempts < count * 8) {
      attempts++;
      final name = randomName(type);
      if (seen.add(name)) {
        names.add(name);
      }
    }
    while (names.length < count) {
      names.add(randomName(type));
    }
    return names;
  }

  // ---------------------------------------------------------------------------
  // AI name generation
  // ---------------------------------------------------------------------------

  static Future<List<String>> generateAINames({
    required NameType type,
    required AiClient aiClient,
    int count = aiNameBatchSize,
    String? context,
    Novel? novel,
    String? entityDescription,
    Duration timeout = nameGenerationTimeout,
  }) async {
    if (!aiClient.isInitialized) {
      throw StateError('Name generation requires an initialized AI client.');
    }

    final systemPrompt = _buildSystemPrompt(type);
    final userPrompt = _buildUserPrompt(
      type,
      count,
      context,
      novel: novel,
      entityDescription: entityDescription,
    );

    final response = await aiClient.chatCompletionDetached([
      AiMessage.system(id: 'name_gen_sys', content: systemPrompt),
      AiMessage.user(id: 'name_gen_usr', content: userPrompt),
    ], timeout: timeout);

    final names = _parseNames(response, count);
    return names.isNotEmpty ? names : [randomName(type)];
  }

  static String _buildSystemPrompt(NameType type) {
    final typeDesc = switch (type) {
      NameType.character => '小说角色姓名',
      NameType.skill => '武技/法术/功法名称',
      NameType.item => '武器/法宝/道具名称',
      NameType.creature => '妖兽/魔物/灵兽名称',
      NameType.location => '地点/城池/地域名称',
    };
    return '你是一个专业的网络小说起名助手。请根据要求生成$typeDesc。\n'
        '只输出最终结果：名字列表，每行一个，不要序号，不要额外说明，不要展示分析过程。';
  }

  static String _buildUserPrompt(
    NameType type,
    int count,
    String? context, {
    Novel? novel,
    String? entityDescription,
  }) {
    final buf = StringBuffer();
    final novelInfo = _buildNovelInfo(novel);
    if (novelInfo.isNotEmpty) {
      buf.writeln('小说信息：');
      buf.write(novelInfo);
      buf.writeln();
      buf.writeln();
    }
    final trimmedEntityDescription = entityDescription?.trim();
    if (trimmedEntityDescription != null &&
        trimmedEntityDescription.isNotEmpty) {
      buf.writeln('当前实体描述：');
      buf.write(trimmedEntityDescription);
      buf.writeln();
      buf.writeln();
    }
    buf.write('请生成 $count 个');
    buf.write(switch (type) {
      NameType.character => '小说角色姓名',
      NameType.skill => '技能、法术、功法或能力名称',
      NameType.item => '物品、武器、道具或装备名称',
      NameType.creature => '生物、怪物、族群或灵兽名称',
      NameType.location => '地点、建筑、区域或地标名称',
    });
    buf.write('。名称需要契合上方小说信息和当前实体描述的题材、语气与世界观。');
    if (context != null && context.isNotEmpty) {
      buf.write('\n\n背景设定：$context');
    }
    buf.write('\n\n只输出最终名字列表，必须恰好 $count 个，每行一个名字，不要序号，不要解释。');
    return buf.toString();
  }

  static String _buildNovelInfo(Novel? novel) {
    if (novel == null) {
      return '';
    }
    final lines = <String>[];
    final title = novel.title.trim();
    if (title.isNotEmpty) {
      lines.add('小说名：$title');
    }
    final category = novel.category.trim();
    if (category.isNotEmpty) {
      lines.add('分类：$category');
    }
    final tags = novel.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (tags.isNotEmpty) {
      lines.add('Tags：${tags.join('、')}');
    }
    return lines.join('\n');
  }

  static List<String> _parseNames(String response, int expectedCount) {
    final names = <String>[];
    final seen = <String>{};
    final parts = response.split(RegExp(r'[\n\r,，;；]+'));
    for (final part in parts) {
      final name = part
          .trim()
          .replaceFirst(
            RegExp(r'^\s*(?:[-*]\s*)?(?:\d+|[一二三四五六七八九十]+)[\.\)、:：\s]+'),
            '',
          )
          .replaceAll(RegExp("^[「『\\\"'`]+|[」』\\\"'`]+\$"), '')
          .trim();
      if (name.isEmpty || !seen.add(name)) {
        continue;
      }
      names.add(name);
      if (names.length >= expectedCount) {
        break;
      }
    }
    return names;
  }
}
