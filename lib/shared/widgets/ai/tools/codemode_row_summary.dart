// 职责: 从子调用 JSON 中仅提取行头所需字段，跳过正文和详情对象。
// 关联文件:
//   lib/shared/widgets/ai/tools/codemode_detail_dialog.dart
//   lib/shared/widgets/ai/tools/tool_card_descriptor.dart
//   lib/shared/models/ai_nested_tool_call.dart
import 'dart:convert';

import '../../../models/ai_nested_tool_call.dart';

Map<String, dynamic> codemodeRowArguments(AiNestedToolCall call) {
  final keys = switch (call.toolName) {
    'Read' => const {'path', 'offset', 'limit', 'sort'},
    'Grep' || 'Glob' => const {'path', 'pattern'},
    'Replace' => const {'path', 'pattern', 'replacement'},
    'Search' || 'WebSearch' => const {'query'},
    'WebFetch' => const {'url'},
    'GraphSearch' => const {'type', 'id', 'entity_type', 'entity_id', 'depth'},
    'Create' => const {
      'path',
      'fields',
      'source_type',
      'source_id',
      'target_type',
      'target_id',
    },
    _ => const <String>{},
  };
  return {
    if (call.targetPath != null) 'path': call.targetPath,
    if (keys.isNotEmpty) ..._select(call.argumentsPreview, keys),
  };
}

Map<String, dynamic>? codemodeRowResult(AiNestedToolCall call) =>
    call.source == 'mcp'
    ? _select(call.resultPreview, const {
        'mcp_progress',
        'executionState',
        'ok',
      })
    : call.toolName == 'Replace'
    ? _select(call.resultPreview, const {'matched_fields', 'applied_fields'})
    : null;

Map<String, dynamic> _select(String source, Set<String> keys) {
  try {
    return _SummaryReader(source).read(keys);
  } on FormatException {
    // 历史预览可能被截断；与完整详情的解码失败行为保持一致。
    return const {};
  }
}

/// 只解码被选中的标量和 Create.fields 摘要，不构造未选中值的 String/List/Map。
/// 跳过字符串时直接寻找未转义的结束引号，大段正文不会复制到摘要中。
class _SummaryReader {
  _SummaryReader(this.source);

  final String source;
  int offset = 0;

  Map<String, dynamic> read(Set<String> keys) {
    final value = _object(keys);
    _whitespace();
    if (offset != source.length) {
      throw const FormatException('Trailing JSON');
    }
    return value;
  }

  Map<String, dynamic> _object(Set<String> keys) {
    _expect(123);
    final result = <String, dynamic>{};
    _whitespace();
    if (_take(125)) {
      return result;
    }
    while (offset < source.length) {
      _whitespace();
      final start = offset;
      _string();
      final key = jsonDecode(source.substring(start, offset)) as String;
      _expect(58);
      _whitespace();
      if (keys.contains(key) && key == 'mcp_progress' && _at(123)) {
        result[key] = _object(const {'progress', 'total', 'message'});
      } else if (keys.contains(key) && key == 'fields' && _at(123)) {
        result[key] = _object(const {
          'title',
          'name',
          'source_type',
          'source_id',
          'target_type',
          'target_id',
        });
      } else {
        final valueStart = offset;
        final scalar = !_at(123) && !_at(91);
        _skipValue();
        if (keys.contains(key) && scalar) {
          result[key] = jsonDecode(source.substring(valueStart, offset));
        }
      }
      _whitespace();
      if (_take(125)) {
        return result;
      }
      _expect(44);
    }
    throw const FormatException('Unterminated object');
  }

  void _skipValue() {
    if (_at(34)) {
      _string();
      return;
    }
    if (_at(123) || _at(91)) {
      // 显式栈避免深层详情导致递归调用栈增长，只保存括号类型。
      final closing = <int>[];
      do {
        if (offset >= source.length) {
          throw const FormatException('Unterminated value');
        }
        final char = source.codeUnitAt(offset);
        if (char == 34) {
          _string();
          continue;
        }
        offset++;
        if (char == 123 || char == 91) {
          closing.add(char == 123 ? 125 : 93);
        } else if (char == 125 || char == 93) {
          if (closing.removeLast() != char) {
            throw const FormatException('Mismatched bracket');
          }
        }
      } while (closing.isNotEmpty);
      return;
    }
    final start = offset;
    while (offset < source.length) {
      final char = source.codeUnitAt(offset);
      if (char <= 32 || char == 44 || char == 125 || char == 93) {
        break;
      }
      offset++;
    }
    if (start == offset) {
      throw const FormatException('Missing value');
    }
  }

  void _string() {
    if (!_take(34)) {
      throw const FormatException('Expected string');
    }
    while (offset < source.length) {
      final end = source.indexOf('"', offset);
      if (end < 0) {
        break;
      }
      var backslashes = 0;
      for (var i = end - 1; i >= offset && source.codeUnitAt(i) == 92; i--) {
        backslashes++;
      }
      offset = end + 1;
      if (backslashes.isEven) {
        return;
      }
    }
    throw const FormatException('Unterminated string');
  }

  void _whitespace() {
    while (offset < source.length && source.codeUnitAt(offset) <= 32) {
      offset++;
    }
  }

  bool _at(int char) =>
      offset < source.length && source.codeUnitAt(offset) == char;

  bool _take(int char) {
    if (!_at(char)) {
      return false;
    }
    offset++;
    return true;
  }

  void _expect(int char) {
    _whitespace();
    if (!_take(char)) {
      throw const FormatException('Unexpected JSON token');
    }
  }
}
