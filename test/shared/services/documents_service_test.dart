// 职责: 测试文档服务 — 验证目录导入与文档持久化行为。
// 关联文件:
//   lib/shared/services/documents_service.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:io';

import 'package:charset/charset.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/documents_service.dart';

void main() {
  group('DocumentsService', () {
    late NovelContentDatabase db;
    late DocumentsService service;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      service = DocumentsService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('imports GBK encoded txt files from directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reveric_documents_import_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}${Platform.pathSeparator}设定.txt');
      await file.writeAsBytes(gbk.encode('灵气体系：山门、丹炉、阵法。'));

      final result = await service.importDirectory(
        type: documentTypeLore,
        directoryPath: tempDir.path,
      );

      final documents = await service.getDocumentsByType(documentTypeLore);
      expect(result.imported, 1);
      expect(result.skipped, 0);
      expect(documents, hasLength(1));
      expect(documents.single.title, '设定');
      expect(documents.single.content, '灵气体系：山门、丹炉、阵法。');
    });

    test('imports a csv file as one document', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reveric_documents_csv_import_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}${Platform.pathSeparator}人物表.csv');
      await file.writeAsString('姓名,身份,备注\n林深,主角,创业翻身\n"侧,写",配角,引用');

      final result = await service.importFile(
        type: documentTypeMaterial,
        filePath: file.path,
      );

      final documents = await service.getDocumentsByType(documentTypeMaterial);
      expect(result.imported, 1);
      expect(result.skipped, 0);
      expect(documents, hasLength(1));
      expect(documents.single.title, '人物表');
      expect(documents.single.content, contains('姓名,身份,备注'));
      expect(documents.single.content, contains('"侧,写"'));
    });

    test('imports a single text file', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reveric_documents_file_import_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}${Platform.pathSeparator}资料.md');
      await file.writeAsString('这里记录一段素材。');

      final result = await service.importFile(
        type: documentTypeMaterial,
        filePath: file.path,
      );

      final documents = await service.getDocumentsByType(documentTypeMaterial);
      expect(result.imported, 1);
      expect(result.skipped, 0);
      expect(documents, hasLength(1));
      expect(documents.single.title, '资料');
      expect(documents.single.content, '这里记录一段素材。');
    });

    test(
      'imports a large text file as one document without truncation',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'reveric_documents_large_import_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final content = List.filled(12000, '长').join();
        final file = File('${tempDir.path}${Platform.pathSeparator}长文.txt');
        await file.writeAsString(content);

        final result = await service.importFile(
          type: documentTypeLore,
          filePath: file.path,
        );

        final documents = await service.getDocumentsByType(documentTypeLore);
        expect(result.imported, 1);
        expect(result.skipped, 0);
        expect(documents, hasLength(1));
        expect(documents.single.title, '长文');
        expect(documents.single.content, content);
      },
    );

    test(
      'imports multiple files at once, aggregating counts and upserting duplicates',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'reveric_documents_multi_import_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final separator = Platform.pathSeparator;
        final worldFile = File('${tempDir.path}$separator世界.txt');
        await worldFile.writeAsString('旧版世界设定。');
        final charactersFile = File('${tempDir.path}$separator人物.md');
        await charactersFile.writeAsString('林深：主角。');
        final emptyFile = File('${tempDir.path}$separator空.txt');
        await emptyFile.writeAsString('');

        // 先占一个同名文档，验证批量导入对同名文件走 upsert 而不是重复建。
        await service.createDocument(type: documentTypeLore, title: '世界');

        final result = await service.importFiles(
          type: documentTypeLore,
          filePaths: [worldFile.path, charactersFile.path, emptyFile.path],
        );

        final documents = await service.getDocumentsByType(documentTypeLore);
        expect(result.imported, 2);
        expect(result.skipped, 1);
        expect(documents, hasLength(2));
        final world = documents.firstWhere((d) => d.title == '世界');
        expect(world.content, '旧版世界设定。');
        expect(documents.any((d) => d.title == '人物'), isTrue);
      },
    );

    test(
      'rejects duplicate active titles in the same root directory',
      () async {
        await service.createDocument(type: documentTypeLore, title: '世界设定');

        await expectLater(
          service.createFolder(type: documentTypeLore, title: '世界设定'),
          throwsArgumentError,
        );
      },
    );

    test('allows reusing a soft-deleted document title', () async {
      await db.customStatement('''
        INSERT INTO documents (
          id, type, title, created_at, updated_at, deleted_at
        ) VALUES ('deleted_document', 'lore', '世界设定', 0, 0, 1)
      ''');

      final id = await service.createDocument(
        type: documentTypeLore,
        title: '世界设定',
      );

      final document = await service.getDocumentByTitle(
        type: documentTypeLore,
        title: '世界设定',
      );
      expect(document?.id, id);
    });

    test('rejects moving a document into a duplicate title scope', () async {
      final leftFolderId = await service.createFolder(
        type: documentTypeLore,
        title: '左侧',
      );
      final rightFolderId = await service.createFolder(
        type: documentTypeLore,
        title: '右侧',
      );
      final movingDocumentId = await service.createDocument(
        type: documentTypeLore,
        parentId: leftFolderId,
        title: '设定',
      );
      await service.createDocument(
        type: documentTypeLore,
        parentId: rightFolderId,
        title: '设定',
      );

      await expectLater(
        service.moveDocument(id: movingDocumentId, newParentId: rightFolderId),
        throwsArgumentError,
      );
    });

    test('createDocument rejects path-structural chars in title', () async {
      await expectLater(
        service.createDocument(type: documentTypeLore, title: 'Who?'),
        throwsArgumentError,
      );
      await expectLater(
        service.createDocument(type: documentTypeLore, title: 'a/b'),
        throwsArgumentError,
      );
    });
  });
}
