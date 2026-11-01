// 职责: 执行单次 fjs 插件激活、工具调用或设置页操作，约束桥接、资源与取消。
// 关联文件:
//   lib/shared/services/plugins/host.dart
import 'dart:async';
import '../javascript.dart';
import 'dart:convert';
import 'package:fjs/fjs.dart';
import '../../agent/agent_tool_dispatcher.dart';
import '../../models/plugin/manifest.dart';
import 'prelude.dart';
import 'registry.dart';

class PluginExecutionError implements Exception {
  PluginExecutionError(this.code, this.message, {this.hostCode});
  final String code, message;
  final String? hostCode;
  @override
  String toString() => '$code: $message';
}

abstract interface class PluginExecutor {
  Future<List<Map<String, dynamic>>> activate(
    PluginManifest manifest,
    String code,
  );
  Future<Map<String, dynamic>> invoke(
    PluginManifest manifest,
    String code,
    List<Map<String, dynamic>> expected,
    String tool,
    Map<String, dynamic> input,
    String callId,
    AgentCancellationToken? cancellation,
  );

  /// 执行清单声明的设置页操作；插件未开启时也可执行。
  Future<Map<String, dynamic>> runAction(
    PluginManifest manifest,
    String code,
    String action,
    String callId,
    AgentCancellationToken? cancellation,
  );
}

typedef PluginHostCall =
    Future<Object?> Function(String method, Map<String, dynamic> args);

class PluginRuntime implements PluginExecutor {
  PluginRuntime({
    required this.hostCall,
    this.onStop,
    this.activationTimeout = const Duration(seconds: 5),
    this.callTimeout = const Duration(seconds: 60),
    this.actionTimeout = const Duration(seconds: 20),
  });
  final PluginHostCall hostCall;
  final void Function()? onStop;
  final Duration activationTimeout, callTimeout, actionTimeout;
  @override
  Future<List<Map<String, dynamic>>> activate(
    PluginManifest manifest,
    String code,
  ) async => (await _run(manifest, code)).definitions;
  @override
  Future<Map<String, dynamic>> invoke(
    PluginManifest manifest,
    String code,
    List<Map<String, dynamic>> expected,
    String tool,
    Map<String, dynamic> input,
    String callId,
    AgentCancellationToken? cancellation,
  ) async => (await _run(
    manifest,
    code,
    expected: expected,
    tool: tool,
    input: input,
    callId: callId,
    cancellation: cancellation,
  )).result!;
  @override
  Future<Map<String, dynamic>> runAction(
    PluginManifest manifest,
    String code,
    String action,
    String callId,
    AgentCancellationToken? cancellation,
  ) async => (await _run(
    manifest,
    code,
    action: action,
    callId: callId,
    cancellation: cancellation,
  )).result!;
  Future<
    ({List<Map<String, dynamic>> definitions, Map<String, dynamic>? result})
  >
  _run(
    PluginManifest manifest,
    String code, {
    List<Map<String, dynamic>>? expected,
    String? tool,
    String? action,
    Map<String, dynamic> input = const {},
    String callId = '',
    AgentCancellationToken? cancellation,
  }) async {
    if (utf8.encode(code).length > 2 * 1024 * 1024) {
      throw PluginExecutionError('plugin_error', 'Entry exceeds 2 MB');
    }
    if (utf8.encode(jsonEncode(input)).length > 256 * 1024) {
      throw PluginExecutionError('invalid_argument', 'Input exceeds 256 KB');
    }
    JsEngine? engine;
    Future<void>? closing;
    PluginExecutionError? failure;
    var accepting = true;
    final definitions = <Map<String, dynamic>>[];
    final actions = <String>{};
    Map<String, dynamic>? output;
    var receivedResult = false;
    var registering = true;
    Future<void> close() async {
      if (engine != null) {
        await (closing ??= engine.close());
      }
    }

    void stop(PluginExecutionError error) {
      failure ??= error;
      accepting = false;
      onStop?.call();
      unawaited(close().catchError((Object _) {}));
    }

    final remove = cancellation?.onCancel(
      () =>
          stop(PluginExecutionError('user_cancelled', 'Plugin call cancelled')),
    );
    final timer = Timer(
      action != null
          ? actionTimeout
          : (tool == null ? activationTimeout : callTimeout),
      () => stop(
        PluginExecutionError('plugin_timeout', 'Plugin execution timed out'),
      ),
    );
    try {
      await initializeJavascript();
      if (failure != null) {
        throw failure!;
      }
      engine = await JsEngine.create(
        builtins: JsBuiltinOptions.none(),
        runtimeOptions: JsEngineRuntimeOptions(
          memoryLimit: BigInt.from(64 * 1024 * 1024),
          maxStackSize: BigInt.from(1024 * 1024),
        ),
      );
      if (failure != null) {
        throw failure!;
      }
      await engine.init(
        bridge: (value) async {
          Map<String, dynamic> reply;
          try {
            if (!accepting) {
              throw failure ?? StateError('Execution closed');
            }
            if (value is! JsValue_String ||
                utf8.encode(value.field0).length > 2 * 1024 * 1024) {
              throw const FormatException('Invalid bridge message');
            }
            final message = jsonDecode(value.field0) as Map<String, dynamic>;
            switch (message['kind']) {
              case 'register':
                if (!registering) {
                  throw StateError('Registration closed');
                }
                if (message['action'] case final String name) {
                  if (!manifest.actions.any((a) => a.name == name) ||
                      !actions.add(name)) {
                    throw PluginExecutionError(
                      'plugin_registration_mismatch',
                      'Action not declared in manifest: $name',
                    );
                  }
                  break;
                }
                if (message['complete'] == true) {
                  registering = false;
                  if (actions.length != manifest.actions.length) {
                    throw PluginExecutionError(
                      'plugin_registration_mismatch',
                      'Registered actions differ from manifest',
                    );
                  }
                  if (expected != null &&
                      canonicalPluginJson(definitions) !=
                          canonicalPluginJson(expected)) {
                    throw PluginExecutionError(
                      'plugin_registration_mismatch',
                      'Registration differs from activation',
                    );
                  }
                  break;
                }
                final definition =
                    message['definition'] as Map<String, dynamic>;
                PluginTool(manifest.id, manifest.name, 'bundled', definition);
                definitions.add(definition);
                if (expected != null &&
                    (definitions.length > expected.length ||
                        canonicalPluginJson(definition) !=
                            canonicalPluginJson(
                              expected[definitions.length - 1],
                            ))) {
                  throw PluginExecutionError(
                    'plugin_registration_mismatch',
                    'Registration differs from activation',
                  );
                }
              case 'call':
                if (registering) {
                  throw StateError('Host API unavailable during apply');
                }
                // 设置页操作不依赖激活结果，插件关闭时也能执行。
                if (action == null &&
                    (expected == null ||
                        canonicalPluginJson(definitions) !=
                            canonicalPluginJson(expected))) {
                  throw PluginExecutionError(
                    'plugin_registration_mismatch',
                    'Registration differs from activation',
                  );
                }
                final method = message['method'] as String;
                final result = await hostCall(
                  method,
                  message['args'] as Map<String, dynamic>,
                );
                return JsResult.ok(
                  JsValue.string(jsonEncode({'ok': true, 'result': result})),
                );
              case 'result':
                if (receivedResult) {
                  throw StateError('Duplicate result');
                }
                receivedResult = true;
                if (message['error'] != null) {
                  throw PluginExecutionError(
                    RegExp(
                          'out of memory|stack overflow|memory limit',
                          caseSensitive: false,
                        ).hasMatch(message['error'].toString())
                        ? 'plugin_memory_limit'
                        : 'plugin_error',
                    message['error'].toString(),
                    hostCode: message['code'] as String?,
                  );
                }
                if (expected != null &&
                    canonicalPluginJson(definitions) !=
                        canonicalPluginJson(expected)) {
                  throw PluginExecutionError(
                    'plugin_registration_mismatch',
                    'Registration differs from activation',
                  );
                }
                if (tool != null || action != null) {
                  if (message['value'] is! Map<String, dynamic> ||
                      utf8.encode(jsonEncode(message['value'])).length >
                          256 * 1024) {
                    throw PluginExecutionError(
                      'plugin_invalid_result',
                      '${action != null ? 'Action' : 'Tool'} must return a JSON object up to 256 KB',
                    );
                  }
                  output = message['value'] as Map<String, dynamic>;
                }
              default:
                throw const FormatException('Unknown bridge kind');
            }
            reply = {'ok': true, 'result': null};
          } catch (error) {
            if (error is PluginExecutionError) {
              stop(error);
            } else if (error is! PluginHostError) {
              stop(PluginExecutionError('plugin_error', error.toString()));
            }
            reply = {
              'ok': false,
              'code': error is PluginHostError ? error.code : 'plugin_error',
              'error': error.toString(),
            };
          }
          return JsResult.ok(JsValue.string(jsonEncode(reply)));
        },
      );
      await engine.eval(
        source: JsCode.code(
          '${pluginPrelude(manifest.id, manifest.version)}\n$code\n${action != null ? pluginInvokeAction(action, callId) : pluginInvoke(tool, input, callId)}',
        ),
      );
      if (failure != null) {
        throw failure!;
      }
      if (!receivedResult) {
        throw PluginExecutionError('plugin_invalid_result', 'Missing result');
      }
      return (definitions: definitions, result: output);
    } catch (error) {
      if (failure != null) {
        throw failure!;
      }
      if (error is PluginExecutionError) {
        rethrow;
      }
      final text = error.toString();
      throw PluginExecutionError(
        RegExp(
              'out of memory|stack overflow|memory limit',
              caseSensitive: false,
            ).hasMatch(text)
            ? 'plugin_memory_limit'
            : 'plugin_error',
        text,
      );
    } finally {
      accepting = false;
      timer.cancel();
      remove?.call();
      onStop?.call();
      await close();
    }
  }
}

class PluginHostError implements Exception {
  PluginHostError(this.code, this.message);
  final String code, message;
  @override
  String toString() => '$code: $message';
}
