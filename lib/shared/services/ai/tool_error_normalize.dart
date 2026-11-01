// 职责: 统一 AI 工具结果分类与 ok，补齐失败诊断字段供模型、trace 与 UI 消费
//        以及为匿名工具错误事件归一化诊断字段（exception_message / stack_top / tool_input）
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/models/agent_skill.dart
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/agent/agent.dart (诊断字段附加到 result map)

import 'dart:convert';

import '../../models/agent_skill.dart';
import '../../utils/utf16_safe_text.dart';
import 'codemode/tool.dart';

/// AI 工具业务失败的 `error_code`，语义对齐 gRPC 标准状态码。
///
/// 只表达失败大类，供模型和 codemode 脚本按类分支；具体原因写在 `error`，
/// 下一步写在 `hint` / `recovery`。框架级的取消、拦截与 codemode 运行时错误
/// 不在此列。
enum ToolErrorCode {
  /// 参数缺失、格式或取值不合法，路径语法错误。
  invalid_argument,

  /// 调用目标资源不存在；输入字段中的无效资源引用归为 invalid_argument。
  not_found,

  /// 要创建或改名成的目标已存在。
  already_exists,

  /// 并发修改冲突，刷新后重试。
  conflict,

  /// 资源当前状态不满足操作前提，如删除非空文件夹、实体仍被引用、
  /// old_text 与当前内容不匹配。
  failed_precondition,

  /// 目标被用户锁定（如章节已发布），需用户在界面解除后才能修改；不要重试或绕过。
  locked,

  /// 需要用户先登录。
  unauthenticated,

  /// 目标只读或当前模式无权操作。
  permission_denied,

  /// 该资源或路径不支持此操作，应换工具或换路径。
  unsupported,

  /// 内容或匹配范围超出上限。
  resource_exhausted,

  /// 依赖的服务、会话或配置当前不可用。
  unavailable,

  /// 执行过程失败。
  internal,
}

/// 清洗 [runtimeType] 为可 GROUP BY 的安全标签（去掉泛型尖括号等）。
///
/// 用于匿名工具错误事件的 exception_type 字段，仅暴露异常类型名，
/// 不包含 exception message 内容。
String safeErrorTypeName(Object error) {
  final cleaned = error.runtimeType.toString().replaceAll(
    RegExp(r'[^A-Za-z0-9_]'),
    '',
  );
  return cleaned.isEmpty ? 'Object' : cleaned;
}

/// 清洗 trace / error 标签为可 GROUP BY 的 snake 安全串。
String sanitizeToolTraceToken(String? raw) {
  if (raw == null || raw.isEmpty) {
    return '';
  }
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return cleaned;
}

/// 从工具 path 提取匿名 collection（如 `/chapters/x/title` → `chapters`）。
String? collectionFromToolPath(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) {
    return null;
  }
  if (parts.first.startsWith('.')) {
    // `.agents/rules/...` → agents_rules
    final joined = parts.take(2).join('_');
    final token = sanitizeToolTraceToken(joined);
    return token.isEmpty ? null : token;
  }
  final token = sanitizeToolTraceToken(parts.first);
  return token.isEmpty ? null : token;
}

/// 从结果或 input 解析 path。成功响应把权威路径写在顶层 `path`，失败响应可能没有。
String? toolResultPath(
  Map<String, dynamic> result, [
  Map<String, dynamic>? input,
]) {
  final direct = result['path'];
  if (direct is String && direct.isNotEmpty) {
    return direct;
  }
  final inputPath = input?['path'];
  if (inputPath is String && inputPath.isNotEmpty) {
    return inputPath;
  }
  return null;
}

/// 从 `Invalid novel status: "..."` 类文案解析枚举字段名。
String? inferEnumField(String message) {
  final match = RegExp(r'^Invalid (.+):').firstMatch(message.trim());
  if (match == null) {
    return null;
  }
  final enumField = sanitizeToolTraceToken(match.group(1)!.trim());
  return enumField.isEmpty ? null : enumField;
}

String? toolResultErrorMessage(Map<String, dynamic> result) {
  final message = result['error']?.toString();
  return message == null || message.trim().isEmpty ? null : message;
}

/// 只检查顶层协议；正文中的同名业务键不参与调用状态判断。
bool toolResultIsSuccess(Map<String, dynamic> result) =>
    result['ok'] != false &&
    result['cancelled'] != true &&
    result['skipped'] != true &&
    result['rejected'] != true &&
    toolResultErrorMessage(result) == null;

/// 归一化工具失败 map：补齐 `error_code` / `collection` / `enum_field`。
///
/// 成功补齐 ok；失败保留已有错误码与业务字段，取消和跳过保持原语义。
Map<String, dynamic> normalizeToolFailureResult(
  Map<String, dynamic> result, {
  Map<String, dynamic>? input,
}) {
  if (result['executionState'] is String && result['ok'] is bool) {
    return result;
  }
  if (toolResultIsSuccess(result)) {
    return result['ok'] == true ? result : {...result, 'ok': true};
  }

  final out = Map<String, dynamic>.from(result);
  if (out['skipped'] == true) {
    out['ok'] = false;
    out['error_code'] ??= 'loop_skipped';
    return out;
  }

  if (out['cancelled'] == true) {
    out['ok'] = false;
    final existingCode = out['error_code'];
    if (existingCode is! String || existingCode.isEmpty) {
      out['error_code'] = 'user_cancelled';
    }
    out['error'] ??= 'User cancelled';
    return out;
  }

  out['ok'] = false;
  final enumField = inferEnumField(out['error']?.toString() ?? '');
  if (enumField != null) {
    out['enum_field'] ??= enumField;
  }
  final code = out['error_code'];
  if (code is! String || code.isEmpty) {
    out['error_code'] = ToolErrorCode.internal.name;
  }

  if (out['collection'] == null) {
    final path = toolResultPath(out, input);
    final collection = collectionFromToolPath(path);
    if (collection != null) {
      out['collection'] = collection;
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 诊断字段清洗 — 用于匿名工具错误事件
// ---------------------------------------------------------------------------

/// 异常 message 最大长度（截断到 500 字符）。
const int _maxExceptionMessageLen = 500;

/// stack top 帧数。
const int _maxStackFrames = 5;

/// Create 诊断中单个字段值的最大长度。
const int _maxToolInputStringLen = 100;

/// 清洗异常 message：截断到 [_maxExceptionMessageLen] 字符。
///
/// 最小清洗策略：仅截断长度，不剥离路径或用户内容。
/// 调用方需知晓 exception 文本可能含文件路径或少量用户内容。
String sanitizeExceptionMessage(Object error) {
  final raw = error.toString();
  if (raw.length <= _maxExceptionMessageLen) {
    return raw;
  }
  return '${raw.substring(0, _maxExceptionMessageLen)}...[truncated]';
}

/// 提取 stack trace 顶部 [_maxStackFrames] 帧，每帧格式 `file:line:column`。
///
/// 路径转 basename 避免泄露用户主目录；Dart stack frame 格式示例：
/// `#0  foo (package:mymodule/src/file.dart:42:10)`
String sanitizeStackTop(
  StackTrace stackTrace, {
  int maxFrames = _maxStackFrames,
}) {
  final lines = stackTrace.toString().split('\n');
  final frames = <String>[];
  final framePattern = RegExp(r'\((.*?):(\d+)(?::(\d+))?\)');
  for (final line in lines) {
    if (frames.length >= maxFrames) break;
    final trimmed = line.trim();
    if (trimmed.isEmpty) break;
    final match = framePattern.firstMatch(trimmed);
    if (match == null) continue;
    final fullPath = match.group(1)!;
    final lineNo = match.group(2)!;
    final colNo = match.group(3);
    // 路径转 basename：取最后一段，去掉 package: 前缀的路径部分但保留包名
    final basename = fullPath.split('/').last;
    frames.add(
      colNo != null ? '$basename:$lineNo:$colNo' : '$basename:$lineNo',
    );
  }
  return frames.join('\n');
}

/// 清洗失败工具调用的诊断上下文。
///
/// Create 失败事件保留路径、顶层参数名（top_level_keys）、字段名与截断后的
/// 字段值：top_level_keys 用于区分模型遗漏 `fields`、传入扁平字段或 `fields`
/// 形状错误，字段值用于诊断枚举与资源定位问题；字符串仍会截断，避免单个事件
/// 无限膨胀。Write 只保留有界的参数形状，Edit 只保留匹配诊断；二者不收集正文。
String sanitizeToolInput(
  String toolName,
  Map<String, dynamic> input, {
  Map<String, dynamic>? result,
}) {
  final path = input['path'];
  final collection = path is String ? collectionFromToolPath(path) : null;
  final sanitized = switch (toolName) {
    'Codemode' => codemodeSafeDiagnostics(input, result),
    'AgentSkill' => <String, dynamic>{
      'agent_skill_name': agentSkillNameFromInput(input),
    },
    'Create' => <String, dynamic>{
      ...?(collection == null ? null : {'collection': collection}),
      if (path is String && path.isNotEmpty) 'path': path,
      'top_level_keys': input.keys.map((key) => key.toString()).toList(),
      'fields_shape': _diagnosticValueShape(input['fields']),
      'field_names': (input['fields'] is Map)
          ? (input['fields'] as Map).keys.map((key) => key.toString()).toList()
          : const <String>[],
      if (input['fields'] is Map)
        'fields': _truncateDiagnosticValue(input['fields'] as Map),
      // fields 是字符串时，形状本身就是故障原因（模型把 JSON 塞进了字符串，
      // 且未能解析）。保留截断前缀与长度，否则 invalid_fields 无从归因。
      if (input['fields'] is String) ...<String, dynamic>{
        'fields_raw_prefix': _truncateDiagnosticValue(input['fields']),
        'fields_raw_length': (input['fields'] as String).length,
      },
    },
    'Edit' => <String, dynamic>{
      ...?(collection == null ? null : {'collection': collection}),
      'field': _fieldFromToolPath(path),
      // invalid_path 只能靠原始 path 归因；非字符串时记录形状。
      if (path is String)
        'path': _truncateDiagnosticValue(path)
      else
        'path_shape': _diagnosticValueShape(path),
      ..._safeEditDiagnostics(switch (result?['_metadata']) {
        final Map meta => meta['edit_diagnostics'],
        _ => null,
      }),
    },
    'Write' => <String, dynamic>{
      ...?(collection == null ? null : {'collection': collection}),
      'field': _fieldFromToolPath(path),
      'top_level_keys': _diagnosticNames(input.keys),
      'fields_shape': input.containsKey('fields')
          ? _writeValueShape(input['fields'])
          : 'absent',
      'value_shape': input.containsKey('value')
          ? _writeValueShape(input['value'])
          : 'absent',
      if (input['fields'] case final Map fields) ...{
        'field_names': _diagnosticNames(fields.keys),
        'field_shapes': {
          for (final entry in fields.entries.take(32))
            _diagnosticName(entry.key): _writeValueShape(entry.value),
        },
        'field_count': fields.length,
      },
      for (final key in ['missing_fields', 'required_fields'])
        if (result?[key] case final List names) key: _diagnosticNames(names),
    },
    _ => <String, dynamic>{
      ...?(collection == null ? null : {'collection': collection}),
    },
  };
  return jsonEncode(sanitized);
}

String _diagnosticName(Object? name) {
  final text = name.toString();
  return RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,63}$').hasMatch(text)
      ? text
      : '<invalid>';
}

String _writeValueShape(Object? value) => switch (value) {
  null => 'null',
  String() when value.isEmpty => 'empty_string',
  _ => _diagnosticValueShape(value),
};

List<String> _diagnosticNames(Iterable<dynamic> names) =>
    names.take(32).map(_diagnosticName).toList();

Map<String, Object> _safeEditDiagnostics(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    if (const {
      'empty_source',
      'line_endings',
      'outer_whitespace',
      'first_line_diverged',
      'no_matching_anchor',
    }.contains(value['match_reason']))
      'match_reason': value['match_reason'] as String,
    for (final key in ['source_length', 'old_text_length', 'divergence_offset'])
      if (value[key] is int && (value[key] as int) >= 0) key: value[key] as int,
  };
}

String _diagnosticValueShape(Object? value) {
  if (value == null) {
    return 'absent';
  }
  return switch (value) {
    Map() => 'object',
    String() => 'string',
    List() => 'array',
    num() => 'number',
    bool() => 'boolean',
    _ => 'other',
  };
}

Object? _truncateDiagnosticValue(Object? value) {
  switch (value) {
    case String value:
      return value.length <= _maxToolInputStringLen
          ? value
          : '${value.substring(0, _maxToolInputStringLen)}...[truncated]';
    case List value:
      return value.map(_truncateDiagnosticValue).toList(growable: false);
    case Map value:
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _truncateDiagnosticValue(entry.value),
      };
    default:
      return value;
  }
}

String _fieldFromToolPath(Object? path) {
  if (path is! String) {
    return '';
  }
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return parts.length >= 3 ? parts.last : '';
}

/// Codemode 结构化诊断只保留计数和分类；JS 消息单独写入 exception_message。
Map<String, dynamic> codemodeSafeDiagnostics(
  Map<String, dynamic> input,
  Map<String, dynamic>? result,
) {
  final diagnostics = result?['diagnostics'];
  final phase = diagnostics is Map ? diagnostics['phase'] : null;
  return {
    'source_bytes': input['code'] is String
        ? utf8.encode(input['code'] as String).length
        : 0,
    for (final key in ['call_count', 'completed_count', 'failed_count'])
      if (result?[key] is int && (result![key] as int) >= 0) key: result[key],
    'phase': const {'queued', 'executing', 'finished'}.contains(phase)
        ? phase
        : 'finished',
    if (diagnostics is Map) ...{
      for (final key in [
        'elapsed_ms',
        'output_bytes',
        'output_frames',
        'return_bytes',
        'max_input_bytes',
        'output_limit_bytes',
        'output_limit_frames',
        'input_limit_bytes',
        'execution_limit_ms',
        'limit',
        'observed',
      ])
        if (diagnostics[key] is int &&
            (diagnostics[key] as int) >= 0 &&
            (diagnostics[key] as int) <= 9007199254740991)
          key: diagnostics[key],
      if (const {
        'initializing',
        'script',
        'tool_input',
        'tool_execution',
        'tool_result',
        'output',
        'return_value',
        'tool_error',
      }.contains(diagnostics['failure_stage']))
        'failure_stage': diagnostics['failure_stage'],
      if (const {
        'source_bytes',
        'input_bytes',
        'output_bytes',
        'output_frames',
        'bridge_bytes',
        'result_envelope',
        'json_depth',
        'json_value',
        'tool_failure',
        'heap_bytes',
        'stack_bytes',
        'execution_time',
        'bridge_failure',
        'syntax',
        'type',
        'reference',
        'runtime',
      }.contains(diagnostics['failure_reason']))
        'failure_reason': diagnostics['failure_reason'],
      if (ToolErrorCode.values.any(
        (code) => code.name == diagnostics['tool_error_code'],
      ))
        'tool_error_code': diagnostics['tool_error_code'],
      if (codemodeToolNames.contains(diagnostics['last_tool']))
        'last_tool': diagnostics['last_tool'],
    },
  };
}

Map<String, dynamic> codemodeAnonymousFailure(
  Map<String, dynamic>? result,
  Map<String, dynamic>? input,
) {
  const codes = {
    'codemode_invalid_input',
    'codemode_script_error',
    'codemode_timeout',
    'codemode_memory_limit',
    'codemode_resource_limit',
    'codemode_tool_forbidden',
    'codemode_runtime_failed',
    'codemode_busy',
    'user_cancelled',
  };
  final code = codes.contains(result?['error_code'])
      ? result!['error_code'] as String
      : 'codemode_runtime_failed';
  final metadata = result?['_metadata'];
  final message = code == 'codemode_script_error' && metadata is Map
      ? sanitizeCodemodeJsErrorMessage(metadata['codemode_js_error'])
      : null;
  return {
    'ok': false,
    'error_code': code,
    'error': code,
    'exception_type': 'CodemodeFailure',
    'exception_message': message ?? code,
    'stack_top': '',
    'tool_input': jsonEncode(
      codemodeSafeDiagnostics(input ?? const {}, result),
    ),
  };
}

/// 保留有界的 JS 消息首行，排除原生异常附带的堆栈、路径和常见凭证。
String? sanitizeCodemodeJsErrorMessage(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return null;
  }
  var message = raw.split(RegExp(r'[\r\n]')).first.trim();
  message = message
      .replaceAll(RegExp(r'''https?://[^\s"'<>]+'''), '<url>')
      .replaceAll(RegExp(r'''[A-Za-z]:[\\/][^\r\n"']+'''), '<path>')
      .replaceAll(
        RegExp(
          r'''/(?:Users|home|tmp|var|private|Volumes|mnt|etc|opt|usr|workspace)/[^\r\n"']+''',
        ),
        '<path>',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[^\s,;"\x27]+', caseSensitive: false),
        'Bearer <redacted>',
      )
      .replaceAllMapped(
        RegExp(
          r'''\b(api[_-]?key|authorization|password|secret|token)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
          caseSensitive: false,
        ),
        (match) => '${match[1]}=<redacted>',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}'), '<redacted>');
  if (message.isEmpty) {
    return null;
  }
  return message.length <= _maxExceptionMessageLen
      ? message
      : truncateUtf16Safe(message, _maxExceptionMessageLen - 3);
}
