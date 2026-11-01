// 职责: 文档类数据（世界观/大纲/素材）的 CRUD 服务，支持多层级文件夹管理和文本文件/目录导入。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/utils/text_file_decoder.dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';

import '../database/novel_content_database.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../utils/ai_path_name_check.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';
import '../utils/text_file_decoder.dart';
import '../utils/unique_display_name.dart';

final _log = AppLogger.forModule('DocumentsService');

class DocumentsService {
  DocumentsService(
    this._database, {
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
  }) : _buildEntityId = idBuilder;

  final NovelContentDatabase _database;
  final ShortEntityIdBuilder _buildEntityId;

  ShortEntityIdType _idType(String type, {required bool isFolder}) {
    return switch ((type, isFolder)) {
      (documentTypeLore, false) => ShortEntityIdType.loreDocument,
      (documentTypeLore, true) => ShortEntityIdType.loreFolder,
      (documentTypeMaterial, false) => ShortEntityIdType.materialsDocument,
      (documentTypeMaterial, true) => ShortEntityIdType.materialsFolder,
      _ => throw ArgumentError.value(
        type,
        'type',
        'Unsupported model-visible document type.',
      ),
    };
  }

  Future<bool> _idExists(String id) async {
    final row =
        await (_database.selectOnly(_database.documents)
              ..addColumns([_database.documents.id])
              ..where(_database.documents.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Stream<List<Document>> watchDocumentsByType(String type) =>
      _database.documentDao.watchByType(type);

  Future<List<Document>> getDocumentsByType(String type) =>
      _database.documentDao.getByType(type);

  Future<Document?> getDocumentById(String id) =>
      _database.documentDao.getById(id);

  Future<Document?> getDocumentByTitle({
    required String type,
    required String title,
    String? parentId,
  }) {
    return (_database.select(_database.documents)..where((table) {
          final parentCondition = parentId == null
              ? table.parentId.isNull()
              : table.parentId.equals(parentId);
          return table.type.equals(type) &
              table.title.equals(title) &
              parentCondition &
              table.deletedAt.equals(notDeletedSentinel);
        }))
        .getSingleOrNull();
  }

  Future<Document?> getDocumentByNamePath({
    required String type,
    required List<String> namePath,
  }) async {
    if (namePath.isEmpty) return null;

    String? currentParentId;
    Document? currentDocument;

    for (var i = 0; i < namePath.length; i++) {
      final name = namePath[i];
      final doc =
          await (_database.select(_database.documents)..where((table) {
                final parentCondition = currentParentId == null
                    ? table.parentId.isNull()
                    : table.parentId.equals(currentParentId);
                return table.type.equals(type) &
                    table.title.equals(name) &
                    parentCondition &
                    table.deletedAt.equals(notDeletedSentinel);
              }))
              .getSingleOrNull();

      if (doc == null) return null;
      currentDocument = doc;
      currentParentId = doc.id;
    }

    return currentDocument;
  }

  Future<List<Document>> getDocumentsInPath({
    required String type,
    required List<String> namePath,
  }) async {
    if (namePath.isEmpty) {
      return getChildren(
        null,
      ).then((docs) => docs.where((d) => d.type == type).toList());
    }

    final parent = await getDocumentByNamePath(type: type, namePath: namePath);
    if (parent == null) return [];
    if (!parent.isFolder) return [];

    return getChildren(
      parent.id,
    ).then((docs) => docs.where((d) => d.type == type).toList());
  }

  Future<bool> isTitleAvailable({
    required String type,
    required String title,
    String? parentId,
    String? excludeId,
  }) async {
    if (title.isEmpty) {
      return true;
    }
    final query = _database.select(_database.documents)
      ..where((table) {
        final parentCondition = parentId == null
            ? table.parentId.isNull()
            : table.parentId.equals(parentId);
        var condition =
            table.type.equals(type) &
            table.title.equals(title) &
            parentCondition &
            table.deletedAt.equals(notDeletedSentinel);
        if (excludeId != null) {
          condition = condition & table.id.equals(excludeId).not();
        }
        return condition;
      });
    final existing = await query.getSingleOrNull();
    return existing == null;
  }

  Future<void> assertTitleAvailable({
    required String type,
    required String title,
    String? parentId,
    String? excludeId,
  }) async {
    if (nameHasAiPathStructuralChars(title)) {
      throw ArgumentError.value(
        title,
        'title',
        tr(LocaleKeys.commonNameHasPathChar),
      );
    }
    final available = await isTitleAvailable(
      type: type,
      title: title,
      parentId: parentId,
      excludeId: excludeId,
    );
    if (!available) {
      final location = parentId == null
          ? tr(LocaleKeys.commonRootDirectory)
          : tr(LocaleKeys.commonThisFolder);
      throw ArgumentError.value(
        title,
        'title',
        tr(
          LocaleKeys.commonDuplicateTitleIn,
          namedArgs: {'title': title, 'location': location},
        ),
      );
    }
  }

  Future<String> createDocument({
    required String type,
    String? parentId,
    String title = '',
    String? defaultTitle,
    String content = '',
    String tags = '',
    String category = '',
    String status = documentStatusActive,
  }) async {
    final now = DateTime.now();
    final nextSortOrder = await _nextSortOrder(parentId: parentId);
    final documentTitle = title.isNotEmpty || defaultTitle == null
        ? title
        : buildUniqueDisplayName(
            baseName: defaultTitle,
            existingNames: (await _getSiblings(type: type, parentId: parentId))
                .map((document) {
                  return document.title;
                }),
          );
    await assertTitleAvailable(
      type: type,
      title: documentTitle,
      parentId: parentId,
    );
    try {
      return await insertWithShortEntityId(
        type: _idType(type, isFolder: false),
        tableName: 'documents',
        idExists: _idExists,
        buildId: _buildEntityId,
        insert: (id) => _database
            .into(_database.documents)
            .insert(
              DocumentsCompanion.insert(
                id: id,
                type: type,
                title: documentTitle,
                content: Value(content),
                status: Value(status),
                tags: Value(tags),
                category: Value(category),
                parentId: Value(parentId),
                isFolder: const Value(false),
                sortOrder: Value(nextSortOrder),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=documents operation=INSERT type=$type folder=false failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<String> createFolder({
    required String type,
    String? parentId,
    String title = '',
  }) async {
    final now = DateTime.now();
    final nextSortOrder = await _nextSortOrder(parentId: parentId);
    await assertTitleAvailable(type: type, title: title, parentId: parentId);
    try {
      return await insertWithShortEntityId(
        type: _idType(type, isFolder: true),
        tableName: 'documents',
        idExists: _idExists,
        buildId: _buildEntityId,
        insert: (id) => _database
            .into(_database.documents)
            .insert(
              DocumentsCompanion.insert(
                id: id,
                type: type,
                title: title,
                content: const Value(''),
                status: const Value(documentStatusActive),
                tags: const Value(''),
                parentId: Value(parentId),
                isFolder: const Value(true),
                sortOrder: Value(nextSortOrder),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=documents operation=INSERT type=$type folder=true failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 批量创建文档（同一 [type] + [parentId]）。
  ///
  /// 一次性解析 sortOrder 与唯一标题，并在一个事务中严格插入。标题去重语义与
  /// [createDocument] 一致：先对已存在的兄弟去重，再对本批内部去重。返回新建
  /// 文档 id（与入参同序）。
  Future<List<String>> createDocuments({
    required String type,
    String? parentId,
    required List<({String title, String content, String category})> entries,
  }) async {
    if (entries.isEmpty) {
      return const [];
    }
    final now = DateTime.now();
    final usedNames = <String>{
      for (final sibling in await _getSiblings(type: type, parentId: parentId))
        sibling.title.trim(),
    };
    var sortOrder = await _nextSortOrder(parentId: parentId);
    final idType = _idType(type, isFolder: false);
    try {
      return await _database.transaction(() async {
        final ids = <String>[];
        final reservedIds = <String>{};
        for (final entry in entries) {
          final title = buildUniqueDisplayName(
            baseName: entry.title,
            existingNames: usedNames,
          );
          usedNames.add(title);
          final currentSortOrder = sortOrder;
          final id = await insertWithShortEntityId(
            type: idType,
            tableName: 'documents',
            idExists: _idExists,
            reservedIds: reservedIds,
            buildId: _buildEntityId,
            insert: (candidate) => _database
                .into(_database.documents)
                .insert(
                  DocumentsCompanion.insert(
                    id: candidate,
                    type: type,
                    title: title,
                    content: Value(entry.content),
                    status: const Value(documentStatusActive),
                    category: Value(entry.category),
                    parentId: Value(parentId),
                    isFolder: const Value(false),
                    sortOrder: Value(currentSortOrder),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                  ),
                ),
          );
          ids.add(id);
          sortOrder += 1;
        }
        return ids;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=documents operation=INSERT_BATCH type=$type failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Document>> _getSiblings({
    required String type,
    required String? parentId,
  }) {
    return (_database.select(_database.documents)..where((table) {
          final parentCondition = parentId == null
              ? table.parentId.isNull()
              : table.parentId.equals(parentId);
          return table.type.equals(type) &
              parentCondition &
              table.deletedAt.equals(notDeletedSentinel);
        }))
        .get();
  }

  // tags 传 null 时保持不动（Value.absent），不是「不传即清空」—— 调用方只改
  // title/content/category 时不允许顺带抹掉存量 tags。
  Future<void> updateDocument({
    required String id,
    required String title,
    required String content,
    String? tags,
    String? category,
  }) async {
    final existing = await getDocumentById(id);
    if (existing != null && existing.title != title) {
      await assertTitleAvailable(
        type: existing.type,
        title: title,
        parentId: existing.parentId,
        excludeId: id,
      );
    }
    await (_database.update(
      _database.documents,
    )..where((table) => table.id.equals(id))).write(
      DocumentsCompanion(
        title: Value(title),
        content: Value(content.trimRight()),
        tags: tags == null ? const Value.absent() : Value(tags),
        category: category == null ? const Value.absent() : Value(category),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateDocumentStatus({
    required String id,
    required String status,
  }) {
    _assertAllowedStatus(status, documentStatuses, fieldName: 'status');
    return (_database.update(
      _database.documents,
    )..where((table) => table.id.equals(id))).write(
      DocumentsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> moveDocument({required String id, String? newParentId}) async {
    final existing = await getDocumentById(id);
    if (existing != null) {
      await assertTitleAvailable(
        type: existing.type,
        title: existing.title,
        parentId: newParentId,
        excludeId: id,
      );
    }
    final nextSortOrder = await _nextSortOrder(parentId: newParentId);
    await (_database.update(
      _database.documents,
    )..where((table) => table.id.equals(id))).write(
      DocumentsCompanion(
        parentId: Value(newParentId),
        sortOrder: Value(nextSortOrder),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteDocument(String id) async {
    final children = await getChildren(id);
    if (children.isNotEmpty) {
      throw Exception('Cannot delete folder with children');
    }
    await (_database.delete(
      _database.documents,
    )..where((table) => table.id.equals(id))).go();
  }

  Future<void> deleteDocumentRecursive(String id) async {
    await _database.transaction(() async {
      await _deleteDocumentRecursive(id);
    });
  }

  Future<void> _deleteDocumentRecursive(String id) async {
    final children = await getChildren(id);
    for (final child in children) {
      await _deleteDocumentRecursive(child.id);
    }
    await (_database.delete(
      _database.documents,
    )..where((table) => table.id.equals(id))).go();
  }

  Future<List<Document>> getChildren(String? parentId) {
    return (_database.select(_database.documents)
          ..where(
            (table) => parentId == null
                ? table.parentId.isNull()
                : table.parentId.equals(parentId),
          )
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Stream<List<Document>> watchChildren(String? parentId) {
    return (_database.select(_database.documents)
          ..where(
            (table) => parentId == null
                ? table.parentId.isNull()
                : table.parentId.equals(parentId),
          )
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<bool> hasChildren(String id) async {
    final children =
        await (_database.select(_database.documents)
              ..where((table) => table.parentId.equals(id))
              ..where((table) => table.deletedAt.equals(notDeletedSentinel))
              ..limit(1))
            .get();
    return children.isNotEmpty;
  }

  Future<List<Document>> getAncestors(String id) async {
    final ancestors = <Document>[];
    var currentId = id;
    while (true) {
      final doc = await getDocumentById(currentId);
      if (doc == null || doc.parentId == null) break;
      final parent = await getDocumentById(doc.parentId!);
      if (parent == null) break;
      ancestors.add(parent);
      currentId = parent.id;
    }
    return ancestors;
  }

  Future<List<Document>> getDescendants(String id) async {
    final descendants = <Document>[];
    await _collectDescendants(id, descendants);
    return descendants;
  }

  Future<void> _collectDescendants(
    String id,
    List<Document> descendants,
  ) async {
    final children = await getChildren(id);
    for (final child in children) {
      descendants.add(child);
      await _collectDescendants(child.id, descendants);
    }
  }

  Future<void> reorderDocuments(List<String> ids) async {
    await _database.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (_database.update(_database.documents)
              ..where((table) => table.id.equals(ids[i])))
            .write(DocumentsCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<void> reorderChildren(String? parentId, List<String> ids) async {
    await _database.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        final doc = await getDocumentById(ids[i]);
        if (doc == null) continue;
        if (doc.parentId != parentId) continue;
        await (_database.update(_database.documents)
              ..where((table) => table.id.equals(ids[i])))
            .write(DocumentsCompanion(sortOrder: Value(i)));
      }
    });
  }

  void _assertAllowedStatus(
    String value,
    List<String> allowedValues, {
    required String fieldName,
  }) {
    if (!allowedValues.contains(value)) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Allowed values: ${allowedValues.join(', ')}',
      );
    }
  }

  Future<int> _nextSortOrder({String? parentId}) async {
    final items =
        await (_database.select(_database.documents)..where(
              (table) => parentId == null
                  ? table.parentId.isNull()
                  : table.parentId.equals(parentId),
            ))
            .get();
    if (items.isEmpty) {
      return 0;
    }
    final maxSortOrder = items
        .map((item) => item.sortOrder)
        .reduce((a, b) => a > b ? a : b);
    return maxSortOrder + 1;
  }

  Future<({int imported, int skipped})> importDirectory({
    required String type,
    required String directoryPath,
    String? parentId,
  }) async {
    final dir = Directory(directoryPath);
    final exists = dir.existsSync();
    _log.info(
      'directory import started type=$type exists=$exists '
      'pathKind=${_pathKind(directoryPath)}',
    );
    if (!exists) {
      _log.warning(
        'directory import failed: selected directory is not readable',
      );
      throw FileSystemException('Directory is not readable', directoryPath);
    }

    var imported = 0;
    var skipped = 0;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    } catch (error, stackTrace) {
      _log.error(
        'directory import enumeration failed pathKind=${_pathKind(directoryPath)}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    for (final entry in entries) {
      if (entry is File) {
        final result = await _importTextFile(
          type: type,
          file: entry,
          parentId: parentId,
        );
        imported += result.imported;
        skipped += result.skipped;
      } else if (entry is Directory) {
        final path = entry.path;
        final folderName = _baseName(path);
        if (folderName.isEmpty || folderName.startsWith('.')) continue;
        String folderId;
        final existing = await getDocumentByTitle(
          type: type,
          title: folderName,
          parentId: parentId,
        );
        if (existing != null && existing.isFolder) {
          folderId = existing.id;
        } else {
          folderId = await createFolder(
            type: type,
            parentId: parentId,
            title: folderName,
          );
        }
        final sub = await importDirectory(
          type: type,
          directoryPath: entry.path,
          parentId: folderId,
        );
        imported += sub.imported;
        skipped += sub.skipped;
      }
    }

    _log.info(
      'directory import completed type=$type imported=$imported skipped=$skipped',
    );
    return (imported: imported, skipped: skipped);
  }

  Future<({int imported, int skipped})> importFile({
    required String type,
    required String filePath,
    String? parentId,
  }) {
    return _importTextFile(
      type: type,
      file: File(filePath),
      parentId: parentId,
    );
  }

  /// 批量导入多个文本文件。逐文件复用 [_importTextFile] 的扩展名过滤、
  /// 空文件跳过与同名 upsert 语义，汇总返回导入/跳过计数。
  Future<({int imported, int skipped})> importFiles({
    required String type,
    required List<String> filePaths,
    String? parentId,
  }) async {
    var imported = 0;
    var skipped = 0;
    for (final filePath in filePaths) {
      final result = await _importTextFile(
        type: type,
        file: File(filePath),
        parentId: parentId,
      );
      imported += result.imported;
      skipped += result.skipped;
    }
    return (imported: imported, skipped: skipped);
  }

  Future<({int imported, int skipped})> _importTextFile({
    required String type,
    required File file,
    required String? parentId,
  }) async {
    final name = _baseName(file.path);
    if (name.isEmpty || name.startsWith('.')) return (imported: 0, skipped: 0);

    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex > 0 ? name.substring(dotIndex + 1).toLowerCase() : '';
    if (ext != 'txt' && ext != 'md' && ext != 'csv') {
      return (imported: 0, skipped: 0);
    }

    final title = dotIndex > 0 ? name.substring(0, dotIndex) : name;

    try {
      final content = decodeImportedTextBytes(await file.readAsBytes());
      if (content.isEmpty) {
        return (imported: 0, skipped: 1);
      }

      await _upsertImportedDocument(
        type: type,
        parentId: parentId,
        title: title,
        content: content,
      );
      return (imported: 1, skipped: 0);
    } on FileSystemException catch (error, stackTrace) {
      _log.error(
        'document import file read failed extension=$ext',
        error: error,
        stackTrace: stackTrace,
      );
      return (imported: 0, skipped: 1);
    }
  }

  Future<void> _upsertImportedDocument({
    required String type,
    required String? parentId,
    required String title,
    required String content,
  }) async {
    final existing = await getDocumentByTitle(
      type: type,
      title: title,
      parentId: parentId,
    );
    if (existing != null) {
      await updateDocument(id: existing.id, title: title, content: content);
      return;
    }

    final id = await createDocument(
      type: type,
      parentId: parentId,
      title: title,
    );
    await updateDocument(id: id, title: title, content: content);
  }

  String _baseName(String path) {
    final normalized = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    return normalized.split(Platform.pathSeparator).last;
  }

  String _pathKind(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme.isNotEmpty) {
      return uri.scheme;
    }
    return path.startsWith(Platform.pathSeparator) ? 'absolute' : 'relative';
  }
}
