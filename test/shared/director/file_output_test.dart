// 职责: 验证文件恢复的工程身份、灯光采样与宿主关闭后的选择生命周期。
// 关联文件:
//   lib/shared/services/director/file_output.dart
//   lib/shared/services/director/storage.dart
//   lib/shared/services/director/session.dart
import 'dart:async';
import 'dart:io';
import '../../fixtures/director/animated.dart';
import 'package:reveric/shared/models/director/sampling.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/file_output.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/services/director/storage.dart';

class _PendingImportStorage extends DirectorStorage {
  _PendingImportStorage() : super(Directory.systemTemp, Directory.systemTemp);

  final selection = Completer<DirectorDocument?>();

  @override
  Future<DirectorDocument?> importDocument() => selection.future;
}

void main() {
  test(
    'file restore remaps document lighting identity and saves readable animation',
    () async {
      final source = animatedDirectorDocument();
      final storage = _PendingImportStorage();
      DirectorDocument? saved;
      final target = DirectorDocument.blank('Target');
      final session = DirectorSession(
        target,
        onSave: (d) async {
          saved = DirectorDocument.parse(d.encode());
          return null;
        },
      );
      final output = DirectorFileOutput(storage, session);
      final importing = output.importDocument();
      storage.selection.complete(source);
      await importing;
      await session.save();
      expect(saved!.id, target.id);
      expect(saved!.objects, source.objects);
      expect(saved!.cameras, source.cameras);
      expect(
        saved!.tracks
            .where((t) => t['property'].startsWith('lighting.'))
            .single['target_id'],
        target.id,
      );
      for (final frame in [0, 24, 48, 96]) {
        expect(
          sampleDocument(saved!, frame).lighting,
          sampleDocument(source, frame).lighting,
        );
      }
      session.restore(saved!);
      expect(session.history.document.businessContent, saved!.businessContent);
      session.history.undo();
      expect(session.history.document.businessContent, target.businessContent);
      output.dispose();
      session.dispose();
    },
  );

  test(
    'file picker completion after close leaves disposed session alone',
    () async {
      final storage = _PendingImportStorage();
      final session = DirectorSession(DirectorDocument.blank('Original'));
      final output = DirectorFileOutput(storage, session);
      final importing = output.importDocument();

      output.dispose();
      session.dispose();
      storage.selection.complete(DirectorDocument.blank('Imported'));

      await expectLater(importing, completes);
      expect(session.history.document.title, 'Original');
    },
  );
}
