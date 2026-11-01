// 职责: 发现、配置并激活插件，执行工具调用与设置页操作，维护状态及每次调用的独立资源。
// 关联文件:
//   lib/shared/services/plugins/config.dart
//   lib/shared/services/plugins/runtime.dart
//   lib/shared/models/plugin/manifest.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../agent/agent_tool_dispatcher.dart';
import '../../database/daos/plugin_dao.dart';
import '../../logger/app_logger.dart';
import '../../models/plugin/action.dart';
import '../../models/plugin/manifest.dart';
import '../../models/plugin/setting_field.dart';
import 'config.dart';
import 'http.dart';
import 'registry.dart';
import 'runtime.dart';

final _log = AppLogger.forModule('Plugin');

class PluginPackage {
  PluginPackage(this.path, this.manifest, this.code, {this.source = 'bundled'});
  final String path, code, source;
  final PluginManifest manifest;
}

class PluginStatus {
  PluginStatus({
    required this.id,
    required this.path,
    this.manifest,
    this.enabled = false,
    this.state = 'disabled',
    this.error,
    this.source = 'bundled',
    this.needsConfig = false,
  });
  final String id, path, source;
  final PluginManifest? manifest;
  bool enabled;
  String state;
  String? error;

  /// 必填配置未填写；此时不能开启插件。
  bool needsConfig;
}

typedef PluginExecutorFactory =
    PluginExecutor Function(PluginHostCall call, void Function() stop);

class PluginHostService {
  PluginHostService({
    required this.dao,
    required this.registry,
    this.packages,
    PluginExecutorFactory? executorFactory,
    String? platform,
  }) : executorFactory =
           executorFactory ??
           ((call, stop) => PluginRuntime(hostCall: call, onStop: stop)),
       platform = platform ?? Platform.operatingSystem;
  final PluginDao dao;
  final PluginRegistry registry;
  final Future<List<PluginPackage>> Function()? packages;
  final PluginExecutorFactory executorFactory;
  final String platform;
  final _changes = StreamController<List<PluginStatus>>.broadcast();
  final _packages = <String, PluginPackage>{};
  final _statuses = <String, PluginStatus>{};
  final _serial = <String, Future<void>>{};
  final _running = <String, int>{};
  final _queues = <String, List<Completer<bool>>>{};
  Future<void>? _starting;
  bool _disposed = false;
  List<PluginStatus> get statuses => List.unmodifiable(_statuses.values);
  Stream<List<PluginStatus>> get changes => _changes.stream;
  void _emit() {
    if (!_disposed) {
      _changes.add(statuses);
    }
  }

  Future<void> start() => _starting ??= _start();
  Future<List<PluginPackage>> _discover() async {
    final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
    final result = <PluginPackage>[];
    for (final path in assets.listAssets().where(
      (p) => RegExp(r'^assets/plugins/[^/]+/plugin.json$').hasMatch(p),
    )) {
      try {
        final manifest = PluginManifest.fromJson(
          jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>,
        );
        final directory = path.substring(0, path.lastIndexOf('/'));
        final data = await rootBundle.load('$directory/${manifest.main}');
        if (data.lengthInBytes > 2 * 1024 * 1024) {
          throw const FormatException('Entry exceeds 2 MB');
        }
        result.add(
          PluginPackage(
            directory,
            manifest,
            utf8.decode(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          ),
        );
      } catch (error, stack) {
        _statuses[path] = PluginStatus(
          id: path,
          path: path,
          state: 'failed',
          error: error.toString(),
        );
        _log.error(
          'Manifest load failed: $path',
          error: error,
          stackTrace: stack,
        );
      }
    }
    return result;
  }

  Future<void> _start() async {
    final found = await (packages?.call() ?? _discover());
    final ordered = <(PluginPackage, DateTime)>[];
    for (final package in found) {
      final manifest = package.manifest;
      if (_packages.containsKey(manifest.id)) {
        throw StateError('Duplicate plugin id: ${manifest.id}');
      }
      await dao.register(
        pluginId: manifest.id,
        version: manifest.version,
        source: package.source,
        packagePath: package.path,
        defaultEnabled: manifest.defaultEnabled,
      );
      final row = (await dao.getPlugin(manifest.id))!;
      _packages[manifest.id] = package;
      _statuses[manifest.id] = PluginStatus(
        id: manifest.id,
        path: package.path,
        manifest: manifest,
        enabled: row.enabled,
        source: package.source,
        needsConfig: await _missingRequiredKey(manifest) != null,
      );
      ordered.add((package, row.createdAt));
    }
    ordered.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$1.manifest.id.compareTo(b.$1.manifest.id);
    });
    _emit();
    for (final item in ordered) {
      await _activate(item.$1.manifest.id);
    }
  }

  Future<void> _activate(String pluginId) async {
    final status = _statuses[pluginId]!;
    registry.remove(pluginId);
    status.error = null;
    if (!status.enabled) {
      status.state = 'disabled';
      _emit();
      return;
    }
    if (!status.manifest!.platforms.contains(platform)) {
      status.state = 'unsupported';
      _emit();
      return;
    }
    status.state = 'activating';
    _emit();
    if (!await _acquire(pluginId)) {
      return;
    }
    try {
      if (_disposed) {
        return;
      }
      final package = _packages[pluginId]!;
      final runtime = executorFactory((method, args) async {
        throw PluginHostError(
          'unavailable',
          'Host APIs unavailable during apply',
        );
      }, () {});
      final definitions = await runtime.activate(
        package.manifest,
        package.code,
      );
      if (_disposed) {
        return;
      }
      registry.register(pluginId, [
        for (final definition in definitions)
          PluginTool(
            pluginId,
            package.manifest.name,
            package.source,
            definition,
          ),
      ]);
      status.state = 'available';
    } catch (error, stack) {
      status.state = 'failed';
      status.error = error.toString();
      _log.error(
        'Activation failed: $pluginId',
        error: error,
        stackTrace: stack,
      );
    } finally {
      _releaseQueue(pluginId);
    }
    _emit();
  }

  Future<void> setEnabled(String pluginId, bool enabled) {
    final next = (_serial[pluginId] ?? Future<void>.value()).then((_) async {
      await start();
      if (!_packages.containsKey(pluginId)) {
        throw StateError('Unknown plugin: $pluginId');
      }
      if (enabled) {
        final missing = await _missingRequiredKey(
          _packages[pluginId]!.manifest,
        );
        if (missing != null) {
          throw StateError('Required plugin configuration: $missing');
        }
      }
      await dao.setEnabled(pluginId, enabled);
      _statuses[pluginId]!.enabled = enabled;
      await _activate(pluginId);
    });
    _serial[pluginId] = next.catchError((Object _) {});
    return next;
  }

  /// 第一个未填写的必填配置项；全部已填写时返回 null。
  Future<String?> _missingRequiredKey(PluginManifest manifest) async {
    final required = manifest.settings.where((field) => field.required);
    if (required.isEmpty) {
      return null;
    }
    final config = await readPluginConfig(dao, manifest);
    for (final field in required) {
      if (field.isSecret
          ? !config.savedSecrets.contains(field.key)
          : validatePluginSettingValue(field, config.values[field.key]) !=
                null) {
        return field.key;
      }
    }
    return null;
  }

  PluginManifest _manifest(String pluginId) =>
      _packages[pluginId]?.manifest ??
      (throw StateError('Unknown plugin: $pluginId'));

  Future<PluginConfig> loadConfig(String pluginId) =>
      readPluginConfig(dao, _manifest(pluginId));

  /// 与启停共用串行队列，避免清空必填凭据与开启插件交错。
  Future<void> saveConfig(
    String pluginId, {
    required Map<String, Object?> settings,
    required Map<String, String?> secrets,
  }) {
    final next = (_serial[pluginId] ?? Future<void>.value()).then((_) async {
      final manifest = _manifest(pluginId);
      final disabled = await PluginConfigOrchestrator().save(
        dao: dao,
        manifest: manifest,
        settings: settings,
        secrets: secrets,
      );
      final status = _statuses[pluginId]!;
      status.needsConfig = await _missingRequiredKey(manifest) != null;
      if (disabled) {
        status.enabled = false;
        await _activate(pluginId);
      } else {
        _emit();
      }
    });
    _serial[pluginId] = next.catchError((Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> input, {
    String callId = '',
    AgentCancellationToken? cancellation,
  }) async {
    final tool = registry.resolve(name);
    Map<String, dynamic> unavailable() => {
      'ok': false,
      'error_code': 'plugin_unavailable',
      'error': 'Plugin tool unavailable: $name',
    };
    if (_disposed ||
        tool == null ||
        _statuses[tool.pluginId]?.state != 'available') {
      return unavailable();
    }
    final id = tool.pluginId;
    Map<String, dynamic> cancelled() => {
      'ok': false,
      'plugin_id': id,
      'error_code': 'user_cancelled',
      'error': 'Plugin call cancelled',
      'cancelled': true,
    };
    final acquired = await _acquire(id, cancellation: cancellation);
    if (!acquired) {
      return cancellation?.isCancellationRequested == true
          ? cancelled()
          : unavailable();
    }
    if (cancellation?.isCancellationRequested == true) {
      _releaseQueue(id);
      return cancelled();
    }
    if (_disposed ||
        registry.resolve(name)?.pluginId != id ||
        _statuses[id]?.state != 'available') {
      _releaseQueue(id);
      return unavailable();
    }
    final http = PluginHttpApi();
    try {
      final package = _packages[id]!;
      final expected = registry.toolsFor(id).map((t) => t.definition).toList();
      final secrets = await dao.secretValues(id);
      if (cancellation?.isCancellationRequested == true) {
        return cancelled();
      }
      final runtime = executorFactory(
        _hostApi(id, package, http, secrets),
        http.cancel,
      );

      return await runtime.invoke(
        package.manifest,
        package.code,
        expected,
        name,
        input,
        callId,
        cancellation,
      );
    } catch (error) {
      return {
        'ok': false,
        'plugin_id': id,
        'error_code': error is PluginExecutionError
            ? error.code
            : 'plugin_error',
        'error': error.toString(),
        if (error is PluginExecutionError && error.hostCode != null)
          'code': error.hostCode,
        if (error is PluginExecutionError && error.code == 'user_cancelled')
          'cancelled': true,
      };
    } finally {
      http.cancel();
      _releaseQueue(id);
    }
  }

  /// 执行设置页操作。[settings]、[secrets] 是表单里尚未保存的值，覆盖已保存配置，
  /// 凭据为 null 表示待清空。插件未开启时也可执行，便于开启前验证配置。
  Future<PluginActionResult> runAction(
    String pluginId,
    String name, {
    Map<String, Object?> settings = const {},
    Map<String, String?> secrets = const {},
    AgentCancellationToken? cancellation,
  }) async {
    await start();
    final package = _packages[pluginId];
    final redactions = [
      for (final value in secrets.values)
        if (value != null && value.isNotEmpty) value,
    ];
    PluginActionResult failed(String code, String message) {
      _log.warning(
        'Action failed: $pluginId.$name $code '
        '${_redact(message, redactions)}',
      );
      return (ok: false, code: code);
    }

    if (_disposed ||
        package == null ||
        !package.manifest.actions.any((action) => action.name == name)) {
      return failed('unavailable', 'Unknown plugin action');
    }
    if (!package.manifest.platforms.contains(platform)) {
      return failed('unsupported', 'Plugin does not support $platform');
    }
    if (!await _acquire(pluginId, cancellation: cancellation)) {
      return failed('unavailable', 'No execution slot');
    }
    final http = PluginHttpApi();
    try {
      redactions.addAll(await dao.secretValues(pluginId));
      final runtime = executorFactory(
        _hostApi(
          pluginId,
          package,
          http,
          redactions,
          draftSettings: settings,
          draftSecrets: secrets,
        ),
        http.cancel,
      );
      final value = await runtime.runAction(
        package.manifest,
        package.code,
        name,
        '',
        cancellation,
      );
      if (value['ok'] == true) {
        return (ok: true, code: null);
      }
      return failed(
        value['code'] is String ? value['code'] as String : 'failed',
        '${value['message'] ?? ''}',
      );
    } on PluginExecutionError catch (error) {
      return failed(
        error.code == 'plugin_timeout' ? 'timeout' : error.code,
        error.message,
      );
    } catch (error) {
      return failed('plugin_error', error.toString());
    } finally {
      http.cancel();
      _releaseQueue(pluginId);
    }
  }

  /// 插件可调用的宿主 API。设置页操作传入表单草稿，覆盖已保存的配置。
  PluginHostCall _hostApi(
    String id,
    PluginPackage package,
    PluginHttpApi http,
    List<String> secrets, {
    Map<String, Object?> draftSettings = const {},
    Map<String, String?> draftSecrets = const {},
  }) => (method, args) async {
    if (method == 'http.fetch') {
      return http.fetch(args);
    }
    if (method == 'settings.get' || method == 'secrets.get') {
      final key = args['key'];
      final field = package.manifest.settings
          .where((field) => field.key == key)
          .firstOrNull;
      if (key is! String ||
          field == null ||
          field.isSecret != (method == 'secrets.get')) {
        throw PluginHostError(
          'invalid_argument',
          'Undeclared $method key: $key',
        );
      }
      if (field.isSecret) {
        if (draftSecrets.containsKey(key)) {
          final value = draftSecrets[key];
          return value == null || value.isEmpty ? null : value;
        }
        return readPluginSecret(dao, id, key);
      }
      if (draftSettings.containsKey(key)) {
        return draftSettings[key] ?? field.defaultValue;
      }
      return readPluginSetting(dao, id, field);
    }
    if (['log.info', 'log.warn', 'log.error'].contains(method)) {
      if (args['message'] is! String) {
        throw PluginHostError(
          'invalid_argument',
          'Log message must be a string',
        );
      }
      _log.info('plugin=$id $method ${_redact(jsonEncode(args), secrets)}');
      return null;
    }
    throw PluginHostError('unavailable', 'Host API not implemented: $method');
  };

  /// 同时替换原文和 JSON 转义后的凭据。
  String _redact(String text, Iterable<String> secrets) {
    var result = text;
    for (final secret in secrets.where((s) => s.isNotEmpty)) {
      final encoded = jsonEncode(secret);
      result = result
          .replaceAll(secret, '***')
          .replaceAll(encoded.substring(1, encoded.length - 1), '***');
    }
    return result;
  }

  Future<bool> _acquire(
    String id, {
    AgentCancellationToken? cancellation,
  }) async {
    if (_disposed || cancellation?.isCancellationRequested == true) {
      return false;
    }
    if ((_running[id] ?? 0) < 4) {
      _running[id] = (_running[id] ?? 0) + 1;
      return true;
    }
    final waiter = Completer<bool>();
    final queue = (_queues[id] ??= []);
    queue.add(waiter);
    final unlink = cancellation?.onCancel(() {
      // remove 成功说明还未接手槽位；交接后的取消由 execute 释放其租约。
      if (queue.remove(waiter)) {
        waiter.complete(false);
      }
    });
    try {
      return await waiter.future;
    } finally {
      unlink?.call();
    }
  }

  void _releaseQueue(String id) {
    final queue = _queues[id];
    if (queue != null && queue.isNotEmpty) {
      queue.removeAt(0).complete(true);
    } else {
      _running[id] = (_running[id] ?? 1) - 1;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final id in _packages.keys) {
      registry.remove(id);
    }
    for (final queue in _queues.values) {
      for (final waiter in queue) {
        waiter.complete(false);
      }
      queue.clear();
    }
    await _changes.close();
  }
}
