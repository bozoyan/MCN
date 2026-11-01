// 职责: 派生并持久化匿名设备唯一标识，硬件指纹不可用时回退随机 UUID。
// 关联文件:
//   lib/shared/services/anonymous_outbox_service.dart
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/providers/trace_providers.dart
//

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 生成并持久化匿名设备 ID。
///
/// 桌面端优先从系统稳定机器标识派生 SHA-256，且只持久化派生结果；
/// 不能读取时回退随机 UUID。原始机器标识不会上传或写日志。
class DeviceIdService {
  static const _key = 'device_id';
  final _uuid = const Uuid();

  /// 返回已有 device_id，若不存在则生成并持久化。
  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final fingerprint = await _readHardwareFingerprint();
    final id = fingerprint == null
        ? _uuid.v4()
        : sha256.convert(utf8.encode(fingerprint)).toString();
    await prefs.setString(_key, id);
    return id;
  }

  /// 生成新的随机 device_id 并立即覆盖当前持久化值。
  ///
  /// 仅用于调试：重新读取硬件指纹会得到相同的稳定 ID，
  /// 因此此操作刻意使用随机 UUID。
  Future<String> regenerate() async {
    final id = _uuid.v4();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
    return id;
  }

  Future<String?> _readHardwareFingerprint() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('ioreg', [
          '-rd1',
          '-c',
          'IOPlatformExpertDevice',
        ]);
        return _matchValue(
          result.stdout as String,
          RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"'),
        );
      }
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystemProduct).UUID',
        ]);
        return _firstNonEmptyLine(result.stdout as String);
      }
      if (Platform.isLinux) {
        final file = File('/etc/machine-id');
        if (await file.exists()) {
          return (await file.readAsString()).trim();
        }
      }
    } catch (_) {
      // 指纹能力是可选的；调用方会持久化随机 UUID 回退。
    }
    return null;
  }

  String? _matchValue(String value, RegExp pattern) {
    final match = pattern.firstMatch(value);
    return match?.group(1)?.trim();
  }

  String? _firstNonEmptyLine(String value) {
    for (final line in value.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
