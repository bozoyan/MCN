// 职责: 校验并编解码 MCP 服务配置，保留认证信息。
// 关联文件:
//   lib/shared/services/mcp/settings_orchestrator.dart
//   lib/shared/services/mcp/client_adapter.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';

enum McpExposure { deferred, direct }

enum McpAuthMode { none, bearer, headers, oauth }

sealed class McpTransportConfig {
  const McpTransportConfig();
  Map<String, dynamic> toJson();
}

class McpStdioConfig extends McpTransportConfig {
  McpStdioConfig({
    required this.command,
    List<String> args = const [],
    this.cwd,
    Map<String, String> env = const {},
  }) : args = List.unmodifiable(args),
       env = Map.unmodifiable(env) {
    if (command.trim().isEmpty) {
      throw const FormatException('MCP command is required');
    }
  }
  final String command;
  final List<String> args;
  final String? cwd;
  final Map<String, String> env;
  @override
  Map<String, dynamic> toJson() => {
    'transport': 'stdio',
    'command': command,
    'args': args,
    if (cwd != null) 'cwd': cwd,
    'env': env,
  };
}

class McpHttpConfig extends McpTransportConfig {
  McpHttpConfig({
    required this.url,
    this.authMode = McpAuthMode.none,
    Map<String, String> headers = const {},
    this.bearerToken,
    Map<String, dynamic> oauth = const {},
  }) : headers = Map.unmodifiable(headers),
       oauth = Map.unmodifiable(
         jsonDecode(jsonEncode(oauth)) as Map<String, dynamic>,
       ) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('Invalid MCP HTTP URL');
    }
    if (headers.entries.any(
      (e) =>
          e.key.isEmpty ||
          e.key.contains(RegExp(r'[\r\n:]')) ||
          e.value.contains(RegExp(r'[\r\n]')),
    )) {
      throw const FormatException('Invalid MCP header');
    }
    if (bearerToken?.contains(RegExp(r'[\r\n]')) == true) {
      throw const FormatException('Invalid Bearer token');
    }
    if (authMode == McpAuthMode.oauth &&
        headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      throw const FormatException(
        'OAuth cannot override an explicit Authorization header',
      );
    }
    for (final key in [
      'clientId',
      'accessToken',
      'refreshToken',
      'expiresAt',
      'issuer',
      'resource',
      'tokenEndpoint',
      'registeredClientId',
      'registeredClientSecret',
      'registeredAuthMethod',
    ]) {
      if (oauth[key] != null && oauth[key] is! String) {
        throw const FormatException('Invalid OAuth field type');
      }
    }
    final scopes = oauth['scopes'];
    if (scopes != null &&
        (scopes is! List || scopes.any((value) => value is! String))) {
      throw const FormatException('Invalid OAuth scopes');
    }
    final port = oauth['callbackPort'];
    if (port != null && (port is! int || port < 1 || port > 65535)) {
      throw const FormatException('Invalid OAuth callback port');
    }
    if (oauth['expiresAt'] is String &&
        DateTime.tryParse(oauth['expiresAt'] as String) == null) {
      throw const FormatException('Invalid OAuth expiration');
    }
  }
  final String url;
  final McpAuthMode authMode;
  final Map<String, String> headers;
  final String? bearerToken;
  final Map<String, dynamic> oauth;
  @override
  Map<String, dynamic> toJson() => {
    'transport': 'streamable_http',
    'url': url,
    'authMode': authMode.name,
    'headers': headers,
    if (bearerToken != null) 'bearerToken': bearerToken,
    'oauth': oauth,
  };
  // Rotating token values do not change the authenticated connection identity.
  // Login/logout, issuer/resource changes and user edits still invalidate it.
  Map<String, dynamic> connectionIdentity() => {
    ...toJson(),
    if (authMode == McpAuthMode.oauth)
      'oauth': {
        ...Map<String, dynamic>.from(oauth)
          ..remove('accessToken')
          ..remove('refreshToken')
          ..remove('expiresAt'),
        'hasAccessToken': oauth['accessToken'] != null,
      },
  };
}

class McpServerConfig {
  McpServerConfig({
    required this.name,
    required this.connection,
    this.description,
    this.enabled = false,
    this.exposure = McpExposure.deferred,
    this.connectTimeoutSeconds = 15,
    this.callTimeoutSeconds = 60,
  }) {
    if (name.isEmpty ||
        name != name.trim() ||
        name.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Invalid MCP server name');
    }
    if (namespace.replaceAll('_', '').isEmpty) {
      throw const FormatException('MCP name must contain letters or digits');
    }
    if (connectTimeoutSeconds <= 0 || callTimeoutSeconds <= 0) {
      throw const FormatException('MCP timeouts must be positive');
    }
  }
  final String name;
  final McpTransportConfig connection;
  final String? description;
  final bool enabled;
  final McpExposure exposure;
  final int connectTimeoutSeconds;
  final int callTimeoutSeconds;
  String get namespace {
    final normalized = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return normalized.replaceAll('_', '').isEmpty
        ? 'server_${sha256.convert(utf8.encode(name)).toString().substring(0, 16)}'
        : normalized;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    ...connection.toJson(),
    if (description != null) 'description': description,
    'enabled': enabled,
    'exposure': exposure.name,
    'connectTimeoutSeconds': connectTimeoutSeconds,
    'callTimeoutSeconds': callTimeoutSeconds,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final transport = json['transport'];
    final McpTransportConfig connection;
    switch (transport) {
      case 'stdio':
        connection = McpStdioConfig(
          command: json['command'] as String,
          args: (json['args'] as List? ?? []).cast<String>(),
          cwd: json['cwd'] as String?,
          env: Map<String, String>.from(json['env'] as Map? ?? {}),
        );
      case 'streamable_http':
        connection = McpHttpConfig(
          url: json['url'] as String,
          authMode: McpAuthMode.values.byName(
            json['authMode'] as String? ?? 'none',
          ),
          headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
          bearerToken: json['bearerToken'] as String?,
          oauth: Map<String, dynamic>.from(json['oauth'] as Map? ?? {}),
        );
      default:
        throw const FormatException('Unsupported MCP transport');
    }
    return McpServerConfig(
      name: json['name'] as String,
      connection: connection,
      description: json['description'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      exposure: McpExposure.values.byName(
        json['exposure'] as String? ?? 'deferred',
      ),
      connectTimeoutSeconds: json['connectTimeoutSeconds'] as int? ?? 15,
      callTimeoutSeconds: json['callTimeoutSeconds'] as int? ?? 60,
    );
  }

  McpServerConfig copyWith({
    McpTransportConfig? connection,
    bool? enabled,
    String? description,
    McpExposure? exposure,
  }) => McpServerConfig(
    name: name,
    connection: connection ?? this.connection,
    enabled: enabled ?? this.enabled,
    description: description ?? this.description,
    exposure: exposure ?? this.exposure,
    connectTimeoutSeconds: connectTimeoutSeconds,
    callTimeoutSeconds: callTimeoutSeconds,
  );
}

/// [name] collides with [existing]: either the same name, or a different name
/// that normalizes to the same tool namespace.
class McpServerNameConflict extends FormatException {
  const McpServerNameConflict(this.name, this.existing)
    : super('Duplicate MCP server name or namespace');
  final String name;
  final String existing;
}

class McpSettings {
  McpSettings(Iterable<McpServerConfig> servers)
    : servers = List.unmodifiable(servers) {
    final namespaces = <String, String>{};
    for (final server in this.servers) {
      // Equal names always share a namespace, so one lookup covers both.
      if (namespaces[server.namespace] case final existing?) {
        throw McpServerNameConflict(server.name, existing);
      }
      namespaces[server.namespace] = server.name;
    }
  }
  static const key = 'mcp_servers';
  final List<McpServerConfig> servers;
  String encode() => jsonEncode({
    'formatVersion': 1,
    'servers': servers.map((s) => s.toJson()).toList(),
  });
  factory McpSettings.decode(String? raw) {
    if (raw == null) {
      return McpSettings([]);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['formatVersion'] != 1) {
        throw const FormatException('Unsupported MCP configuration version');
      }
      return McpSettings(
        (json['servers'] as List).map(
          (s) => McpServerConfig.fromJson(s as Map<String, dynamic>),
        ),
      );
    } on FormatException catch (error) {
      // JSON parser diagnostics may contain the original credential-bearing source.
      throw FormatException(
        error.source == null ? error.message : 'Invalid MCP configuration JSON',
      );
    } on TypeError {
      throw const FormatException('Invalid MCP configuration field type');
    } on ArgumentError {
      throw const FormatException('Invalid MCP configuration field value');
    }
  }

  McpSettings disabledForRestore() =>
      McpSettings(servers.map((s) => s.copyWith(enabled: false)));
}

/// Runtime loading preserves valid servers and reports invalid entries without
/// rewriting storage. Persistence and imports still use strict McpSettings.
class McpSettingsLoad {
  McpSettingsLoad(this.settings, this.errors, {this.error});
  final McpSettings settings;
  final Map<String, String> errors;
  final String? error;

  factory McpSettingsLoad.decode(String? raw) {
    if (raw == null) {
      return McpSettingsLoad(McpSettings([]), const {});
    }
    late List<dynamic> entries;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['formatVersion'] != 1) {
        throw const FormatException('Unsupported MCP configuration version');
      }
      entries = json['servers'] as List;
    } on FormatException catch (error) {
      return McpSettingsLoad(
        McpSettings([]),
        const {},
        error: error.source == null
            ? error.message
            : 'Invalid MCP configuration JSON',
      );
    } on TypeError {
      return McpSettingsLoad(
        McpSettings([]),
        const {},
        error: 'Invalid MCP configuration field type',
      );
    }
    final valid = <McpServerConfig>[];
    final errors = <String, String>{};
    final names = <String, int>{};
    final namespaces = <String, Set<String>>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final name = entry is Map && entry['name'] is String
          ? entry['name'] as String
          : 'servers[$i]';
      names[name] = (names[name] ?? 0) + 1;
      try {
        final config = McpServerConfig.fromJson(entry as Map<String, dynamic>);
        valid.add(config);
        namespaces.putIfAbsent(config.namespace, () => {}).add(config.name);
      } on FormatException catch (error) {
        errors[name] = error.source == null
            ? error.message
            : 'Invalid MCP configuration field value';
      } on TypeError {
        errors[name] = 'Invalid MCP configuration field type';
      } on ArgumentError {
        errors[name] = 'Invalid MCP configuration field value';
      }
    }
    for (final config in valid) {
      if (names[config.name]! > 1 || namespaces[config.namespace]!.length > 1) {
        errors[config.name] = 'Duplicate MCP server name or namespace';
      }
    }
    return McpSettingsLoad(
      McpSettings(valid.where((s) => !errors.containsKey(s.name))),
      Map.unmodifiable(errors),
    );
  }
}
