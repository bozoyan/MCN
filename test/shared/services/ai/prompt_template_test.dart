// 职责: 验证模板变量、条件渲染及解析或渲染失败时保留完整原文
// 关联文件:
//   lib/shared/services/ai/prompt_template.dart
//   lib/shared/services/ai/prompts/prompt_definition.dart
//   lib/shared/services/ai/prompts/prompt_registry.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/ai/prompts/prompt_registry.dart';

class _UnrenderableValue {
  @override
  String toString() => throw StateError('test value cannot be rendered');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PromptTemplateService.renderString', () {
    test('替换简单变量', () {
      final result = PromptTemplateService.renderString('你好，{{name}}！', {
        'name': '世界',
      });
      expect(result, '你好，世界！');
    });

    test('替换多个变量', () {
      final result = PromptTemplateService.renderString('{{greet}}，{{name}}！', {
        'greet': 'Hello',
        'name': 'world',
      });
      expect(result, 'Hello，world！');
    });

    test('缺失变量在 lenient 模式下输出空字符串', () {
      final result = PromptTemplateService.renderString('Hello，{{name}}！', {});
      expect(result, 'Hello，！');
    });

    test('条件块在变量非空时渲染', () {
      final result = PromptTemplateService.renderString(
        '{{#show}}可见{{/show}}{{^show}}隐藏{{/show}}',
        {'show': 'true'},
      );
      expect(result, '可见');
    });

    test('条件块在变量不存在时不渲染', () {
      final result = PromptTemplateService.renderString(
        '{{#show}}可见{{/show}}{{^show}}隐藏{{/show}}',
        {},
      );
      expect(result, '隐藏');
    });

    test('嵌套条件块', () {
      final result = PromptTemplateService.renderString(
        '{{#outer}}{{#inner}}deep{{/inner}}{{/outer}}',
        {'outer': 'true', 'inner': 'true'},
      );
      expect(result, 'deep');
    });

    test('条件块中引用自身变量', () {
      final result = PromptTemplateService.renderString(
        '{{#name}}你好，{{name}}{{/name}}',
        {'name': '小明'},
      );
      expect(result, '你好，小明');
    });

    test('条件块中引用父级变量', () {
      final result = PromptTemplateService.renderString(
        '{{#flag}}name={{name}}{{/flag}}',
        {'flag': 'true', 'name': 'test'},
      );
      expect(result, 'name=test');
    });

    test('HTML 不转义', () {
      final result = PromptTemplateService.renderString('{{content}}', {
        'content': '<b>bold</b>',
      });
      expect(result, '<b>bold</b>');
    });

    test('空输入', () {
      final result = PromptTemplateService.renderString('');
      expect(result, '');
    });

    test('无变量模板', () {
      final result = PromptTemplateService.renderString('纯文本模板');
      expect(result, '纯文本模板');
    });

    for (final template in [
      '  名称：{{name}}\n{{#show}}未闭合条件  ',
      '  名称：{{name}}\n{{#show}}闭合错误{{/other}}  ',
    ]) {
      test('解析失败保留完整原文：$template', () {
        expect(
          PromptTemplateService.renderString(template, {
            'name': '已替换',
            'show': true,
          }),
          template,
        );
      });
    }

    test('渲染失败丢弃部分结果并保留完整原文', () {
      const template = '  {{name}}\n{{value}}  ';
      expect(
        PromptTemplateService.renderString(template, {
          'name': '已替换',
          'value': _UnrenderableValue(),
        }),
        template,
      );
    });
  });

  group('PromptTemplateService.renderString - 多行模板', () {
    test('多行模板替换变量', () {
      final template = '''
## 标题
{{title}}

{{#content}}内容：{{content}}{{/content}}
{{^content}}无内容{{/content}}
''';

      final result = PromptTemplateService.renderString(template, {
        'title': '测试',
        'content': '正文',
      });

      expect(result, contains('## 标题'));
      expect(result, contains('测试'));
      expect(result, contains('内容：正文'));
      expect(result, isNot(contains('无内容')));
    });

    test('多行模板 - 缺失可选部分', () {
      final template = '''
## 标题
{{title}}

{{#content}}内容：{{content}}{{/content}}
{{^content}}无内容{{/content}}
''';

      final result = PromptTemplateService.renderString(template, {
        'title': '测试',
      });

      expect(result, contains('无内容'));
      expect(result, isNot(contains('内容：')));
    });
  });

  group('PromptTemplateService.renderString - 真实场景模拟', () {
    test('系统 prompt 无变量', () {
      final template = '你是 Reveric 的小说写作助手。\n\n请遵守规则。';
      final result = PromptTemplateService.renderString(template);
      expect(result, '你是 Reveric 的小说写作助手。\n\n请遵守规则。');
    });

    test('多行技能内容作为变量渲染', () {
      final template = '{{skill}}';
      final result = PromptTemplateService.renderString(template, {
        'skill': '## chapter-planning\n\n1. 小周期推进\n2. 伏笔不空转\n\n> 引用内容',
      });
      expect(result, contains('## chapter-planning'));
      expect(result, contains('1. 小周期推进'));
      expect(result, contains('2. 伏笔不空转'));
      expect(result, contains('> 引用内容'));
    });

    test('多个技能变量同时渲染', () {
      final template = '规则A：{{rule_a}}\n规则B：{{rule_b}}';
      final result = PromptTemplateService.renderString(template, {
        'rule_a': '规则A的完整内容',
        'rule_b': '规则B的完整内容',
      });
      expect(result, contains('规则A的完整内容'));
      expect(result, contains('规则B的完整内容'));
    });

    test('章节正文任务模板', () {
      final template = '''
请根据以下信息创作当前章节正文初稿。

## 章节标题
{{chapter_title}}

## 章节大纲
{{outline}}

{{#previous_content}}
## 前章参考
{{previous_content}}
{{/previous_content}}

## 创作要求
1. 严格按照大纲中的节拍顺序展开场景，不遗漏关键事件。
2. 直接输出正文，不要输出创作说明。
''';

      final result = PromptTemplateService.renderString(template, {
        'chapter_title': '第一章',
        'outline': '主角登场',
        'previous_content': '之前的剧情',
      });

      expect(result, contains('第一章'));
      expect(result, contains('主角登场'));
      expect(result, contains('之前的剧情'));
      expect(result, contains('直接输出正文'));
    });
  });

  group('all prompt templates contain their declared variables', () {
    final repoRoot = Directory.current.path;
    final variablePattern = RegExp(r'\{\{[#^/]?(\w+)\}\}');

    for (final definition in PromptRegistry.definitions) {
      final templatePath = definition.templatePath;
      if (templatePath == null) continue;

      test('${definition.id} — $templatePath', () {
        final file = File('$repoRoot/$templatePath.md');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Template file missing: ${file.path}',
        );

        final content = file.readAsStringSync();
        final usedVars = variablePattern
            .allMatches(content)
            .map((m) => m.group(1)!)
            .toSet();

        for (final variable in definition.variables) {
          expect(
            usedVars.contains(variable),
            isTrue,
            reason:
                'Prompt "${definition.id}" declares variable '
                '"$variable" but it is not used in $templatePath.md',
          );
        }
      });
    }
  });
}
