// 职责: 验证移动端文档导入编排会把目录建成当前层下的文件夹，并支持指定 parentId。
// 关联文件:
//   lib/mobile/services/document_import_orchestrator.dart
//   lib/shared/services/documents_service.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/file-access.md
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/services/document_import_orchestrator.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/documents_service.dart';

void main() {
  late NovelContentDatabase db;
  late DocumentsService service;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = DocumentsService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('imports files into the current folder', () async {
    final parentId = await service.createFolder(
      type: documentTypeLore,
      title: '资料',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'reveric_mobile_document_import_files_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}设定.md');
    await file.writeAsString('灵气复苏。');

    final result = await const MobileDocumentImportOrchestrator().importPicked(
      documentsService: service,
      type: documentTypeLore,
      parentId: parentId,
      selection: MobileDocumentImportSelection.files([file.path]),
    );

    final children = await service.getChildren(parentId);
    expect(result.imported, 1);
    expect(result.skipped, 0);
    expect(children.single.title, '设定');
    expect(children.single.parentId, parentId);
    expect(children.single.isFolder, isFalse);
  });

  test('imports a directory as a folder under the current parent', () async {
    final parentId = await service.createFolder(
      type: documentTypeLore,
      title: '世界观',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'reveric_mobile_document_import_dir_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final nested = Directory('${tempDir.path}${Platform.pathSeparator}地理');
    await nested.create();
    await File(
      '${nested.path}${Platform.pathSeparator}都城.txt',
    ).writeAsString('京城。');

    final result = await const MobileDocumentImportOrchestrator().importPicked(
      documentsService: service,
      type: documentTypeLore,
      parentId: parentId,
      selection: MobileDocumentImportSelection.directory(
        directoryPath: tempDir.path,
        directoryName: '导入包',
      ),
    );

    final parentChildren = await service.getChildren(parentId);
    expect(result.imported, 1);
    expect(parentChildren.single.title, '导入包');
    expect(parentChildren.single.isFolder, isTrue);

    final importedChildren = await service.getChildren(
      parentChildren.single.id,
    );
    expect(importedChildren.single.title, '地理');
    expect(importedChildren.single.isFolder, isTrue);

    final nestedChildren = await service.getChildren(
      importedChildren.single.id,
    );
    expect(nestedChildren.single.title, '都城');
    expect(nestedChildren.single.parentId, importedChildren.single.id);
  });

  test(
    'reuses an existing folder with the same name in the current parent',
    () async {
      final existingId = await service.createFolder(
        type: documentTypeLore,
        title: '导入包',
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'reveric_mobile_document_import_reuse_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}补充.md',
      ).writeAsString('补充设定。');

      await const MobileDocumentImportOrchestrator().importPicked(
        documentsService: service,
        type: documentTypeLore,
        selection: MobileDocumentImportSelection.directory(
          directoryPath: tempDir.path,
          directoryName: '导入包',
        ),
      );

      final roots = await service.getChildren(null);
      expect(roots.where((document) => document.isFolder), hasLength(1));
      expect(roots.singleWhere((document) => document.isFolder).id, existingId);
      final children = await service.getChildren(existingId);
      expect(children.single.title, '补充');
    },
  );

  test('parses directory names from mixed path separators', () {
    expect(mobileDocumentImportDirectoryName('/tmp/cache/资料/'), '资料');
    expect(mobileDocumentImportDirectoryName(r'C:\Users\docs\lore'), 'lore');
  });
}
