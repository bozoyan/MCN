// 职责: 测试 roleplay 模板的角色资料注入与条件渲染。
// 关联文件:
//   assets/prompts/agent/roleplay_master.md
//   lib/shared/services/ai/roleplay_orchestrator.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';

void main() {
  group('roleplay 系统提示 — 无变量', () {
    test('系统提示不包含 Mustache 变量', () {
      const template = '''
你正在进行沉浸式一对一角色扮演。你的唯一任务是扮演指定角色。

## 扮演原则
1. **始终在角色内**：只以角色的身份、语气、知识边界和情绪反应说话。
2. **保持角色一致**：回应前在内部核对角色的身份、性格、动机。
3. **受限视角**：只知道角色应该知道的信息。

## 输出格式
- 直接输出角色的下一轮回应。
''';
      final result = PromptTemplateService.renderString(template);
      expect(result, contains('以角色的身份'));
      expect(result, contains('只知道角色应该知道'));
      expect(result, contains('直接输出角色的下一轮回应'));
      expect(result, isNot(contains('{{')));
    });
  });

  group('roleplay 任务提示 — 角色资料注入', () {
    test('完整角色资料注入', () {
      const template = '''
{{#character_name}}
## 角色资料
- 角色：{{character_name}}
- 身份：{{character_role}}
{{#character_summary}}- 简介：{{character_summary}}{{/character_summary}}
{{/character_name}}

## 扮演要求
- 以{{character_name}}的身份和语气回应
- 言行须符合角色性格、知识水平、语言习惯、社会地位
- 直接输出角色回应
''';

      final result = PromptTemplateService.renderString(template, {
        'character_name': '陆泽',
        'character_role': '主角',
        'character_summary': '网游高手，性格冷静',
      });

      expect(result, contains('## 角色资料'));
      expect(result, contains('- 角色：陆泽'));
      expect(result, contains('- 身份：主角'));
      expect(result, contains('- 简介：网游高手，性格冷静'));
      expect(result, contains('以陆泽的身份和语气回应'));
    });

    test('无角色名时隐藏角色资料区块', () {
      const template = '''
{{#character_name}}
## 角色资料
- 角色：{{character_name}}
- 身份：{{character_role}}
{{#character_summary}}- 简介：{{character_summary}}{{/character_summary}}
{{/character_name}}

## 扮演要求
- 以{{character_name}}的身份和语气回应
- 直接输出角色回应
''';

      final result = PromptTemplateService.renderString(template, {
        'character_role': '主角',
      });

      expect(result, isNot(contains('## 角色资料')));
      expect(result, contains('## 扮演要求'));
      expect(result, contains('以的身份和语气回应'));
    });

    test('无角色简介时隐藏简介行', () {
      const template = '''
{{#character_name}}
## 角色资料
- 角色：{{character_name}}
- 身份：{{character_role}}
{{#character_summary}}- 简介：{{character_summary}}{{/character_summary}}
{{/character_name}}
''';

      final result = PromptTemplateService.renderString(template, {
        'character_name': '陆泽',
        'character_role': '主角',
      });

      expect(result, contains('- 角色：陆泽'));
      expect(result, contains('- 身份：主角'));
      expect(result, isNot(contains('- 简介：')));
    });

    test('角色名为空时条件块不渲染', () {
      const template = '''
{{#character_name}}
## 角色资料
- 角色：{{character_name}}
{{/character_name}}
''';

      final result = PromptTemplateService.renderString(template, {});

      expect(result, isEmpty);
    });
  });
}
