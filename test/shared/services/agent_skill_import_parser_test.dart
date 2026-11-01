// 职责: 测试 AgentSkillImportParser 的 frontmatter 解析（含 metadata.category/tags）
//   与 AgentSkillImportParser.write 的 round-trip（不写 agent_scopes）。
// 关联文件:
//   lib/shared/services/agent_skill_import_parser.dart
//   lib/shared/services/agent_skill_transfer.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/agent_skill_import_parser.dart';

void main() {
  group('AgentSkillImportParser.parse', () {
    test('parses YAML block scalars, comments and metadata lists', () {
      final result = AgentSkillImportParser.parse('''---
name: sample # a comment
description: >-
  First line
  second line
when_to_use: |-
  Writing
  Revising
metadata:
  tags: [writing, revision]
---
Body
''')!;
      expect(result.name, 'sample');
      expect(result.description, 'First line second line');
      expect(result.whenToUse, 'Writing\nRevising');
      expect(result.tags, ['writing', 'revision']);
      expect(result.body, 'Body\n');
    });

    test('malformed YAML and non-string required values are rejected', () {
      for (final header in [
        'name: [',
        'name: [a]\ndescription: text',
        'name: a\ndescription: true',
      ]) {
        expect(AgentSkillImportParser.parse('---\n$header\n---\nbody'), isNull);
      }
    });

    test('parses basic frontmatter without category/tags', () {
      const content = '''---
name: 扩写场景
when_to_use: 用户要求扩写某个场景时
description: 把简短场景扩展为完整段落
---
# 扩写场景
详细指令...''';
      final result = AgentSkillImportParser.parse(content);

      expect(result, isNotNull);
      expect(result!.name, '扩写场景');
      expect(result.whenToUse, '用户要求扩写某个场景时');
      expect(result.description, '把简短场景扩展为完整段落');
      expect(result.category, isEmpty);
      expect(result.tags, isEmpty);
      expect(result.body, startsWith('# 扩写场景'));
    });

    test('parses CRLF frontmatter used by Windows checkouts', () {
      const content =
          '---\r\n'
          'name: 创作向导\r\n'
          'when_to_use: 初始化小说时\r\n'
          'description: 引导完成小说基础配置\r\n'
          '---\r\n'
          '# 创作向导\r\n'
          '正文';
      final result = AgentSkillImportParser.parse(content);

      expect(result, isNotNull);
      expect(result!.name, '创作向导');
      expect(result.whenToUse, '初始化小说时');
      expect(result.description, '引导完成小说基础配置');
      expect(result.body, startsWith('# 创作向导'));
    });

    test('ignores legacy agent_scopes on import', () {
      const content = '''---
name: 扩写场景
description: desc
agent_scopes: [chat]
---
body''';
      final result = AgentSkillImportParser.parse(content);
      expect(result, isNotNull);
      expect(result!.name, '扩写场景');
    });

    test('parses category and tags from metadata', () {
      const content = '''---
name: 爽文节奏
description: 调整章节节奏以符合爽文风格
metadata:
  category: 节奏
  tags: 爽文, 节奏, 快节奏
---
正文...''';
      final result = AgentSkillImportParser.parse(content);

      expect(result, isNotNull);
      expect(result!.name, '爽文节奏');
      expect(result.category, '节奏');
      expect(result.tags, ['爽文', '节奏', '快节奏']);
    });

    test('ignores obsolete top-level category and tags', () {
      const content = '''---
name: 爽文节奏
description: 调整章节节奏以符合爽文风格
category: 节奏
tags: [爽文, 节奏, 快节奏]
---
正文...''';
      final result = AgentSkillImportParser.parse(content);

      expect(result, isNotNull);
      expect(result!.category, isEmpty);
      expect(result.tags, isEmpty);
    });

    test('prefers metadata category/tags over legacy top-level', () {
      const content = '''---
name: 爽文节奏
description: 调整章节节奏以符合爽文风格
category: legacy-cat
tags: [legacy]
metadata:
  category: 节奏
  tags: 爽文, 快节奏
---
正文...''';
      final result = AgentSkillImportParser.parse(content);

      expect(result, isNotNull);
      expect(result!.category, '节奏');
      expect(result.tags, ['爽文', '快节奏']);
    });

    test('falls back when_to_use to description when missing or empty', () {
      const missing = '''---
name: 爽文节奏
description: 调整章节节奏以符合爽文风格
---
正文...''';
      final missingResult = AgentSkillImportParser.parse(missing);
      expect(missingResult, isNotNull);
      expect(missingResult!.whenToUse, '调整章节节奏以符合爽文风格');
      expect(missingResult.description, '调整章节节奏以符合爽文风格');

      const empty = '''---
name: 爽文节奏
when_to_use:
description: 调整章节节奏以符合爽文风格
---
正文...''';
      final emptyResult = AgentSkillImportParser.parse(empty);
      expect(emptyResult, isNotNull);
      expect(emptyResult!.whenToUse, '调整章节节奏以符合爽文风格');
    });

    test('returns null when name or description is missing', () {
      const content = '''---
when_to_use: test
---
body''';
      expect(AgentSkillImportParser.parse(content), isNull);
    });

    test('returns null when no frontmatter', () {
      expect(AgentSkillImportParser.parse('just text'), isNull);
    });
  });

  group('AgentSkillImportParser.write', () {
    test('round-trips multiline and YAML-sensitive text', () {
      for (final description in [
        'true',
        '123',
        'a # comment',
        'a: b',
        'a\nb',
        'a "quote" and \\ slash',
      ]) {
        final output = AgentSkillImportParser.write(
          name: 'test',
          description: description,
          body: 'body',
        );
        expect(AgentSkillImportParser.parse(output)!.description, description);
      }
    });
    test('writes frontmatter with metadata category/tags, no agent_scopes', () {
      final output = AgentSkillImportParser.write(
        name: '扩写场景',
        description: '把简短场景扩展为完整段落',
        body: '# 扩写场景\n详细指令...',
        whenToUse: '用户要求扩写时',
        category: '扩写',
        tags: ['节奏', '爽文'],
      );

      expect(output, contains('name: 扩写场景'));
      expect(output, contains('when_to_use: 用户要求扩写时'));
      expect(output, contains('description: 把简短场景扩展为完整段落'));
      expect(output, isNot(contains('agent_scopes')));
      expect(output, contains('metadata:'));
      expect(output, contains('  category: 扩写'));
      expect(output, contains('  tags: 节奏, 爽文'));
      expect(RegExp(r'^category:', multiLine: true).hasMatch(output), isFalse);
      expect(RegExp(r'^tags:', multiLine: true).hasMatch(output), isFalse);
      expect(output, contains('# 扩写场景'));
    });

    test('omits empty optional fields', () {
      final output = AgentSkillImportParser.write(
        name: 'test',
        description: 'desc',
        body: 'body',
      );

      expect(output, contains('name: test'));
      expect(output, contains('description: desc'));
      expect(output, isNot(contains('when_to_use')));
      expect(output, isNot(contains('agent_scopes')));
      expect(output, isNot(contains('metadata')));
      expect(output, isNot(contains('category')));
      expect(output, isNot(contains('tags')));
    });

    test('round-trips parse -> write -> parse', () {
      const original = '''---
name: 爽文节奏
when_to_use: 用户要求调整节奏时
description: 调整章节节奏
metadata:
  category: 节奏
  tags: 爽文, 快节奏
---
# 爽文节奏
这是正文。''';
      final parsed = AgentSkillImportParser.parse(original)!;
      final written = AgentSkillImportParser.write(
        name: parsed.name,
        description: parsed.description,
        body: parsed.body,
        whenToUse: parsed.whenToUse,
        category: parsed.category,
        tags: parsed.tags,
      );
      final reparsed = AgentSkillImportParser.parse(written)!;

      expect(reparsed.name, parsed.name);
      expect(reparsed.whenToUse, parsed.whenToUse);
      expect(reparsed.description, parsed.description);
      expect(reparsed.category, parsed.category);
      expect(reparsed.tags, parsed.tags);
      expect(reparsed.body, parsed.body);
    });
  });
}
