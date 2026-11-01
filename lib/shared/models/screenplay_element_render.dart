// 职责: 将结构化剧本元素单向渲染为文本（紧凑行与剧本排版两种），并提供 overlay 规范序列化。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/services/novel_export.dart
//   lib/shared/widgets/ai/diff/change_field_render.dart

import 'dart:convert';

import 'screenplay_element.dart';

String renderScreenplayElements(
  Iterable<ScreenplayElement> elements, {
  required Map<String, String> characterNames,
  bool includeNotes = false,
  Map<String, String> locationNames = const {},
  String deletedCharacterSuffix = ' (deleted)',
}) {
  final lines = <String>[];
  for (final raw in elements) {
    final element = raw.normalized();
    if (element.type == ScreenplayElementType.note && !includeNotes) {
      continue;
    }
    switch (element.type) {
      case ScreenplayElementType.scene_heading:
        lines.add(
          [
            if (element.interiorExterior != null)
              switch (element.interiorExterior) {
                'interior' => 'INT.',
                'interior_exterior' => 'INT./EXT.',
                _ => 'EXT.',
              },
            if (element.locationId != null)
              locationNames[element.locationId] ?? element.locationId!,
            if (element.timeLabel?.isNotEmpty == true) element.timeLabel!,
          ].join(' · '),
        );
      case ScreenplayElementType.character:
        final characterId = element.characterId!;
        final name =
            characterNames[characterId] ??
            '$characterId$deletedCharacterSuffix';
        final extension = element.extension.isEmpty
            ? ''
            : ' (${element.extension})';
        lines.add('$name$extension');
      case ScreenplayElementType.parenthetical:
        final text = element.text.trim();
        // 中文 IME 下括注正文自带全角括号；只认半角会再套一层成 `(（低声）)`。
        final wrapped =
            (text.startsWith('(') && text.endsWith(')')) ||
            (text.startsWith('（') && text.endsWith('）'));
        lines.add(wrapped ? text : '($text)');
      case ScreenplayElementType.note:
        lines.add('[[${element.text}]]');
      case ScreenplayElementType.action:
      case ScreenplayElementType.dialogue:
      case ScreenplayElementType.transition:
      case ScreenplayElementType.subtitle:
        lines.add(element.text);
    }
  }
  return lines.join('\n');
}

/// 剧本正文排版 —— 与编辑器的 document_heading.dart、readonly_element.dart 和
/// element_layout.dart 对齐：动作冠 `△`、角色行收 `：`、括注与对白缩进四格、
/// 对白冠 `└`，元素之间空行（括注与对白紧跟上一行，不断开）。
///
/// TXT 导出与修改历史 diff 共用这一套字符约定，两处看到的剧本必须长得一样。
/// 场次头与标题对齐是导出专有的（需要场次序号、出场表和固定行宽），由
/// [onSceneHeading] / [alignTitle] 注入，不传则跳过场次头、标题不做填充。
List<String> formatScreenplayElementLines(
  Iterable<ScreenplayElement> elements, {
  required String Function(String characterId) characterName,
  String Function(String text)? formatNote,
  List<String> Function(ScreenplayElement element)? onSceneHeading,
  String Function(String line, {required bool centered})? alignTitle,
}) {
  final lines = <String>[];
  for (final raw in elements) {
    final element = raw.normalized();
    if (lines.isNotEmpty &&
        element.type != ScreenplayElementType.parenthetical &&
        element.type != ScreenplayElementType.dialogue) {
      lines.add('');
    }
    switch (element.type) {
      case ScreenplayElementType.scene_heading:
        lines.addAll(onSceneHeading?.call(element) ?? const <String>[]);
      case ScreenplayElementType.action:
        final paragraphs = element.text.split('\n');
        lines.add('△ ${paragraphs.first}');
        lines.addAll(paragraphs.skip(1).map((line) => '  $line'));
      case ScreenplayElementType.character:
        final extension = element.extension.isEmpty
            ? ''
            : '（${element.extension}）';
        lines.add('${characterName(element.characterId!)}$extension：');
      case ScreenplayElementType.parenthetical:
        // 括注正文可能带半角或全角括号，也可能裸文本；一律剥到裸文本再套全角，
        // 免得出现 `(（低声）)` 这种双层括号。
        var text = element.text.trim();
        if ((text.startsWith('(') && text.endsWith(')')) ||
            (text.startsWith('（') && text.endsWith('）'))) {
          text = text.substring(1, text.length - 1);
        }
        lines.add('    （${text.replaceAll('\n', '\n    ')}）');
      case ScreenplayElementType.dialogue:
        final paragraphs = element.text.split('\n');
        lines.add('    └ ${paragraphs.first}');
        lines.addAll(paragraphs.skip(1).map((line) => '      $line'));
      case ScreenplayElementType.transition:
      case ScreenplayElementType.subtitle:
        final centered = element.type == ScreenplayElementType.subtitle;
        lines.addAll(
          element.text
              .split('\n')
              .map(
                (line) => alignTitle?.call(line, centered: centered) ?? line,
              ),
        );
      case ScreenplayElementType.note:
        lines.add(formatNote?.call(element.text) ?? '[[${element.text}]]');
    }
  }
  return lines;
}

String serializeScreenplayElements(Iterable<ScreenplayElement> elements) {
  final encoded = <Map<String, Object?>>[];
  for (final raw in elements) {
    final element = raw.normalized();
    if (element.isHeading) {
      continue;
    }
    encoded.add(<String, Object?>{
      if (element.id != null) 'id': element.id,
      'type': element.type.name,
      if (element.text.isNotEmpty) 'text': element.text,
      if (element.characterId != null) 'character_id': element.characterId,
      if (element.extension.isNotEmpty) 'extension': element.extension,
    });
  }
  return jsonEncode(encoded);
}

/// 解码 overlay 中的规范元素 JSON。只认规范形态，不解析剧本自由文本。
List<ScreenplayElement> decodeSerializedScreenplayElements(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) {
    throw const FormatException('Screenplay elements must be an array.');
  }
  return decoded.map((raw) {
    if (raw is! Map) {
      throw const FormatException('Screenplay element must be an object.');
    }
    final item = Map<String, dynamic>.from(raw);
    return ScreenplayElement(
      id: item['id']?.toString(),
      type: screenplayElementTypeFromName(item['type']?.toString() ?? ''),
      text: item['text']?.toString() ?? '',
      characterId: item['character_id']?.toString(),
      extension: item['extension']?.toString() ?? '',
    );
  }).toList();
}

/// 把 overlay 中的结构化元素 JSON 渲染成剧本排版，供 diff 与预览展示。
/// 序列化时已跳过场次头，这里不会遇到；角色名缺失时退回显示 id。
String renderSerializedScreenplayElementsAsScript(
  String value, {
  Map<String, String> characterNames = const {},
}) {
  return formatScreenplayElementLines(
    decodeSerializedScreenplayElements(value),
    characterName: (id) => characterNames[id] ?? id,
  ).join('\n');
}
