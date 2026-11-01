// 职责: 编排移动端文档导入 — 选择文件或目录、Android SAF 复制到缓存、写入当前文件夹并清理临时副本
// 关联文件:
//   lib/mobile/services/android_saf_directory_import.dart
//   lib/mobile/widgets/document_folder_browser.dart
//   lib/shared/services/documents_service.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import '../../shared/logger/app_logger.dart';
import '../../shared/services/documents_service.dart';
import 'android_saf_directory_import.dart';

final _log = AppLogger.forModule('MobileDocumentImport');

enum MobileDocumentImportSource { file, directory }

const mobileTextDocumentImportTypeGroup = XTypeGroup(
  label: 'text',
  extensions: <String>['txt', 'md', 'csv'],
  mimeTypes: <String>['text/plain', 'text/markdown', 'text/csv'],
  uniformTypeIdentifiers: <String>[
    'public.text',
    'net.daringfireball.markdown',
    'public.comma-separated-values-text',
  ],
);

class MobileDocumentImportResult {
  const MobileDocumentImportResult({
    required this.imported,
    required this.skipped,
  });

  final int imported;
  final int skipped;

  bool get isEmpty => imported == 0 && skipped == 0;
}

class MobileDocumentImportSelection {
  const MobileDocumentImportSelection.files(this.filePaths)
    : directoryPath = null,
      directoryName = null,
      temporaryDirectoryPath = null;

  const MobileDocumentImportSelection.directory({
    required this.directoryPath,
    this.directoryName,
    this.temporaryDirectoryPath,
  }) : filePaths = const [];

  final List<String> filePaths;
  final String? directoryPath;
  final String? directoryName;
  final String? temporaryDirectoryPath;

  bool get isEmpty => filePaths.isEmpty && directoryPath == null;
}

bool mobileDocumentImportSupportsDirectory() {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.fuchsia || TargetPlatform.iOS => false,
  };
}

class MobileDocumentImportOrchestrator {
  const MobileDocumentImportOrchestrator();

  Future<MobileDocumentImportSelection?> pick(
    MobileDocumentImportSource source,
  ) async {
    switch (source) {
      case MobileDocumentImportSource.file:
        final files = await openFiles(
          acceptedTypeGroups: const [mobileTextDocumentImportTypeGroup],
        );
        if (files.isEmpty) {
          _log.info('document file selection cancelled');
          return null;
        }
        return MobileDocumentImportSelection.files(
          files.map((file) => file.path).toList(growable: false),
        );
      case MobileDocumentImportSource.directory:
        if (defaultTargetPlatform == TargetPlatform.android) {
          return _pickAndroidDirectory();
        }
        final directoryPath = await getDirectoryPath();
        if (directoryPath == null) {
          _log.info('document directory selection cancelled');
          return null;
        }
        return MobileDocumentImportSelection.directory(
          directoryPath: directoryPath,
          directoryName: mobileDocumentImportDirectoryName(directoryPath),
        );
    }
  }

  Future<MobileDocumentImportResult> importPicked({
    required DocumentsService documentsService,
    required String type,
    String? parentId,
    required MobileDocumentImportSelection selection,
  }) async {
    if (selection.filePaths.isNotEmpty) {
      final result = await documentsService.importFiles(
        type: type,
        filePaths: selection.filePaths,
        parentId: parentId,
      );
      return MobileDocumentImportResult(
        imported: result.imported,
        skipped: result.skipped,
      );
    }

    final directoryPath = selection.directoryPath;
    if (directoryPath == null) {
      return const MobileDocumentImportResult(imported: 0, skipped: 0);
    }

    final dirName =
        selection.directoryName ??
        mobileDocumentImportDirectoryName(directoryPath);
    if (dirName.isEmpty) {
      _log.warning('directory import skipped because folder name is empty');
      return const MobileDocumentImportResult(imported: 0, skipped: 0);
    }

    final existing = await documentsService.getDocumentByTitle(
      type: type,
      title: dirName,
      parentId: parentId,
    );
    final rootFolderId = existing != null && existing.isFolder
        ? existing.id
        : await documentsService.createFolder(
            type: type,
            parentId: parentId,
            title: dirName,
          );
    final result = await documentsService.importDirectory(
      type: type,
      directoryPath: directoryPath,
      parentId: rootFolderId,
    );
    return MobileDocumentImportResult(
      imported: result.imported,
      skipped: result.skipped,
    );
  }

  Future<void> cleanup(MobileDocumentImportSelection selection) {
    final temporaryPath = selection.temporaryDirectoryPath;
    if (temporaryPath == null) {
      return Future<void>.value();
    }
    return deleteAndroidDirectoryImport(temporaryPath);
  }

  Future<MobileDocumentImportSelection?> _pickAndroidDirectory() async {
    final result = await pickAndCopyAndroidDirectory();
    if (result == null) {
      _log.info('document directory selection cancelled');
      return null;
    }
    if (result.fileCount == 0) {
      _log.info('copied Android directory contained no importable files');
      await deleteAndroidDirectoryImport(result.directoryPath);
      return const MobileDocumentImportSelection.files([]);
    }
    return MobileDocumentImportSelection.directory(
      directoryPath: result.directoryPath,
      directoryName: result.directoryName,
      temporaryDirectoryPath: result.directoryPath,
    );
  }
}

@visibleForTesting
String mobileDocumentImportDirectoryName(String path) {
  final normalized = path.replaceAll(RegExp(r'[/\\]+$'), '');
  return normalized.split(RegExp(r'[/\\]')).last;
}
