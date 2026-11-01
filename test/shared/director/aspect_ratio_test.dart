// 职责: 验证画幅持久化、自适应尺寸、撤销重做与导出快照的稳定性。
// 关联文件:
//   lib/shared/models/director/aspect_ratio.dart
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/services/director/session.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/aspect_ratio.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/session.dart';

void main() {
  test('new projects and reopened blank documents follow first viewport', () {
    for (final document in [
      DirectorDocument.blank('scene'),
      DirectorDocument.parse(DirectorDocument.blank('round trip').encode()),
    ]) {
      expect(document.aspectRatio, DirectorAspectRatio.adaptive);
      final history = CommandHistory(document);
      addTearDown(history.dispose);
      history.updateViewportSize(1000, 600);
      expect((history.document.width, history.document.height), (1200, 720));
      expect(history.undoCount, 0);
      expect(
        DirectorDocument.parse(history.document.encode()).aspectRatio,
        DirectorAspectRatio.adaptive,
      );
    }
  });

  test('saved fixed proportions survive opening in a different viewport', () {
    final history = CommandHistory(
      DirectorDocument.parse(
        File('test/fixtures/director/motion.director.json').readAsStringSync(),
      ),
    );
    addTearDown(history.dispose);
    history.updateViewportSize(1000, 600);
    expect(history.document.aspectRatio, DirectorAspectRatio.vertical);
    expect((history.document.width, history.document.height), (720, 1280));
    expect(history.dirty, false);
  });

  test('fixed presets round trip with even dimensions and undo atomically', () {
    final history = CommandHistory(DirectorDocument.blank('scene'));
    addTearDown(history.dispose);
    for (final aspect in DirectorAspectRatio.values.skip(1)) {
      final before = history.document;
      history.setAspectRatio(aspect);
      final saved = DirectorDocument.parse(history.document.encode());
      expect(saved.aspectRatio, aspect);
      expect((saved.width, saved.height), (aspect.width, aspect.height));
      expect(saved.width.isEven && saved.height.isEven, true);
      expect(saved.toJson()['output'].containsKey('aspect_mode'), false);
      history.undo();
      expect(history.document.businessContent, before.businessContent);
      history.redo();
      expect(history.document.aspectRatio, aspect);
    }
  });

  test(
    'auto follows viewport without adding undo steps or changing an export snapshot',
    () {
      final history = CommandHistory(
        DirectorDocument.parse(
          File(
            'test/fixtures/director/motion.director.json',
          ).readAsStringSync(),
        ),
      );
      addTearDown(history.dispose);
      history.updateViewportSize(1000, 600);
      history.setAspectRatio(DirectorAspectRatio.adaptive);
      expect((history.document.width, history.document.height), (1200, 720));
      expect(history.undoCount, 1);
      final exportSnapshot = history.document;
      history.markSaved(exportSnapshot);
      history.updateViewportSize(400, 800);
      expect((history.document.width, history.document.height), (720, 1440));
      expect(history.undoCount, 1);
      expect(history.dirty, true);
      expect((exportSnapshot.width, exportSnapshot.height), (1200, 720));
      final revision = history.document.revision;
      history.updateViewportSize(800, 1600);
      expect(history.document.revision, revision);
      history.undo();
      expect(history.document.aspectRatio, DirectorAspectRatio.vertical);
      history.redo();
      expect(history.document.aspectRatio, DirectorAspectRatio.adaptive);
      expect((history.document.width, history.document.height), (720, 1440));
      history.setAspectRatio(DirectorAspectRatio.square);
      history.updateViewportSize(1000, 500);
      expect((history.document.width, history.document.height), (720, 720));
      history.undo();
      expect(history.document.aspectRatio, DirectorAspectRatio.adaptive);
      expect((history.document.width, history.document.height), (1440, 720));
    },
  );

  test('saved auto mode reopens and resolves against its new viewport', () {
    final original = CommandHistory(DirectorDocument.blank('scene'));
    addTearDown(original.dispose);
    original.updateViewportSize(1000, 600);
    original.setAspectRatio(DirectorAspectRatio.adaptive);
    final reopened = CommandHistory(
      DirectorDocument.parse(original.document.encode()),
    );
    addTearDown(reopened.dispose);
    expect(reopened.document.aspectRatio, DirectorAspectRatio.adaptive);
    expect((reopened.document.width, reopened.document.height), (1200, 720));
    reopened.updateViewportSize(800, 800);
    expect((reopened.document.width, reopened.document.height), (720, 720));
    expect(reopened.undoCount, 0);
    expect(reopened.dirty, true);
  });

  test('viewport resizing preserves playback and pending property input', () {
    final session = DirectorSession(DirectorDocument.blank('scene'));
    addTearDown(session.dispose);
    session.history.setAspectRatio(DirectorAspectRatio.adaptive);
    session.play();
    session.hasPendingInput = true;
    session.history.updateViewportSize(1000, 500);
    expect(session.playing, true);
    expect(session.hasPendingInput, true);
    expect(
      (session.history.document.width, session.history.document.height),
      (1440, 720),
    );
  });

  test(
    'auto sizing bounds allocation and rejects invalid stored dimensions',
    () {
      for (final (width, height) in [
        (333.0, 777.0),
        (20000.0, 50.0),
        (1.0, 10000.0),
      ]) {
        final size = adaptiveOutputSize(width, height);
        expect(size.$1, inInclusiveRange(2, 1920));
        expect(size.$2, inInclusiveRange(2, 1920));
        expect(size.$1.isEven && size.$2.isEven, true);
      }
      final doc = DirectorDocument.blank('scene');
      for (final edit in <void Function(Json)>[
        (j) => j['output']['width'] = 721,
        (j) => j['output']['width'] = 4096,
        (j) => j['output']['height'] = 0,
        (j) => j['output']['aspect_mode'] = 'unknown',
      ]) {
        expect(
          () => doc.mutate((j) {
            j['output']['aspect_mode'] = 'auto';
            edit(j);
          }),
          throwsA(isA<DocumentError>()),
        );
      }
    },
  );
}
