// 职责: 定义人物在特定情境下的结构化行为倾向。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/novel_content.dart

class CharacterBehaviorTag {
  const CharacterBehaviorTag({required this.tag, required this.context});

  final String tag;
  final String context;

  factory CharacterBehaviorTag.fromJson(Map<String, dynamic> json) {
    final tag = json['tag'];
    final context = json['context'];
    if (tag is! String || context is! String) {
      throw const FormatException(
        'Character behavior tag requires string tag and context.',
      );
    }
    return CharacterBehaviorTag(tag: tag, context: context);
  }

  Map<String, dynamic> toJson() => {'tag': tag, 'context': context};

  CharacterBehaviorTag normalized() {
    return CharacterBehaviorTag(tag: tag.trim(), context: context.trim());
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CharacterBehaviorTag &&
            other.tag == tag &&
            other.context == context;
  }

  @override
  int get hashCode => Object.hash(tag, context);
}
