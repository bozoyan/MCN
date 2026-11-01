// 职责: AI 工具枚举值验证与规范化 — 提供友好的错误提示和自动纠正常见格式错误（包括中文映射）
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/models/content_status.dart
//   lib/shared/models/outline_draft.dart
part of 'tools.dart';

/// 验证结果，包含是否有效、可能的更正值和错误信息
class _EnumValidationResult {
  const _EnumValidationResult({
    required this.isValid,
    this.correctedValue,
    this.errorMessage,
  });

  final bool isValid;
  final String? correctedValue;
  final String? errorMessage;

  factory _EnumValidationResult.valid() =>
      const _EnumValidationResult(isValid: true);

  factory _EnumValidationResult.corrected(String value) =>
      _EnumValidationResult(isValid: true, correctedValue: value);

  factory _EnumValidationResult.invalid(String message) =>
      _EnumValidationResult(isValid: false, errorMessage: message);
}

/// 中文映射表 - 用于自动纠正常见中文表述
class _ChineseEnumMappings {
  // Character role 中文映射
  static const Map<String, String> characterRoleZh = {
    '主角': 'protagonist',
    '主角角色': 'protagonist',
    // 模型常用英文别名。
    'main': 'protagonist',
    '反派': 'antagonist',
    '反派角色': 'antagonist',
    '配角': 'supporting',
    '配角角色': 'supporting',
    '次要角色': 'minor',
    '小角色': 'minor',
    '龙套': 'minor',
  };

  // Character gender 中文映射
  static const Map<String, String> characterGenderZh = {
    '男': 'male',
    '男性': 'male',
    '男生': 'male',
    '女': 'female',
    '女性': 'female',
    '女生': 'female',
    '非二元': 'non_binary',
    '非二进制': 'non_binary',
    '其他': 'other',
    '未知': 'unknown',
  };

  // Foreshadowing status 中文映射
  static const Map<String, String> foreshadowingStatusZh = {
    '待铺垫': 'pending',
    '已埋设': 'planted',
    '埋设': 'planted',
    '已铺垫': 'planted',
    '铺垫': 'planted',
    '已兑现': 'payoff',
    '兑现': 'payoff',
    '已回收': 'payoff',
    '回收': 'payoff',
    '已放弃': 'abandoned',
    '放弃': 'abandoned',
  };

  static const Map<String, String> foreshadowingStatusAliases = {
    ...foreshadowingStatusZh,
    'setup': 'planted',
    '待处理': 'pending',
    '待': 'pending',
    '未开始': 'pending',
    '已废弃': 'abandoned',
    '废弃': 'abandoned',
  };

  static const Map<String, String> outlineStatusAliases = {
    '进行中': 'in_progress',
    'active': 'in_progress',
    '活跃': 'in_progress',
    '活跃中': 'in_progress',
    '已完成': 'finished',
    '完成': 'finished',
    '完成状态': 'finished',
    '待处理': 'pending',
    '待': 'pending',
    '未开始': 'pending',
  };

  // Novel status 中文映射
  static const Map<String, String> novelStatusZh = {
    '连载': 'in_progress',
    '连载中': 'in_progress',
    '写作中': 'in_progress',
    '完结': 'finished',
    '已完结': 'finished',
    '完本': 'finished',
    '弃坑': 'abandoned',
    '太监': 'abandoned',
    '弃文': 'abandoned',
  };

  // Document create type 中文映射（lore/materials）
  static const Map<String, String> documentCreateTypeZh = {
    '文档': 'document',
    '文件': 'document',
    '文件夹': 'folder',
    '目录': 'folder',
    'directory': 'folder',
    'folder': 'folder',
    'document': 'document',
  };

  // Location type 中文映射
  static const Map<String, String> locationTypeZh = {
    '世界': 'world',
    '大陆': 'continent',
    '洲': 'continent',
    '国家': 'country',
    '地区': 'region',
    '区域': 'region',
    'area': 'region',
    '山': 'mountain',
    '山脉': 'mountain',
    '平原': 'plain',
    '森林': 'forest',
    '树林': 'forest',
    '河': 'river',
    '河流': 'river',
    '湖': 'lake',
    '湖泊': 'lake',
    '海': 'sea',
    '海域': 'sea',
    '岛': 'island',
    '岛屿': 'island',
    '城市': 'city',
    '城区': 'district',
    '区': 'district',
    '村': 'village',
    '村庄': 'village',
    '建筑': 'building',
    '大楼': 'building',
    '房间': 'room',
    '地': 'room',
    '地标': 'landmark',
    '景点': 'landmark',
    '自定义': 'custom',
    '自然': 'natural',
    '自然景观': 'natural',
  };

  // Relation type 中文映射
  static const Map<String, String> relationTypeZh = {
    // character → character
    '亲属': 'family',
    '家人': 'family',
    '家人关系': 'family',
    '父母': 'parent',
    '父亲': 'parent',
    '母亲': 'parent',
    '父': 'parent',
    '母': 'parent',
    '兄弟': 'sibling',
    '姐妹': 'sibling',
    '兄弟姐妹': 'sibling',
    '兄妹': 'sibling',
    '姐弟': 'sibling',
    '朋友': 'friend',
    '好友': 'friend',
    '死党': 'friend',
    '敌对': 'enemy',
    '敌人': 'enemy',
    '对手': 'enemy',
    '仇人': 'enemy',
    '恋人': 'lover',
    '情人': 'lover',
    '爱人': 'lover',
    '夫妻': 'lover',
    '情侣': 'lover',
    '师徒': 'master_disciple',
    '师父': 'master_disciple',
    '师傅': 'master_disciple',
    '徒弟': 'master_disciple',
    '师徒关系': 'master_disciple',
    '同事': 'colleague',
    '同僚': 'colleague',
    '下属': 'subordinate',
    '上下级': 'subordinate',
    '部下': 'subordinate',
    '手下': 'subordinate',
    '部属': 'subordinate',
    '合作': 'friend',
    '其他': 'friend',
    '另一身份': 'alter_ego',
    '另一个身份': 'alter_ego',
    '马甲': 'alter_ego',
    '化身': 'alter_ego',
    '人间体': 'alter_ego',
    '身份': 'alter_ego',
    '别名身份': 'alter_ego',
    // character → faction
    '成员': 'member',
    '会员': 'member',
    '首领': 'leader',
    '领导': 'leader',
    '领导人': 'leader',
    '老大': 'leader',
    '创始人': 'founder',
    '创立者': 'founder',
    '建立者': 'founder',
    '盟友': 'ally',
    '同盟': 'ally',
    '盟军': 'ally',
    // character → skill
    '已学会': 'learned',
    '学会': 'learned',
    '学习中': 'mastering',
    '学习': 'mastering',
    '已精通': 'mastered',
    '精通': 'mastered',
    '已掌握': 'mastered',
    '掌握': 'mastered',
    '创造者': 'creator',
    '发明者': 'creator',
    '创建者': 'creator',
    // character → item
    '持有者': 'owner',
    '拥有者': 'owner',
    '持有': 'owner',
    '拥有': 'owner',
    '使用者': 'user',
    '使用': 'user',
    // skill → skill
    '前置': 'prerequisite',
    '前置技能': 'prerequisite',
    '进化为': 'evolves_to',
    '进化': 'evolves_to',
    '分支': 'branch',
    '分支出': 'branch',
    // item → item
    '组成部分': 'part_of',
    '组成': 'part_of',
    '包含于': 'part_of',
    // creature → creature
    '猎物': 'prey',
    '捕食': 'prey',
    '天敌': 'predator',
    '天敌关系': 'predator',
  };

  // Entity type 中文映射
  static const Map<String, String> entityTypeZh = {
    '角色': 'character',
    '人物': 'character',
    '势力': 'faction',
    '公会': 'faction',
    '组织': 'faction',
    '帮派': 'faction',
    '技能': 'skill',
    '能力': 'skill',
    '物品': 'item',
    '装备': 'item',
    '道具': 'item',
    '神器': 'item',
    '地点': 'location',
    '位置': 'location',
    '场景': 'location',
    '章节': 'chapter',
    '伏笔': 'foreshadowing',
    '生物': 'creature',
    '动物': 'creature',
    '生物体': 'creature',
  };
}

/// 枚举验证与规范化工具类
class _EnumValidator {
  /// 验证并可能规范化枚举值
  ///
  /// 返回验证结果，包含是否有效、可能的更正值和错误信息
  static _EnumValidationResult validateAndNormalize({
    required String fieldName,
    required String value,
    required List<String> validValues,
    bool allowEmpty = true,
    Map<String, String>? chineseMapping,
  }) {
    // 空值处理
    if (value.isEmpty) {
      if (allowEmpty) {
        return _EnumValidationResult.valid();
      }
      return _EnumValidationResult.invalid(
        '$fieldName cannot be empty. Use one of: ${_formatEnumList(validValues)}.',
      );
    }

    // 完全匹配
    if (validValues.contains(value)) {
      return _EnumValidationResult.valid();
    }

    // 尝试中文/别名映射
    if (chineseMapping != null) {
      final corrected = _lookupAliasMapping(chineseMapping, value);
      if (corrected != null && validValues.contains(corrected)) {
        return _EnumValidationResult.corrected(corrected);
      }
    }

    // 尝试常见格式转换（驼峰→下划线、空格→下划线等）
    final normalized = _normalizeEnumFormat(value);
    if (validValues.contains(normalized)) {
      return _EnumValidationResult.corrected(normalized);
    }

    // 检查是否为拼写相近的值
    final suggestion = _findClosestMatch(value, validValues);
    if (suggestion != null) {
      return _EnumValidationResult.invalid(
        'Invalid $fieldName: "$value". Did you mean "$suggestion"? '
        'Valid values (snake_case): ${_formatEnumList(validValues)}.',
      );
    }

    return _EnumValidationResult.invalid(
      'Invalid $fieldName: "$value". '
      'Valid values (use exact snake_case, not Chinese): ${_formatEnumList(validValues)}.',
    );
  }

  /// 格式化枚举列表为可读字符串
  static String _formatEnumList(List<String> values) {
    return values.map((v) => '"$v"').join(', ');
  }

  static String? _lookupAliasMapping(
    Map<String, String> mapping,
    String value,
  ) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final direct = mapping[trimmed];
    if (direct != null) {
      return direct;
    }
    final lower = trimmed.toLowerCase();
    for (final entry in mapping.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  /// 规范化常见的枚举格式错误
  ///
  /// 将 titleCase、camelCase、带空格等形式转换为 snake_case
  static String _normalizeEnumFormat(String value) {
    String normalized = value.trim().toLowerCase();

    // 处理常见连词替换
    normalized = normalized
        .replaceAll('non-binary', 'non_binary')
        .replaceAll('non binary', 'non_binary')
        .replaceAll('master-disciple', 'master_disciple')
        .replaceAll('master disciple', 'master_disciple')
        .replaceAll('alter-ego', 'alter_ego')
        .replaceAll('alter ego', 'alter_ego')
        .replaceAll('in-progress', 'in_progress')
        .replaceAll('in progress', 'in_progress');

    // 将驼峰命名转换为下划线
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      if (char.toUpperCase() != char && i > 0) {
        final prev = normalized[i - 1];
        // 如果当前字符是大写且前一个字符不是下划线/连字符，添加下划线
        if (prev != '_' && prev != '-') {
          buffer.write('_');
        }
      }
      buffer.write(char.toLowerCase());
    }
    normalized = buffer.toString();

    // 移除多余的下划线和连字符
    normalized = normalized.replaceAll(RegExp(r'[-_\s]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_|_$'), '');

    return normalized;
  }

  /// 查找最接近的有效值（基于简单编辑距离启发式）
  static String? _findClosestMatch(String input, List<String> validValues) {
    if (validValues.isEmpty) return null;

    final inputLower = input.toLowerCase();
    String? bestMatch;
    double bestScore = 0;

    for (final valid in validValues) {
      final validLower = valid.toLowerCase();
      final score = _calculateSimilarity(inputLower, validLower);

      if (score > bestScore) {
        bestScore = score;
        bestMatch = valid;
      }
    }

    // 只有相似度足够高时才返回建议
    return bestScore > 0.5 ? bestMatch : null;
  }

  /// 计算两个字符串的相似度（简单的字符重叠启发式）
  static double _calculateSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    // 计算字符交集
    final aChars = a.split('');
    final bChars = b.split('');
    final intersection = aChars.where((c) => bChars.contains(c)).length;
    final union = (aChars.toSet()..addAll(bChars)).length;

    if (union == 0) return 0.0;

    final charSimilarity = intersection / union;

    // 完全匹配额外加分
    final exactMatch = a == b ? 0.3 : 0.0;

    // 长度相近加分
    final lengthDiff = (a.length - b.length).abs();
    final lengthScore = 1.0 / (1.0 + lengthDiff * 0.2);

    return (charSimilarity * 0.5 + lengthScore * 0.2 + exactMatch).clamp(
      0.0,
      1.0,
    );
  }
}

/// 增强的枚举验证函数

bool _isEnumResolverError(String? resolved) {
  return resolved != null && resolved.startsWith('Invalid');
}

String _finalizeEnumValue(String raw, String? resolved) {
  return resolved ?? raw;
}

String? _resolveEnumValue({
  required String fieldName,
  required String value,
  required List<String> validValues,
  Map<String, String>? chineseMapping,
  bool allowEmpty = true,
}) {
  final result = _EnumValidator.validateAndNormalize(
    fieldName: fieldName,
    value: value,
    validValues: validValues,
    chineseMapping: chineseMapping,
    allowEmpty: allowEmpty,
  );
  if (!result.isValid) {
    return result.errorMessage;
  }
  return result.correctedValue;
}

String? _resolveGraphSearchRelationType(String relationType) {
  if (relationType.isEmpty) {
    return null;
  }
  return _resolveEnumValue(
    fieldName: 'relation type',
    value: relationType,
    validValues: AiToolManager._allValidRelationTypes,
    chineseMapping: _ChineseEnumMappings.relationTypeZh,
    allowEmpty: false,
  );
}

String? _resolveEntityType(String entityType) {
  if (entityType.isEmpty) {
    return null;
  }
  return _resolveEnumValue(
    fieldName: 'entity type',
    value: entityType,
    validValues: entityTypes,
    chineseMapping: _ChineseEnumMappings.entityTypeZh,
  );
}

String? _validateRelationTypePair(
  String sourceType,
  String targetType,
  String relationType,
) {
  final validTypes = AiToolManager._validRelationTypesFor(
    sourceType,
    targetType,
  );
  if (validTypes.contains(relationType)) {
    return null;
  }
  if (validTypes.isEmpty) {
    return 'No supported relation types for $sourceType → $targetType';
  }
  final suggestion = _EnumValidator._findClosestMatch(relationType, validTypes);
  if (suggestion != null) {
    return 'Invalid relation type: "$relationType". Did you mean "$suggestion"? '
        'Valid values (snake_case): ${_EnumValidator._formatEnumList(validTypes)}.';
  }
  return 'Invalid relation type: "$relationType". '
      'Valid values (use exact snake_case, not Chinese): ${_EnumValidator._formatEnumList(validTypes)}.';
}
