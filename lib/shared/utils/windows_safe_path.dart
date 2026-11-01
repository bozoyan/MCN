// 职责: 在 Windows 上将含非 ASCII 字符的路径转换为 8.3 短路径，避免 SQLite 因中文用户名/路径打开失败
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/novel_content.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../logger/app_logger.dart';

final _log = AppLogger.forModule('WindowsSafePath');

/// 将路径转换为不含非 ASCII 字符的形式，避免 sqlite3 在 Windows 中文用户名下开库失败。
///
/// - 非 Windows 平台直接返回原路径。
/// - Windows 下若路径全部为 ASCII，原样返回。
/// - Windows 下含非 ASCII 字符时，对路径所在的「已存在目录」调用 `GetShortPathNameW` 取 8.3
///   短路径，再拼回目标文件名。
/// - 当 8.3 短名被磁盘禁用、目录不存在或 API 调用失败时，回退到原路径并打印警告日志。
///
/// 调用方需在调用前确保目标文件所在目录存在，否则无法生成短路径。
String toWindowsSafePath(String path) {
  if (!Platform.isWindows) return path;
  if (_isAscii(path)) return path;

  final dir = p.dirname(path);
  final base = p.basename(path);
  final shortDir = _getShortPath(dir);
  if (shortDir == null || shortDir.isEmpty) {
    _log.warning(
      'failed to resolve 8.3 short path for "$dir"; '
      'falling back to original path. SQLite may fail to open if the path '
      'contains non-ASCII characters.',
    );
    return path;
  }
  return p.join(shortDir, base);
}

bool _isAscii(String s) {
  for (final code in s.codeUnits) {
    if (code > 127) return false;
  }
  return true;
}

String? _getShortPath(String path) {
  final inputPtr = path.toPcwstr();
  try {
    final lengthNeeded = GetShortPathName(inputPtr, null, 0).value;
    if (lengthNeeded == 0) return null;
    final buffer = wsalloc(lengthNeeded);
    try {
      final result = GetShortPathName(inputPtr, buffer, lengthNeeded).value;
      if (result == 0 || result >= lengthNeeded) return null;
      return buffer.toDartString();
    } finally {
      free(buffer);
    }
  } finally {
    free(inputPtr);
  }
}
