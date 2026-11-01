// 职责: Prompt 组装器 — 按固定 section 顺序、标题和分隔符组合已生成的 prompt 片段。
// 关联文件:
//   lib/shared/services/ai/prompts/prompt_fragments.dart
//   lib/shared/services/ai/prompts/ai_prompt_service.dart

class PromptSection {
  const PromptSection({
    required this.key,
    required this.title,
    required this.content,
    this.description,
  });

  final String key;
  final String title;
  final String? description;
  final String content;

  bool get isEmpty => content.trim().isEmpty;
}

class PromptComposer {
  const PromptComposer({this.separator = '\n\n---\n\n'});

  final String separator;

  String compose(List<PromptSection> sections) {
    final rendered = <String>[];
    for (final section in sections) {
      if (section.isEmpty) {
        continue;
      }
      rendered.add(_renderSection(section));
    }
    return rendered.join(separator).trim();
  }

  String _renderSection(PromptSection section) {
    if (section.key == 'system_instruction') {
      return section.content.trim();
    }
    final buffer = StringBuffer();
    buffer.writeln('# ${section.title}');
    buffer.writeln();
    final description = section.description?.trim();
    if (description != null && description.isNotEmpty) {
      buffer.writeln(description);
      buffer.writeln();
    }
    buffer.write(section.content.trim());
    return buffer.toString().trim();
  }
}
