// 职责: 验证结构化字段在 diff 中的渲染分派、回落策略与按行退回禁用标记。
// 关联文件:
//   lib/shared/widgets/ai/diff/change_field_render.dart
//   lib/shared/models/screenplay_element_render.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/diff/change_field_render.dart';

ChangeFieldDiffTexts render(
  String resourceType,
  String? field, {
  String? oldRaw,
  String? newRaw,
  Map<String, String> characterNames = const {},
}) {
  return renderChangeFieldDiff(
    resourceType: resourceType,
    field: field,
    oldRaw: oldRaw,
    newRaw: newRaw,
    characterNames: characterNames,
  );
}

void main() {
  test('renders screenplay elements with the export script layout', () {
    final texts = render(
      'screenplay_scenes',
      'elements',
      oldRaw:
          '[{"id":"e1","type":"action","text":"萧炎站在台阶下。"},'
          '{"id":"e2","type":"character","character_id":"cha_1"},'
          '{"id":"e3","type":"parenthetical","text":"（轻声）"},'
          '{"id":"e4","type":"dialogue","text":"三个月前。"}]',
      newRaw:
          '[{"id":"e1","type":"action","text":"萧炎站在台阶下。"},'
          '{"id":"e2","type":"character","character_id":"cha_1"},'
          '{"id":"e3","type":"parenthetical","text":"（轻声）"},'
          '{"id":"e4","type":"dialogue","text":"两个多月前。"}]',
      characterNames: const {'cha_1': '萧炎'},
    );
    expect(texts.structured, isTrue);
    expect(
      texts.oldText,
      '△ 萧炎站在台阶下。\n'
      '\n'
      '萧炎：\n'
      '    （轻声）\n'
      '    └ 三个月前。',
    );
    expect(texts.newText, endsWith('    └ 两个多月前。'));
  });

  test('falls back to the raw character id when the name is unknown', () {
    final texts = render(
      'screenplay_scenes',
      'elements',
      oldRaw: '[]',
      newRaw: '[{"id":"e1","type":"character","character_id":"cha_gone"}]',
    );
    expect(texts.newText, 'cha_gone：');
  });

  test('indents continuation paragraphs of action and dialogue', () {
    final texts = render(
      'screenplay_scenes',
      'elements',
      oldRaw: '[]',
      newRaw:
          '[{"id":"e1","type":"action","text":"第一段\\n第二段"},'
          '{"id":"e2","type":"dialogue","text":"第一句\\n第二句"}]',
    );
    // 对白紧跟上一行，不插空行；元素之间的空行只在其余类型之前出现。
    expect(
      texts.newText,
      '△ 第一段\n'
      '  第二段\n'
      '    └ 第一句\n'
      '      第二句',
    );
  });

  test('renders scene events as numbered blocks', () {
    final texts = render(
      'screenplay_scenes',
      'events',
      oldRaw: '[]',
      newRaw:
          '[{"title":"萧炎测验受辱","summary":"萧炎斗之气三段当众受辱"},'
          '{"title":"薰儿当众承诺","summary":"薰儿走向萧炎",'
          '"state_change":"萧炎心底那根弦被触动"}]',
    );
    expect(texts.structured, isTrue);
    expect(texts.oldText, '');
    expect(
      texts.newText,
      '1. 萧炎测验受辱\n'
      '   萧炎斗之气三段当众受辱\n'
      '\n'
      '2. 薰儿当众承诺\n'
      '   薰儿走向萧炎\n'
      '   → 萧炎心底那根弦被触动',
    );
  });

  test('keeps unknown event keys so real edits stay visible', () {
    final texts = render(
      'screenplay_scenes',
      'events',
      oldRaw: '[{"title":"T","evidence_quote":"旧引文"}]',
      newRaw: '[{"title":"T","evidence_quote":"新引文"}]',
    );
    expect(texts.structured, isTrue);
    expect(texts.newText, '1. T\n   evidence_quote：新引文');
  });

  test('indents multi-line event text under the number', () {
    final texts = render(
      'screenplay_scenes',
      'events',
      oldRaw: '[]',
      newRaw: '[{"title":"T","summary":"第一行\\n第二行"}]',
    );
    expect(texts.newText, '1. T\n   第一行\n   第二行');
  });

  test('unwraps json scalars', () {
    final emotion = render(
      'screenplay_scenes',
      'emotion',
      oldRaw: 'null',
      newRaw: '"紧张"',
    );
    expect(emotion.structured, isTrue);
    expect(emotion.oldText, '');
    expect(emotion.newText, '紧张');
  });

  test('renders character aliases and behavior tags line by line', () {
    final aliases = render(
      'characters',
      'aliases',
      oldRaw: '["炎"]',
      newRaw: '["炎","小炎子"]',
    );
    expect(aliases.newText, '炎\n小炎子');

    final tags = render(
      'characters',
      'behavior_tags',
      oldRaw: '[]',
      newRaw: '[{"tag":"隐忍","context":"家族场合"},{"tag":"冒进","context":""}]',
    );
    expect(tags.newText, '隐忍：家族场合\n冒进');
  });

  test('renders outline beats with status and chapter count', () {
    final texts = render(
      'outlines',
      'beats',
      oldRaw: '[]',
      newRaw:
          '[{"title":"开篇","status":"pending","chapter_count":3,'
          '"content":"萧炎测验"}]',
    );
    expect(texts.newText, '1. 开篇  [pending · 3]\n   萧炎测验');
  });

  test('leaves fields outside the whitelist untouched', () {
    final texts = render(
      'chapters',
      'content',
      oldRaw: '第一章',
      newRaw: '第一章 修订',
    );
    expect(texts.structured, isFalse);
    expect(texts.oldText, '第一章');
    expect(texts.newText, '第一章 修订');
  });

  test('falls back to stored text when the payload does not parse', () {
    const broken = '[{"type":"action",';
    final texts = render(
      'screenplay_scenes',
      'elements',
      oldRaw: '[]',
      newRaw: broken,
    );
    expect(texts.structured, isFalse);
    expect(texts.oldText, '[]');
    expect(texts.newText, broken);
  });

  test('falls back when rendering would hide a real change', () {
    // 渲染丢弃元素 id；只改 id 时渲染文本相同，此时必须回落原文，
    // 否则历史里会把一次真实改动显示成「无变化」。
    const oldRaw = '[{"id":"a","type":"action","text":"同一句"}]';
    const newRaw = '[{"id":"b","type":"action","text":"同一句"}]';
    final texts = render(
      'screenplay_scenes',
      'elements',
      oldRaw: oldRaw,
      newRaw: newRaw,
    );
    expect(texts.structured, isFalse);
    expect(texts.oldText, oldRaw);
    expect(texts.newText, newRaw);
  });

  test('treats an absent side as empty content', () {
    final texts = render(
      'screenplay_scenes',
      'elements',
      newRaw: '[{"id":"a","type":"action","text":"新建场次"}]',
    );
    expect(texts.structured, isTrue);
    expect(texts.oldText, '');
    expect(texts.newText, '△ 新建场次');
  });
}
