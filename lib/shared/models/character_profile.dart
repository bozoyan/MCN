// 职责: CharacterProfile 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../../third/form/flutter_hook_form.dart';
import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';

export 'character_behavior_tag.dart' show CharacterBehaviorTag;

export '../database/novel_content_database.dart'
    show CharacterProfile, CharacterProfiles, CharacterProfilesCompanion;

/// 别名、称号与管理标签的单条最大字符数。
///
/// 比小说标签的 4 字更宽，容纳「云岚宗大长老」这类称号。
const int characterTagMaxLength = 12;

enum CharacterProfileEditFields<T> implements FieldSchema {
  name<String>(validators: [RequiredValidator<String>()]),
  role<String>(
    validators: [RequiredValidator<String>()],
    initialValue: 'supporting',
  ),
  gender<String>(initialValue: 'unknown'),
  aliases<List<String>>(initialValue: <String>[]),
  tags<List<String>>(initialValue: <String>[]),
  identity<String>(initialValue: ''),
  age<String>(initialValue: '未知'),
  motivation<String>(initialValue: ''),
  arc<String>(initialValue: ''),
  appearance<String>(initialValue: ''),
  description<String>(initialValue: ''),
  biography<String>(initialValue: ''),
  personality<String>(initialValue: ''),
  behaviorTags<List<CharacterBehaviorTag>>(
    initialValue: <CharacterBehaviorTag>[],
  ),
  currentState<String>(initialValue: ''),
  firstAppearChapterId<String?>(),
  avatar<String>(initialValue: ''),
  photos<List<SubjectPhoto>>(initialValue: <SubjectPhoto>[]);

  const CharacterProfileEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension CharacterProfileX on CharacterProfile {
  String get normalizedRole =>
      characterRoles.contains(role) ? role : characterRoleSupporting;

  String get normalizedGender =>
      characterGenders.contains(gender) ? gender : characterGenderUnknown;

  bool get hasBiography => biography.trim().isNotEmpty;

  bool get hasDescription => description.trim().isNotEmpty;

  bool get hasAppearance => appearance.trim().isNotEmpty;

  bool get hasCurrentState => currentState.trim().isNotEmpty;

  bool get isEmpty =>
      name.trim().isEmpty &&
      !hasBiography &&
      !hasAppearance &&
      !hasDescription &&
      !hasCurrentState;

  bool get isProtagonist => normalizedRole == characterRoleProtagonist;

  bool get isAntagonist => normalizedRole == characterRoleAntagonist;

  bool get isSupporting => normalizedRole == characterRoleSupporting;

  bool get isMinor => normalizedRole == characterRoleMinor;

  String get biographyPreview => _preview(biography);

  String get descriptionPreview => _preview(description);

  String get appearancePreview => _preview(appearance);

  String get currentStatePreview => _preview(currentState);

  /// 供角色扮演、小剧场等即时生成场景使用的分层人物上下文。
  String get promptPersonaContext {
    final sections = <String>[
      if (motivation.trim().isNotEmpty) '核心动机：${motivation.trim()}',
      if (arc.trim().isNotEmpty) '人物弧光：${arc.trim()}',
      if (appearance.trim().isNotEmpty) '外观：${appearance.trim()}',
      if (description.trim().isNotEmpty) '外在描述：${description.trim()}',
      if (personality.trim().isNotEmpty) '内在性格：${personality.trim()}',
      if (behaviorTags.isNotEmpty)
        '条件化行为：${behaviorTags.map((item) => '情境「${item.context}」：${item.tag}').join('；')}',
      if (currentState.trim().isNotEmpty) '当前状态：${currentState.trim()}',
    ];
    return sections.join('\n');
  }
}

String _preview(String value) {
  return truncateUtf16Safe(value.trim(), 200);
}

extension CharacterProfileListX on List<CharacterProfile> {
  List<CharacterProfile> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<CharacterProfile> get enabled =>
      where((c) => c.deletedAt == notDeletedSentinel).toList();
}
