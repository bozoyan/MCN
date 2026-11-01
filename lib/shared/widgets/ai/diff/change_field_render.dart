// 职责: 把 working change 的结构化字段文本渲染成 diff 可读形态，并标记该字段禁止按行退回。
// 关联文件:
//   lib/shared/models/screenplay_element_render.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/widgets/history/change_history_components.dart
//   lib/desktop/widgets/ai/diff/pending_changes_detail_dialog.dart
import 'dart:convert';

import '../../../models/screenplay_element_render.dart';
import '../../../services/working_overlay.dart';

/// 一对字段文本在 diff 中的展示形态。
class ChangeFieldDiffTexts {
  const ChangeFieldDiffTexts({
    required this.oldText,
    required this.newText,
    required this.structured,
  });

  final String oldText;
  final String newText;

  /// true = 文本由结构化 JSON 渲染而来，与存储形态不一一对应（元素 id、JSON
  /// 结构都在渲染中丢弃），因此只能整体接受/回滚，不能按行退回。
  final bool structured;
}

/// 渲染一对 old/new 字段文本供 diff 展示。
///
/// 白名单未命中、或 JSON 解析失败时原样返回存储文本，[ChangeFieldDiffTexts
/// .structured] 为 false。渲染后两侧文本相同但存储文本不同时同样回落原文 ——
/// 渲染是有损的，不能让一次真实改动在历史里显示成「无变化」。
ChangeFieldDiffTexts renderChangeFieldDiff({
  required String resourceType,
  required String? field,
  required String? oldRaw,
  required String? newRaw,
  Map<String, String> characterNames = const {},
}) {
  final oldStored = oldRaw ?? '';
  final newStored = newRaw ?? '';
  final raw = ChangeFieldDiffTexts(
    oldText: oldStored,
    newText: newStored,
    structured: false,
  );

  final render = _rendererFor(resourceType, field);
  if (render == null) {
    return raw;
  }

  final String oldText;
  final String newText;
  try {
    oldText = _renderOrEmpty(oldStored, render, characterNames);
    newText = _renderOrEmpty(newStored, render, characterNames);
  } on Object {
    return raw;
  }

  if (oldText == newText && oldStored != newStored) {
    return raw;
  }
  return ChangeFieldDiffTexts(
    oldText: oldText,
    newText: newText,
    structured: true,
  );
}

typedef _FieldRenderer =
    String Function(String value, Map<String, String> characterNames);

/// 字段 → 渲染器。取值与 `WorkingOverlayService` 的字段快照分支对齐：
/// 那里用 `jsonEncode` / `serializeScreenplayElements` 落库的字段，这里负责还原。
_FieldRenderer? _rendererFor(String resourceType, String? field) {
  switch (resourceType) {
    case workingChangeResourceTypeScreenplayScenes:
      return switch (field) {
        'elements' => _renderElements,
        'events' => _renderEvents,
        'emotion' || 'interior_exterior' => _renderJsonScalar,
        _ => null,
      };
    case 'characters':
      return switch (field) {
        'aliases' => _renderAliases,
        'behavior_tags' => _renderBehaviorTags,
        _ => null,
      };
    case 'outlines':
      return switch (field) {
        'beats' => _renderBeats,
        _ => null,
      };
    default:
      return null;
  }
}

/// 空存储文本没有 JSON 可解，直接当空内容处理（新建资源的 oldText 就是空串）。
String _renderOrEmpty(
  String value,
  _FieldRenderer render,
  Map<String, String> characterNames,
) {
  if (value.isEmpty) {
    return '';
  }
  return render(value, characterNames);
}

String _renderElements(String value, Map<String, String> characterNames) {
  return renderSerializedScreenplayElementsAsScript(
    value,
    characterNames: characterNames,
  );
}

/// 场次事件：序号行 + 缩进的 summary + `→` 引导的 state_change。
/// 已知键之外的键按 `key：value` 追加，避免渲染悄悄吃掉改动。
String _renderEvents(String value, Map<String, String> _) {
  final events = _decodeList(value);
  final blocks = <String>[];
  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    if (event is! Map) {
      blocks.add('${index + 1}. ${event ?? ''}');
      continue;
    }
    final entries = Map<String, Object?>.from(event);
    final lines = <String>[];
    void take(String key, String Function(String value) format) {
      final text = entries.remove(key)?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        lines.add(format(text));
      }
    }

    take('title', (text) => text);
    take('summary', (text) => text);
    take('state_change', (text) => '→ $text');
    for (final entry in entries.entries) {
      final text = entry.value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        lines.add('${entry.key}：$text');
      }
    }
    blocks.add(_numberedBlock(index + 1, lines));
  }
  return blocks.join('\n\n');
}

String _renderAliases(String value, Map<String, String> _) {
  return _decodeList(value)
      .map((alias) => alias?.toString().trim() ?? '')
      .where((alias) => alias.isNotEmpty)
      .join('\n');
}

String _renderBehaviorTags(String value, Map<String, String> _) {
  final lines = <String>[];
  for (final raw in _decodeList(value)) {
    if (raw is! Map) {
      continue;
    }
    final tag = raw['tag']?.toString().trim() ?? '';
    final context = raw['context']?.toString().trim() ?? '';
    if (tag.isEmpty && context.isEmpty) {
      continue;
    }
    lines.add(context.isEmpty ? tag : '$tag：$context');
  }
  return lines.join('\n');
}

/// 大纲节拍：序号行带状态与章数，正文缩进跟随。
String _renderBeats(String value, Map<String, String> _) {
  final blocks = <String>[];
  final beats = _decodeList(value);
  for (var index = 0; index < beats.length; index++) {
    final beat = beats[index];
    if (beat is! Map) {
      continue;
    }
    final title = beat['title']?.toString().trim() ?? '';
    final status = beat['status']?.toString().trim() ?? '';
    final chapterCount = beat['chapter_count']?.toString().trim() ?? '';
    final meta = [
      status,
      if (chapterCount.isNotEmpty) chapterCount,
    ].where((part) => part.isNotEmpty).join(' · ');
    final heading = meta.isEmpty ? title : '$title  [$meta]';
    final content = beat['content']?.toString().trim() ?? '';
    blocks.add(
      _numberedBlock(index + 1, [
        if (heading.trim().isNotEmpty) heading.trim(),
        if (content.isNotEmpty) content,
      ]),
    );
  }
  return blocks.join('\n\n');
}

/// `jsonEncode` 过的标量：还原成裸值，null 显示为空。
String _renderJsonScalar(String value, Map<String, String> _) {
  final decoded = jsonDecode(value);
  if (decoded == null) {
    return '';
  }
  if (decoded is List || decoded is Map) {
    throw const FormatException('Expected a scalar value.');
  }
  return decoded.toString();
}

List<Object?> _decodeList(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array.');
  }
  return decoded;
}

/// 首行冠序号，其余行按序号宽度缩进；多行文本逐行缩进，diff 里才不会断层。
String _numberedBlock(int number, List<String> lines) {
  final prefix = '$number. ';
  final indent = ' ' * prefix.length;
  final flat = lines
      .expand((line) => line.split('\n'))
      .map((line) => line.trimRight())
      .toList();
  if (flat.isEmpty) {
    return '$number.';
  }
  return [
    '$prefix${flat.first}',
    ...flat.skip(1).map((line) => '$indent$line'),
  ].join('\n');
}
