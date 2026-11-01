// 职责: 验证剧本结构化元素的单向文本渲染与规范序列化。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/shared/models/screenplay_element_render.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay_element_render.dart';

void main() {
  test('combined interior exterior renders as INT./EXT.', () {
    expect(
      renderScreenplayElements(
        const [
          ScreenplayElement(
            type: ScreenplayElementType.scene_heading,
            sceneId: 'scene',
            episodeId: 'episode',
            interiorExterior: 'interior_exterior',
            locationId: 'gate',
            timeLabel: 'Morning',
          ),
        ],
        characterNames: const {},
        locationNames: const {'gate': 'East gate'},
      ),
      'INT./EXT. · East gate · Morning',
    );
  });
  const elements = <ScreenplayElement>[
    ScreenplayElement(type: ScreenplayElementType.action, text: '雨落下来。'),
    ScreenplayElement(
      id: 'speaker',
      type: ScreenplayElementType.character,
      characterId: 'character_1',
      extension: '画外音',
    ),
    ScreenplayElement(type: ScreenplayElementType.parenthetical, text: '低声'),
    ScreenplayElement(type: ScreenplayElementType.dialogue, text: '走吧。'),
    ScreenplayElement(type: ScreenplayElementType.note, text: '待确认天气'),
  ];

  test('renders character names and omits notes by default', () {
    expect(
      renderScreenplayElements(
        elements,
        characterNames: const {'character_1': '林默'},
      ),
      '雨落下来。\n林默 (画外音)\n(低声)\n走吧。',
    );
    expect(
      renderScreenplayElements(
        elements,
        characterNames: const {'character_1': '林默'},
        includeNotes: true,
      ),
      endsWith('\n[[待确认天气]]'),
    );
  });

  test('keeps full-width parentheses instead of double-wrapping', () {
    expect(
      renderScreenplayElements(
        const [
          ScreenplayElement(
            type: ScreenplayElementType.parenthetical,
            text: '（轻声，像说给自己听）',
          ),
        ],
        characterNames: const {},
      ),
      '（轻声，像说给自己听）',
    );
  });

  test('serializes normalized element fields in canonical order', () {
    expect(
      serializeScreenplayElements(elements.take(2)),
      '[{"type":"action","text":"雨落下来。"},'
      '{"id":"speaker","type":"character",'
      '"character_id":"character_1","extension":"画外音"}]',
    );
  });
}
