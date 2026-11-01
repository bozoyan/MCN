// 职责: 验证桌面画布导出文件名、取消、选择失败与部分写入时的文件安全。
// 关联文件:
//   lib/shared/services/canvas_export/save.dart
//   lib/shared/models/canvas_export.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/file-access.md

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/canvas_export.dart';
import 'package:reveric/shared/services/canvas_export/save.dart';

void main() {
  CanvasExportArtifact artifact(CanvasExportFormat format) =>
      CanvasExportArtifact(
        format: format,
        title: '中文/画布\\../\u0001:*?',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
  test('safe Chinese filenames cannot add paths or reserved device names', () {
    final name = canvasExportFileName(
      '中文/画布\\../\u0001:*?',
      CanvasExportFormat.zip,
    );
    expect(name, startsWith('中文'));
    expect(name, endsWith('.zip'));
    expect(name, isNot(matches(RegExp(r'[\x00-\x1f<>:"/\\|?*]'))));
    expect(canvasExportFileName('CON', CanvasExportFormat.json), '_CON.json');
    expect(canvasExportFileName('..', CanvasExportFormat.zip), 'Canvas.zip');
    expect(
      utf8
          .encode(canvasExportFileName('中' * 500, CanvasExportFormat.zip))
          .length,
      lessThanOrEqualTo(255),
    );
  });
  for (final format in CanvasExportFormat.values) {
    for (final scalar in ['中', '😀']) {
      test(
        'long $scalar title saves the unchanged suggested ${format.name} name to disk',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'canvas_unicode_name_',
          );
          addTearDown(() => directory.delete(recursive: true));
          final bytes = Uint8List.fromList(utf8.encode('完整导出正文\n😀 中文'));
          final title = scalar * 500;
          final export = CanvasExportArtifact(
            format: format,
            title: title,
            bytes: bytes,
          );
          late String suggested, path;
          final saved = await saveCanvasExport(
            export,
            chooseLocation: (name, _) async {
              suggested = name;
              path = '${directory.path}/$name';
              return path;
            },
          );
          expect(saved.status, CanvasExportSaveStatus.saved);
          expect(utf8.encode(suggested).length, lessThanOrEqualTo(255));
          final stem = suggested.substring(
            0,
            suggested.length - format.name.length - 1,
          );
          expect(
            stem.runes.every((rune) => rune == scalar.runes.single),
            isTrue,
          );
          expect(suggested, isNot(contains('�')));
          expect(await File(path).readAsBytes(), bytes);
          expect(export.title, title);
        },
      );
    }
    test(
      'truncation rechecks trailing dots, spaces and reserved names for ${format.name}',
      () {
        final budget = 255 - '.${format.name}'.length;
        for (final title in [
          '${'A' * (budget - 1)}.after',
          '${'A' * (budget - 1)} after',
          'CON${' ' * budget}after',
          'CON.${'中' * 500}',
        ]) {
          final name = canvasExportFileName(title, format);
          final stem = name.substring(0, name.length - format.name.length - 1);
          expect(utf8.encode(name).length, lessThanOrEqualTo(255));
          expect(stem, isNot(endsWith('.')));
          expect(stem, isNot(endsWith(' ')));
          expect(stem.toUpperCase(), isNot('CON'));
          if (title.startsWith('CON')) {
            expect(stem, startsWith('_CON'));
          }
        }
      },
    );
  }

  test('cancelling or failing the picker never starts a write', () async {
    var writes = 0;
    final cancelled = await saveCanvasExport(
      artifact(CanvasExportFormat.zip),
      chooseLocation: (_, _) async => null,
      writeFile: (_, _) async {
        writes++;
      },
    );
    expect(cancelled.status, CanvasExportSaveStatus.cancelled);
    expect(writes, 0);
    final failed = await saveCanvasExport(
      artifact(CanvasExportFormat.zip),
      chooseLocation: (_, _) async =>
          throw const FileSystemException('permission'),
      writeFile: (_, _) async {
        writes++;
      },
    );
    expect(failed.status, CanvasExportSaveStatus.failed);
    expect(failed.mayHavePartialFile, isFalse);
    expect(writes, 0);
  });
  test(
    'successful writes preserve bytes and failures preserve external directory and partial target',
    () async {
      final dir = await Directory.systemTemp.createTemp('canvas_save_test_');
      addTearDown(() => dir.delete(recursive: true));
      final unrelated = File('${dir.path}/keep.txt');
      await unrelated.writeAsString('keep');
      final target = File('${dir.path}/中文.json');
      final saved = await saveCanvasExport(
        artifact(CanvasExportFormat.json),
        chooseLocation: (suggested, format) async {
          expect(format, CanvasExportFormat.json);
          expect(suggested, endsWith('.json'));
          return target.path;
        },
      );
      expect(saved.status, CanvasExportSaveStatus.saved);
      expect(await target.readAsBytes(), [1, 2, 3]);
      final failed = await saveCanvasExport(
        artifact(CanvasExportFormat.json),
        chooseLocation: (_, _) async => target.path,
        writeFile: (path, bytes) async {
          await File(path).writeAsBytes(bytes.take(1).toList());
          throw const FileSystemException('full');
        },
      );
      expect(failed.status, CanvasExportSaveStatus.failed);
      expect(failed.mayHavePartialFile, isTrue);
      expect(await target.readAsBytes(), [1]);
      expect(await unrelated.readAsString(), 'keep');
      expect(await dir.exists(), isTrue);
    },
  );
}
