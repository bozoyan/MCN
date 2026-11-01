// 职责: 通过 Android SAF 读写用户选择的目录，承接文档与 AgentSkill 的移动端导入导出
// 关联文件:
//   lib/mobile/pages/novel_editor_page.dart
//   android/app/src/main/kotlin/ai/reveric/MainActivity.kt
//   lib/shared/services/documents_service.dart
//   lib/shared/services/agent_skill_transfer.dart
//   lib/shared/logger/app_logger.dart
import 'dart:io';

import 'package:flutter/services.dart';

import '../../shared/logger/app_logger.dart';

final _log = AppLogger.forModule('AndroidSafDirectoryImport');

const _channel = MethodChannel('reveric/android_directory_import');

const androidDocumentImportExtensions = <String>{'txt', 'md', 'csv'};

class AndroidSafExportFile {
  const AndroidSafExportFile({
    required this.relativePath,
    required this.content,
  });

  final String relativePath;
  final String content;
}

class AndroidSafDirectoryExportResult {
  const AndroidSafDirectoryExportResult({
    required this.directoryName,
    required this.fileCount,
  });

  final String directoryName;
  final int fileCount;
}

class AndroidSafDirectoryImportResult {
  const AndroidSafDirectoryImportResult({
    required this.directoryPath,
    required this.directoryName,
    required this.fileCount,
    required this.directoryCount,
  });

  final String directoryPath;
  final String directoryName;
  final int fileCount;
  final int directoryCount;
}

Future<AndroidSafDirectoryImportResult?> pickAndCopyAndroidDirectory({
  Set<String> extensions = androidDocumentImportExtensions,
}) async {
  final rawResult = await _channel.invokeMethod<Map<Object?, Object?>>(
    'pickAndCopyDirectory',
    <String, Object>{
      'extensions': extensions
          .map((extension) => extension.toLowerCase().replaceFirst('.', ''))
          .toList(growable: false),
    },
  );
  if (rawResult == null) {
    _log.info('directory selection cancelled');
    return null;
  }

  final path = rawResult['path'];
  final name = rawResult['name'];
  final fileCount = rawResult['fileCount'];
  final directoryCount = rawResult['directoryCount'];
  if (path is! String ||
      name is! String ||
      fileCount is! int ||
      directoryCount is! int) {
    throw const FormatException(
      'Android directory import returned an invalid result.',
    );
  }

  _log.info(
    'directory copied to app cache files=$fileCount directories=$directoryCount',
  );
  return AndroidSafDirectoryImportResult(
    directoryPath: path,
    directoryName: name,
    fileCount: fileCount,
    directoryCount: directoryCount,
  );
}

Future<void> deleteAndroidDirectoryImport(String directoryPath) async {
  try {
    final directory = Directory(directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
      _log.info('temporary directory deleted');
    }
  } on FileSystemException catch (error, stackTrace) {
    _log.warning('temporary directory cleanup failed: $error\n$stackTrace');
  }
}

Future<AndroidSafDirectoryExportResult?> writeFilesToAndroidDirectory({
  required List<AndroidSafExportFile> files,
}) async {
  final rawResult = await _channel.invokeMethod<Map<Object?, Object?>>(
    'pickAndWriteFiles',
    <String, Object>{
      'files': files
          .map(
            (file) => <String, String>{
              'path': file.relativePath,
              'content': file.content,
            },
          )
          .toList(growable: false),
    },
  );
  if (rawResult == null) {
    _log.info('directory export selection cancelled');
    return null;
  }
  final name = rawResult['name'];
  final count = rawResult['fileCount'];
  if (name is! String || count is! int) {
    throw const FormatException(
      'Android directory export returned an invalid result.',
    );
  }
  _log.info('files written to selected Android directory count=$count');
  return AndroidSafDirectoryExportResult(directoryName: name, fileCount: count);
}
