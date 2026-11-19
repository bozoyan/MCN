// 职责: BizyAir 多密钥池——从外置 txt 或供应商 Key 字段解析多把密钥，跨任务轮转分摊额度。
// 关联文件:
//   lib/shared/services/ai/image/bizyair.dart
//   lib/shared/utils/storage_paths.dart
//   /Users/hao/DOC/py/2026/MCP/bizyair/bizyair.py（同一套多密钥规则的 CLI 实现）
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/storage_paths.dart';

/// BizyAir 密钥池。
///
/// 规则与 CLI 保持一致：
/// - 一个任务只用一把 key，成功后游标 +1，跨任务顺序轮转分摊额度；
/// - 提交失败时串行切换到下一把重试，全部失败才报错；
/// - 游标持久化到应用目录，进程重启后接着轮转。
class BizyAirKeyPool {
  BizyAirKeyPool._(this.keys, this._index, this._cursorFile);

  /// 供应商 Key 字段默认当作密钥池文件的候选路径（cwd 之外的常用位置）。
  static const defaultPoolPaths = <String>[
    '~/PY/2026/bizyair/bizyair_BOZO.txt',
    '~/.bizyair/keys.txt',
    '~/DOC/py/2026/bizyair/bizyair_BOZO.txt',
  ];

  /// 游标在应用目录下的文件名（按供应商 ID 分槽）。
  static const _cursorFileName = 'bizyair_key_cursors.json';

  final List<String> keys;
  final File? _cursorFile;
  int _index;

  bool get isEmpty => keys.isEmpty;

  int get size => keys.length;

  /// 当前任务使用的密钥；空池时为 null。
  String? get current => keys.isEmpty ? null : keys[_index];

  /// 当前游标位置（0 基），用于日志与测试。
  int get index => _index;

  /// 脱敏展示，日志里不出现完整密钥。
  String get masked {
    final key = current;
    if (key == null) {
      return '<none>';
    }
    return key.length > 10 ? '...${key.substring(key.length - 6)}' : '***';
  }

  /// 提交失败时切到下一把；池里只有一把时返回 false（没有可换的 key）。
  bool advance() {
    if (keys.length <= 1) {
      return false;
    }
    _index = (_index + 1) % keys.length;
    return true;
  }

  /// 任务成功后把游标 +1 落盘，下次任务换下一把。
  Future<void> commit() async {
    final file = _cursorFile;
    if (file == null || keys.isEmpty) {
      return;
    }
    try {
      final next = (_index + 1) % keys.length;
      final map = await _readCursorMap(file);
      map[_slot] = next;
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (_) {
      // 游标写失败不影响出图，下次从头轮转。
    }
  }

  String get _slot => _cursorSlot;

  String _cursorSlot = 'default';

  /// 解析供应商 Key 字段：
  /// 1. 非空且指向存在的文件 → 按密钥池文件读取（每行一把、`#` 注释、支持 KEY=value）；
  /// 2. 非空且不是文件 → 当作内联密钥，逗号/空白/换行分隔；
  /// 3. 为空 → 依次尝试 [defaultPoolPaths] 与 `BIZYAIR_API_KEYS` 环境变量。
  static Future<BizyAirKeyPool> resolve(
    String raw, {
    String providerId = '',
    File? cursorFile,
  }) async {
    final trimmed = raw.trim();
    final keys = <String>[];

    if (trimmed.isEmpty) {
      keys.addAll(_keysFromEnvironment());
      if (keys.isEmpty) {
        for (final candidate in defaultPoolPaths) {
          final file = File(_expandHome(candidate));
          if (await file.exists()) {
            keys.addAll(parseKeys(await file.readAsString()));
            if (keys.isNotEmpty) {
              break;
            }
          }
        }
      }
    } else {
      final asPath = File(_expandHome(trimmed));
      if (!trimmed.contains('\n') &&
          !trimmed.contains(',') &&
          await asPath.exists()) {
        keys.addAll(parseKeys(await asPath.readAsString()));
      } else {
        keys.addAll(parseKeys(trimmed));
      }
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final key in keys) {
      if (seen.add(key)) {
        unique.add(key);
      }
    }

    final cursor = cursorFile ?? _defaultCursorFile();
    final pool = BizyAirKeyPool._(
      List.unmodifiable(unique),
      unique.isEmpty ? 0 : (await _readIndexOf(cursor, providerId)) % unique.length,
      cursor,
    ).._cursorSlot = providerId.isEmpty ? 'default' : providerId;
    return pool;
  }

  /// 直接喂密钥列表（测试或不依赖文件的场景）。
  static BizyAirKeyPool fromKeys(
    Iterable<String> keys, {
    int startIndex = 0,
    File? cursorFile,
    String providerId = '',
  }) {
    final unique = <String>[];
    final seen = <String>{};
    for (final key in keys.map((key) => key.trim()).where((key) => key.isNotEmpty)) {
      if (seen.add(key)) {
        unique.add(key);
      }
    }
    final pool = BizyAirKeyPool._(
      List.unmodifiable(unique),
      unique.isEmpty ? 0 : startIndex % unique.length,
      cursorFile,
    );
    pool._cursorSlot = providerId.isEmpty ? 'default' : providerId;
    return pool;
  }

  /// 解析密钥文本：每行一把，跳过空行与 `#` 注释；
  /// 兼容 `BIZYAIR_API_KEY=sk-xxx` / `export KEY="sk-xxx"` 写法，
  /// 同一行内的逗号/空白分隔也视为多把。
  static List<String> parseKeys(String content) {
    final keys = <String>[];
    for (final line in content.split('\n')) {
      var value = line.trim();
      if (value.isEmpty || value.startsWith('#')) {
        continue;
      }
      // 先去掉 export，再识别 KEY=value，否则前缀里的空格会让赋值判断失效。
      value = value.replaceFirst(RegExp(r'^export\s+'), '');
      final equals = value.indexOf('=');
      if (equals > 0 && !value.substring(0, equals).contains(RegExp(r'\s'))) {
        value = value.substring(equals + 1).trim();
      }
      for (final part in value.split(RegExp(r'[,\s]+'))) {
        final key = part.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
        if (key.isNotEmpty && !key.startsWith('#')) {
          keys.add(key);
        }
      }
    }
    return keys;
  }

  static List<String> _keysFromEnvironment() {
    final raw = Platform.environment['BIZYAIR_API_KEYS'] ?? '';
    return raw.trim().isEmpty ? const [] : parseKeys(raw);
  }

  static String _expandHome(String path) =>
      path.startsWith('~/')
      ? p.join(Platform.environment['HOME'] ?? '', path.substring(2))
      : path;

  static File? _defaultCursorFile() {
    try {
      return File(p.join(RevericPaths.supportRoot, _cursorFileName));
    } catch (_) {
      // 应用未初始化路径时（如单元测试）不持久化游标。
      return null;
    }
  }

  static Future<Map<String, dynamic>> _readCursorMap(File file) async {
    try {
      if (!await file.exists()) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<int> _readIndexOf(File? file, String providerId) async {
    if (file == null) {
      return 0;
    }
    final map = await _readCursorMap(file);
    final value = map[providerId.isEmpty ? 'default' : providerId];
    return value is int && value >= 0 ? value : 0;
  }
}
