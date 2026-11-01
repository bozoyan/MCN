// 职责: 保存本机文件工作区位置，在业务树卸载期间复制后切换，并支持显式恢复默认位置。
// 关联文件:
//   lib/shared/utils/storage_paths.dart
//   lib/shared/models/local_settings.dart
//   lib/desktop/widgets/settings/settings_storage_section.dart
//   lib/shared/widgets/file_workspace_startup_gate.dart
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/service-naming.md

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../logger/app_logger.dart';
import '../models/local_settings.dart';
import '../utils/storage_paths.dart';

final _log = AppLogger.forModule('FileWorkspace');

class FileWorkspaceLocation {
  const FileWorkspaceLocation({this.activeParent});

  final String? activeParent;

  String get currentDirectory =>
      p.join(activeParent ?? RevericPaths.supportRoot, 'file_workspaces');
}

class FileWorkspaceOrchestrator {
  /// 本机设置文件；路径只对当前设备有效，不进入可移植的应用备份。
  File get _config =>
      File(p.join(RevericPaths.supportRoot, 'settings.local.json'));

  Future<FileWorkspaceLocation> load() async {
    try {
      if (!await _config.exists()) {
        return const FileWorkspaceLocation();
      }
      final settings = LocalSettings.fromJson(
        jsonDecode(await _config.readAsString()) as Map<String, dynamic>,
      );
      final active = settings.fileWorkspaceDirectory;
      if (active != null && (!p.isAbsolute(active) || active.contains('://'))) {
        throw const FormatException('Invalid file workspace location');
      }
      return FileWorkspaceLocation(activeParent: active);
    } catch (error, stack) {
      logFileWorkspaceError('load', error, stack);
      rethrow;
    }
  }

  /// 校验目标父目录并返回规范路径；与当前位置相同时返回 null。
  Future<String?> prepare(String parent) async {
    if (Platform.isAndroid || Platform.isIOS) {
      throw UnsupportedError('Custom file workspaces require a desktop');
    }
    if (!p.isAbsolute(parent) || parent.contains('://')) {
      throw const FormatException('A local absolute directory is required');
    }
    final canonical = await Directory(parent).resolveSymbolicLinks();
    final target = p.join(canonical, 'file_workspaces');
    final source = await _source(await load());
    if (p.equals(target, source.path)) {
      return null;
    }
    _requireSeparateDirectories(source.path, target);
    await RevericPaths.requireNoLinks(Directory(canonical), target);
    // A private temporary directory probes permissions without touching user files.
    final probe = await Directory(canonical).createTemp('.reveric_probe_');
    await probe.delete();
    return canonical;
  }

  /// 业务树卸载后调用：完整复制后才保存并切换位置。
  /// 失败或中途退出时配置仍指向原位置，原文件不受影响。
  Future<void> migrate(String parent) async {
    try {
      final canonical = await prepare(parent);
      if (canonical == null) {
        return;
      }
      final source = await _source(await load());
      final target = Directory(p.join(canonical, 'file_workspaces'));
      _log.info('migration started');
      await target.create(recursive: true);
      if (await source.exists()) {
        await _copy(source, target);
      }
      await _save(FileWorkspaceLocation(activeParent: canonical));
      await RevericPaths.initialize(fileWorkspaceParent: canonical);
      _log.info('migration completed; source retained');
    } catch (error, stack) {
      logFileWorkspaceError('migration', error, stack);
      rethrow;
    }
  }

  /// 启动失败时由用户明确选择；不能依赖旧配置可解析或旧目录可访问。
  /// 只重置位置配置，已有工作区文件保持原样；由启动门重新初始化运行时。
  Future<void> useApplicationDirectory() async {
    await _save(const FileWorkspaceLocation());
    _log.info('application directory selected for recovery');
  }

  /// Run before business providers or background writers are mounted.
  Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    try {
      final current = await load();
      final source = await _source(current);
      if (current.activeParent != null && !await source.exists()) {
        throw const FileSystemException('Active file workspace is unavailable');
      }
      await RevericPaths.initialize(fileWorkspaceParent: current.activeParent);
    } catch (error, stack) {
      logFileWorkspaceError('initialization', error, stack);
      rethrow;
    }
  }

  Future<Directory> _source(FileWorkspaceLocation current) async {
    final source = Directory(
      p.join(
        await Directory(
          p.dirname(current.currentDirectory),
        ).resolveSymbolicLinks(),
        'file_workspaces',
      ),
    );
    await RevericPaths.requireNoLinks(source.parent, source.path);
    return source;
  }

  void _requireSeparateDirectories(String source, String target) {
    if (p.equals(source, target) ||
        p.isWithin(source, target) ||
        p.isWithin(target, source)) {
      throw const FileSystemException('Workspace directories must not overlap');
    }
  }

  Future<void> _copy(Directory source, Directory target) async {
    var copied = 0;
    await for (final entry in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Link) {
        throw const FileSystemException('Workspace contains a symbolic link');
      }
      final destination = p.join(
        target.path,
        p.relative(entry.path, from: source.path),
      );
      await RevericPaths.requireNoLinks(target, destination);
      if (entry is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entry is File) {
        final output = File(destination);
        final type = await FileSystemEntity.type(
          destination,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound) {
          if (type != FileSystemEntityType.file ||
              !await _sameFile(entry, output)) {
            throw const FileSystemException(
              'Destination contains different files',
            );
          }
          continue;
        }
        await output.parent.create(recursive: true);
        // Only this private temporary copy is removed on failure. A killed
        // process can leave a temporary directory, never a partial final file.
        final staging = await output.parent.createTemp('.reveric_copy_');
        try {
          final copy = await entry.copy(p.join(staging.path, 'content'));
          if (!await _sameFile(entry, copy)) {
            throw const FileSystemException(
              'Workspace copy verification failed',
            );
          }
          if (await FileSystemEntity.type(destination, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw const FileSystemException('Destination changed during copy');
          }
          await copy.rename(destination);
          copied++;
        } finally {
          await staging.delete(recursive: true);
        }
      } else {
        throw const FileSystemException('Unsupported workspace entry');
      }
    }
    _log.info('copy completed files=$copied');
  }

  Future<bool> _sameFile(File left, File right) async =>
      await left.length() == await right.length() &&
      await sha256.bind(left.openRead()).first ==
          await sha256.bind(right.openRead()).first;

  Future<void> _save(FileWorkspaceLocation value) async {
    final temp = await _config.parent.createTemp('.reveric_settings_');
    try {
      final file = File(p.join(temp.path, 'settings.local.json'));
      await file.writeAsString(
        jsonEncode(
          LocalSettings(fileWorkspaceDirectory: value.activeParent).toJson(),
        ),
        flush: true,
      );
      await file.rename(_config.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}

/// 保留诊断消息与 OS 错误码，隐去异常中的完整路径和 JSON 原文。
void logFileWorkspaceError(String operation, Object error, StackTrace stack) {
  final diagnostic = switch (error) {
    FileSystemException(:final message, :final osError) => FileSystemException(
      message,
      null,
      osError,
    ),
    FormatException(:final message) => FormatException(message),
    _ => error.runtimeType,
  };
  _log.error(
    '$operation failed type=${error.runtimeType}',
    error: diagnostic,
    stackTrace: stack,
  );
}
