// 职责: 管理单次 FJS 执行、受限 JSON 桥接、宿主预算和主动关闭。
// 关联文件:
//   lib/shared/services/ai/codemode/prelude.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/services/ai/tool_error_normalize.dart
//   third/fjs/lib/fjs.dart
import 'dart:async';
import '../../javascript.dart';
import 'dart:convert';

import 'package:fjs/fjs.dart';

import '../../../agent/agent_tool_dispatcher.dart';
import '../tool_error_normalize.dart' show sanitizeCodemodeJsErrorMessage;
import 'prelude.dart';

/// Host-only limits. Scripts cannot choose or change them.
class CodemodeRuntimeLimits {
  const CodemodeRuntimeLimits({
    this.sourceBytes = 64 * 1024,
    this.heapBytes = 64 * 1024 * 1024,
    this.stackBytes = 1024 * 1024,
    this.executionTime = const Duration(seconds: 180),
    this.inputBytes = 256 * 1024,
    this.outputBytes = 128 * 1024,
    this.outputFrames = 1024,
  });

  final int sourceBytes;
  final int heapBytes;
  final int stackBytes;
  final Duration executionTime;
  final int inputBytes;
  final int outputBytes;
  final int outputFrames;
}

class CodemodeRuntimeResult {
  const CodemodeRuntimeResult({
    required this.output,
    required this.callCount,
    required this.completedCount,
    required this.failedCount,
    this.hasReturn = false,
    this.returnValue,
    this.errorCode,
    this.toolError,
    this.jsErrorMessage,
    this.diagnostics = const {},
  });

  final List<Object?> output;
  final int callCount;
  final int completedCount;
  final int failedCount;
  final bool hasReturn;
  final Object? returnValue;
  final String? errorCode;
  final Map<String, dynamic>? toolError;

  /// 脱敏后提供给模型纠错，并通过 metadata 保留匿名上报所需的诊断。
  final String? jsErrorMessage;
  final Map<String, dynamic> diagnostics;
  bool get ok => errorCode == null;

  Map<String, dynamic> toJson() {
    final message = sanitizeCodemodeJsErrorMessage(jsErrorMessage);
    return {
      'ok': ok,
      'output': output,
      if (hasReturn) 'return_value': returnValue,
      'call_count': callCount,
      'completed_count': completedCount,
      'failed_count': failedCount,
      'diagnostics': diagnostics,
      if (message != null) ...{
        'js_error_message': message,
        '_metadata': {'codemode_js_error': message},
      },
      if (errorCode != null) ...{
        'error_code': errorCode,
        'error': codemodeErrorMessage(errorCode!),
        if (toolError != null) 'tool_error': toolError,
        if (errorCode == 'user_cancelled') 'cancelled': true,
      },
    };
  }
}

String codemodeErrorMessage(String code) => switch (code) {
  'user_cancelled' => 'Script execution was stopped.',
  'codemode_invalid_input' => 'Provide JavaScript and valid JSON values.',
  'codemode_tool_forbidden' => 'This tool or bridge request is not permitted.',
  'codemode_timeout' => 'Script execution exceeded its time limit.',
  'codemode_memory_limit' => 'Script execution exceeded its memory limit.',
  'codemode_resource_limit' =>
    'Script execution exceeded a resource limit. Reduce the work or output.',
  'codemode_script_error' =>
    'JavaScript execution failed. Check the script and its inputs.',
  _ => 'The script runtime could not complete execution.',
};

/// A single-use runtime. Completion means both eval and close have settled.
/// The caller owns tool futures (especially writes) independently of native
/// Promise cancellation, and must settle their effects before final delivery.
class FjsRuntime {
  final Completer<void> _settled = Completer<void>();
  JsEngine? _engine;
  Future<void>? _closing;
  String? _failure;
  bool _started = false;
  bool _accepting = true;
  bool _terminationNotified = false;
  void Function(String? errorCode)? _onTerminate;

  Future<void> get settled => _settled.future;

  void cancel({String errorCode = 'user_cancelled'}) {
    _failure ??= errorCode;
    _stopAccepting();
    // Observe failures here; run() owns their classification and settlement.
    unawaited(_close().catchError((Object _) {}));
  }

  void _stopAccepting() {
    _accepting = false;
    if (!_terminationNotified) {
      _terminationNotified = true;
      _onTerminate?.call(_failure);
    }
  }

  Future<void> _close() {
    final engine = _engine;
    if (engine == null) {
      return Future<void>.value();
    }
    return _closing ??= engine.close();
  }

  Future<CodemodeRuntimeResult> run({
    required String code,
    required List<ToolDef> tools,
    required Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> input,
    )
    executeTool,
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> input,
    )?
    discover,
    bool Function(String name)? isDynamicTool,
    AgentCancellationToken? cancellationToken,
    String Function()? cancellationErrorCode,
    void Function(String? errorCode)? onTerminate,
    void Function(String name, Map<String, dynamic> input, String errorCode)?
    onRejectedTool,
    CodemodeRuntimeLimits limits = const CodemodeRuntimeLimits(),
  }) async {
    if (_started) {
      throw StateError('FjsRuntime is single-use');
    }
    _started = true;
    _onTerminate = onTerminate;
    var evaluating = false;
    var calls = 0;
    var completed = 0;
    var failed = 0;
    var outputBytes = 0;
    var outputSequence = 0;
    var maxInputBytes = 0;
    var returnBytes = 0;
    var pendingToolCalls = 0;
    var stage = 'initializing';
    String? lastTool;
    final watch = Stopwatch()..start();
    final diagnostics = <String, dynamic>{};
    void diagnose(String reason, {int? limit, int? observed}) {
      if (diagnostics.containsKey('failure_reason')) {
        return;
      }
      diagnostics.addAll({
        'failure_stage': stage,
        'failure_reason': reason,
        'limit': ?limit,
        'observed': ?observed,
      });
    }

    final output = <Object?>[];
    Object? returnValue;
    Map<String, dynamic>? toolError;
    String? jsErrorMessage;
    var hasReturn = false;
    final allowed = tools.map((tool) => tool.name).toSet();
    Timer? deadline;
    void Function()? removeCancellation;

    JsResult reply(Map<String, dynamic> value) =>
        JsResult.ok(JsValue.string(jsonEncode(value)));
    JsResult reject(String code) => reply({'ok': false, 'error_code': code});
    Future<JsResult> bridge(JsValue value) async {
      Map<String, dynamic>? request;
      var dispatched = false;
      var audited = false;
      JsResult terminate(String code) {
        if (!dispatched && !audited && request?['kind'] == 'tool') {
          audited = true;
          var input = <String, dynamic>{};
          final rawInput = request?['input'];
          if (rawInput is String &&
              utf8.encode(rawInput).length <= limits.inputBytes) {
            try {
              final parsed = jsonDecode(rawInput);
              if (parsed is Map<String, dynamic>) {
                input = parsed;
              }
            } on FormatException {
              /* The rejection itself is the diagnostic. */
            }
          }
          onRejectedTool?.call(
            request?['tool'] is String
                ? request!['tool'] as String
                : '<invalid>',
            input,
            code,
          );
        }
        cancel(errorCode: code);
        return reject(code);
      }

      if (!_accepting) {
        return reject(_failure ?? 'user_cancelled');
      }
      try {
        if (value is! JsValue_String) {
          return terminate('codemode_tool_forbidden');
        }
        // Nested JSON is transported as a string, so reject before decoding it.
        final raw = value.field0;
        final bridgeBytes = utf8.encode(raw).length;
        if (bridgeBytes > limits.inputBytes * 6 + 1024) {
          diagnose(
            'bridge_bytes',
            limit: limits.inputBytes * 6 + 1024,
            observed: bridgeBytes,
          );
          return terminate('codemode_resource_limit');
        }
        final message = jsonDecode(raw);
        if (message is! Map<String, dynamic>) {
          return terminate('codemode_tool_forbidden');
        }
        request = message;
        final kind = message['kind'];
        if (kind == 'output') {
          final error = message['error_code'];
          if (error != null) {
            final detail = message['diagnostics'];
            if (detail is Map && !diagnostics.containsKey('failure_reason')) {
              final observed = detail['observed'];
              if (observed is int && observed >= 0) {
                if (detail['failure_stage'] == 'return_value' &&
                    detail['failure_reason'] == 'output_bytes') {
                  returnBytes = observed;
                }
                if (detail['failure_reason'] == 'input_bytes' &&
                    observed > maxInputBytes) {
                  maxInputBytes = observed;
                }
              }
              // Only fixed labels and numeric counters survive anonymous sanitization.
              for (final key in [
                'failure_stage',
                'failure_reason',
                'limit',
                'observed',
              ]) {
                if (detail.containsKey(key)) {
                  diagnostics[key] = detail[key];
                }
              }
            }
            return terminate(switch (error) {
              'codemode_resource_limit' => 'codemode_resource_limit',
              'codemode_tool_forbidden' => 'codemode_tool_forbidden',
              _ => 'codemode_invalid_input',
            });
          }
          if (!_hasKeys(message, {'kind', 'sequence', 'text'}) ||
              message['sequence'] != outputSequence + 1 ||
              message['text'] is! String) {
            return terminate('codemode_tool_forbidden');
          }
          stage = 'output';
          final text = message['text'] as String;
          final size = utf8.encode(text).length;
          if (size + outputBytes > limits.outputBytes) {
            diagnose(
              'output_bytes',
              limit: limits.outputBytes,
              observed: size + outputBytes,
            );
            return terminate('codemode_resource_limit');
          }
          if (output.length >= limits.outputFrames) {
            diagnose(
              'output_frames',
              limit: limits.outputFrames,
              observed: output.length + 1,
            );
            return terminate('codemode_resource_limit');
          }
          final decoded = jsonDecode(text);
          _validateJson(decoded);
          output.add(decoded);
          outputBytes += size;
          outputSequence++;
          stage = 'script';
          return reply({'ok': true, 'result': null});
        }
        if (kind == 'discover' && discover != null) {
          if (!_hasKeys(message, {'kind', 'method', 'input'}) ||
              message['method'] is! String ||
              message['input'] is! String) {
            return terminate('codemode_invalid_input');
          }
          final encoded = message['input'] as String;
          if (utf8.encode(encoded).length > limits.inputBytes) {
            return terminate('codemode_resource_limit');
          }
          final arguments = jsonDecode(encoded);
          if (arguments is! Map<String, dynamic>) {
            return terminate('codemode_invalid_input');
          }
          try {
            final result = await discover(
              message['method'] as String,
              arguments,
            );
            if (utf8.encode(jsonEncode(result)).length > 512 * 1024) {
              return reply({
                'ok': false,
                'error_code': 'mcp_definition_too_large',
                'error': 'Discovery result exceeds bridge budget.',
              });
            }
            return reply({'ok': true, 'result': result});
          } catch (error) {
            return reply({
              'ok': false,
              'error_code': 'mcp_discovery_error',
              'error': error.toString(),
            });
          }
        }
        if (kind != 'tool') {
          return terminate('codemode_tool_forbidden');
        }
        stage = 'tool_input';
        calls++;
        final dynamicTool =
            message['tool'] is String &&
            isDynamicTool?.call(message['tool'] as String) == true;
        if (!_hasKeys(message, {
              'kind',
              'tool',
              'input',
              if (dynamicTool) 'options',
            }) ||
            message['tool'] is! String ||
            (!dynamicTool && !allowed.contains(message['tool']))) {
          failed++;
          return terminate('codemode_tool_forbidden');
        }
        lastTool = message['tool'] as String;
        final input = message['input'];
        if (input is! String) {
          failed++;
          return terminate('codemode_invalid_input');
        }
        final inputSize = utf8.encode(input).length;
        if (inputSize > maxInputBytes) {
          maxInputBytes = inputSize;
        }
        if (inputSize > limits.inputBytes) {
          diagnose(
            'input_bytes',
            limit: limits.inputBytes,
            observed: inputSize,
          );
          return terminate('codemode_resource_limit');
        }
        final decoded = jsonDecode(input);
        if (decoded is! Map<String, dynamic>) {
          failed++;
          return terminate('codemode_invalid_input');
        }
        _validateJson(decoded);
        dispatched = true;
        stage = 'tool_execution';
        pendingToolCalls++;
        late Map<String, dynamic> result;
        try {
          if (dynamicTool) {
            final options = jsonDecode(message['options'] as String);
            if (options is! Map<String, dynamic> || options.isNotEmpty) {
              return reject('codemode_invalid_input');
            }
          }
          result = await executeTool(message['tool'] as String, decoded);
        } finally {
          pendingToolCalls--;
        }
        if (!_accepting) {
          return reject(_failure ?? 'user_cancelled');
        }
        stage = 'tool_result';
        _validateJson(result);
        if (result['ok'] == false || result['cancelled'] == true) {
          failed++;
          final error = result['error_code'];
          // Only forward the tool's public recovery fields, never host exceptions
          // or UI metadata. Keep the error code stable for existing scripts.
          // error_code=exception wraps a raw host exception in `error`.
          final public = error != 'exception';
          stage = 'script';
          return reply({
            'ok': false,
            'error_code': error is String ? error : 'tool_failed',
            if (public && result['error'] is String) 'error': result['error'],
            if (public && result['hint'] is String) 'hint': result['hint'],
            if (public && result['recovery'] != null)
              'recovery': result['recovery'],
            if (dynamicTool) 'result': result,
          });
        }
        completed++;
        stage = 'script';
        return reply({'ok': true, 'result': result});
      } on FormatException {
        diagnose('json_value');
        return terminate('codemode_invalid_input');
      } catch (_) {
        failed++;
        diagnose('bridge_failure');
        // Tool business exceptions are normalized by the Agent execution path;
        // an unexpected bridge failure must not leak raw host diagnostics.
        return terminate('codemode_runtime_failed');
      }
    }

    try {
      if (utf8.encode(code).length > limits.sourceBytes) {
        diagnose(
          'source_bytes',
          limit: limits.sourceBytes,
          observed: utf8.encode(code).length,
        );
        _failure = 'codemode_invalid_input';
      } else {
        removeCancellation = cancellationToken?.onCancel(
          () => cancel(
            errorCode: cancellationErrorCode?.call() ?? 'user_cancelled',
          ),
        );
        deadline = Timer(limits.executionTime, () {
          if (pendingToolCalls > 0) {
            stage = 'tool_execution';
          }
          diagnose(
            'execution_time',
            limit: limits.executionTime.inMilliseconds,
            observed: watch.elapsedMilliseconds,
          );
          cancel(errorCode: 'codemode_timeout');
        });
        await initializeJavascript();
        if (_accepting) {
          _engine = await JsEngine.create(
            builtins: JsBuiltinOptions.none(),
            runtimeOptions: JsEngineRuntimeOptions(
              memoryLimit: BigInt.from(limits.heapBytes),
              maxStackSize: BigInt.from(limits.stackBytes),
            ),
          );
          if (_accepting) {
            await _engine!.init(bridge: bridge);
            if (_accepting) {
              evaluating = true;
              stage = 'script';
              final result = await _engine!.eval(
                source: JsCode.code(
                  codemodePrelude(
                    code,
                    [for (final tool in tools) tool.name],
                    inputBytes: limits.inputBytes,
                    outputBytes: limits.outputBytes,
                  ),
                ),
              );
              if (_failure == null) {
                stage = 'return_value';
                if (result is! JsValue_String ||
                    utf8.encode(result.field0).length >
                        limits.outputBytes + 1024) {
                  diagnose(
                    'result_envelope',
                    limit: limits.outputBytes + 1024,
                    observed: result is JsValue_String
                        ? utf8.encode(result.field0).length
                        : null,
                  );
                  _failure = 'codemode_resource_limit';
                } else {
                  final envelope =
                      jsonDecode(result.field0) as Map<String, dynamic>;
                  if (envelope['kind'] != 'codemode-result') {
                    _failure = 'codemode_runtime_failed';
                  } else if (envelope['ok'] != true) {
                    _failure = 'codemode_script_error';
                    final details = envelope['tool_error'];
                    if (details is Map<String, dynamic>) {
                      stage = 'tool_error';
                      _validateJson(details);
                      if (utf8.encode(jsonEncode(details)).length +
                              outputBytes >
                          limits.outputBytes) {
                        diagnose(
                          'output_bytes',
                          limit: limits.outputBytes,
                          observed:
                              utf8.encode(jsonEncode(details)).length +
                              outputBytes,
                        );
                        _failure = 'codemode_resource_limit';
                      } else {
                        diagnose('tool_failure');
                        diagnostics['tool_error_code'] = details['error_code'];
                        toolError = Map.unmodifiable(details);
                      }
                    }
                  } else if (envelope['has_return'] == true) {
                    final value = envelope['result'];
                    _validateJson(value);
                    returnBytes = utf8.encode(jsonEncode(value)).length;
                    if (returnBytes + outputBytes > limits.outputBytes) {
                      diagnose(
                        'output_bytes',
                        limit: limits.outputBytes,
                        observed: returnBytes + outputBytes,
                      );
                      _failure = 'codemode_resource_limit';
                    } else {
                      returnValue = value;
                      hasReturn = true;
                    }
                  }
                }
              }
            }
          }
        }
      }
    } on JsError catch (error) {
      if (_failure == null) {
        if (evaluating) {
          stage = 'script';
        }
        diagnose(
          switch (error) {
            JsError_MemoryLimit() => 'heap_bytes',
            JsError_StackOverflow() => 'stack_bytes',
            JsError_Syntax() => 'syntax',
            JsError_Type() => 'type',
            JsError_Reference() => 'reference',
            _ => 'runtime',
          },
          limit: switch (error) {
            JsError_MemoryLimit() => limits.heapBytes,
            JsError_StackOverflow() => limits.stackBytes,
            _ => null,
          },
        );
        if (evaluating) {
          jsErrorMessage = sanitizeCodemodeJsErrorMessage(switch (error) {
            JsError_Syntax(:final message) => message,
            JsError_Type(:final field0) ||
            JsError_Reference(:final field0) ||
            JsError_Runtime(:final field0) => field0,
            _ => null,
          });
        }
      }
      _failure ??= switch (error) {
        JsError_MemoryLimit() => 'codemode_memory_limit',
        JsError_StackOverflow() => 'codemode_resource_limit',
        JsError_Syntax() => 'codemode_script_error',
        JsError_Runtime() ||
        JsError_Type() ||
        JsError_Reference() when evaluating => 'codemode_script_error',
        _ => 'codemode_runtime_failed',
      };
    } catch (_) {
      _failure ??= 'codemode_runtime_failed';
    } finally {
      deadline?.cancel();
      removeCancellation?.call();
      _stopAccepting();
      try {
        await _close();
      } catch (_) {
        _failure ??= 'codemode_runtime_failed';
      }
      _settled.complete();
    }
    return CodemodeRuntimeResult(
      output: List.unmodifiable(output),
      callCount: calls,
      completedCount: completed,
      failedCount: failed,
      hasReturn: hasReturn,
      returnValue: returnValue,
      errorCode: _failure,
      toolError: toolError,
      jsErrorMessage: jsErrorMessage,
      diagnostics: {
        ...diagnostics,
        'elapsed_ms': watch.elapsedMilliseconds,
        'output_bytes': outputBytes,
        'output_frames': output.length,
        'return_bytes': returnBytes,
        'max_input_bytes': maxInputBytes,
        'output_limit_bytes': limits.outputBytes,
        'output_limit_frames': limits.outputFrames,
        'input_limit_bytes': limits.inputBytes,
        'execution_limit_ms': limits.executionTime.inMilliseconds,
        'last_tool': ?lastTool,
      },
    );
  }
}

bool _hasKeys(Map<String, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);

/// Validate both sides of the native bridge without invoking toJson methods.
void _validateJson(Object? value, [int depth = 0, Set<Object>? ancestors]) {
  if (depth > 64) {
    throw const FormatException('JSON depth limit');
  }
  if (value == null || value is String || value is bool) {
    return;
  }
  if (value is num && value.isFinite) {
    return;
  }
  final seen = ancestors ?? Set<Object>.identity();
  if (value is! List && value is! Map<String, dynamic> || !seen.add(value)) {
    throw const FormatException('Only JSON values are allowed');
  }
  final Iterable<Object?> children = value is List
      ? value.cast<Object?>()
      : (value as Map<String, dynamic>).values;
  for (final child in children) {
    _validateJson(child, depth + 1, seen);
  }
  seen.remove(value);
}
