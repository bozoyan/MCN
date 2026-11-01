// 职责: 验证属性字段即时提交、逐项关键帧、未提交草稿的保护与对象行右键删除。
// 关联文件:
//   lib/shared/widgets/director/inspector.dart
//   lib/shared/widgets/director/panels/common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'dart:io';
import 'dart:math' as math;
import 'package:reveric/shared/models/director/sampling.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/widgets/director/inspector.dart';
import 'package:reveric/shared/widgets/director/track_editor.dart';
import 'package:reveric/shared/widgets/director/panels/objects.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDirectorTest);
  setUp(() {
    rootBundle.clear();
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'height and XYZ rotation edit and keyframe on $platform',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(375, 812)
            : const Size(800, 900);
        addTearDown(tester.view.reset);
        final d = DirectorDocument.parse(
          File('test/fixtures/director/scene.director.json').readAsStringSync(),
        );
        final s = DirectorSession(d)..select(d.objects.first['id']);
        await tester.pumpWidget(
          directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
        );
        await tester.pumpAndSettle();
        Future<void> edit(String name, String value) async {
          final field = find.byKey(ValueKey('director-field:$name'));
          await tester.ensureVisible(field);
          await tester.enterText(field, value);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(s.hasPendingInput, isFalse);
          expect(s.error, isNull);
        }

        await edit('position:1', '2.5');
        await edit('rotation:0', '30');
        await edit('rotation:1', '45');
        await edit('rotation:2', '60');
        final object = s.history.document.objects.first;
        expect(object['position'][1], 2.5);
        final angles = quaternionEuler(object['rotation']);
        for (var i = 0; i < 3; i++) {
          expect(angles[i], closeTo([30, 45, 60][i] * math.pi / 180, 1e-9));
        }
        s.seek(24);
        await tester.pumpAndSettle();
        for (final property in ['position', 'rotation']) {
          final key = find.byKey(ValueKey('director-key:$property'));
          await tester.ensureVisible(key);
          await tester.tap(key);
          await tester.pumpAndSettle();
        }
        await edit('position:1', '4');
        await edit('rotation:0', '90');
        expect(
          sampleDocument(s.history.document, 24).objects.first['position'][1],
          4,
        );
        final q =
            sampleDocument(s.history.document, 24).objects.first['rotation']
                as List;
        final expected = eulerQuaternion([
          math.pi / 2,
          math.pi / 4,
          math.pi / 3,
        ]);
        for (var i = 0; i < 4; i++) {
          expect(q[i], closeTo(expected[i], 1e-9));
        }
        s.history.undo();
        await tester.pumpAndSettle();
        expect(
          sampleDocument(s.history.document, 24).objects.first['rotation'],
          object['rotation'],
        );
        await tester.pumpWidget(const SizedBox.shrink());
        s.dispose();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
  testWidgets('keyframe dialog preserves existing tilt and edits XYZ degrees', (
    tester,
  ) async {
    final d = DirectorDocument.parse(
      File('test/fixtures/director/scene.director.json').readAsStringSync(),
    );
    final s = DirectorSession(d);
    final id = d.objects.first['id'];
    final initial = eulerQuaternion([0.3, 0.4, -0.5]);
    s.history.intervalKeys(id, 'rotation', 0, 48, initial);
    await tester.pumpWidget(
      directorTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editTrackOrClip(
              context,
              s,
              s.history.document.tracks.singleWhere(
                (t) => t['target_id'] == id && t['property'] == 'rotation',
              ),
            ),
            child: const Text('Edit key'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openKey() async {
      await tester.tap(find.text('Edit key'));
      await tester.pumpAndSettle();
      final row = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.title is Text &&
            ((w.title as Text).data ?? '').startsWith('48 ·'),
      );
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    await openKey();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      sampleDocument(s.history.document, 48).objects.first['rotation'],
      initial,
    );
    await openKey();
    final value = find.byKey(const ValueKey('director-key-value'));
    await tester.enterText(value, '45, 60, -90');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final actual =
        sampleDocument(s.history.document, 48).objects.first['rotation']
            as List;
    final expected = eulerQuaternion([math.pi / 4, math.pi / 3, -math.pi / 2]);
    for (var i = 0; i < 4; i++) {
      expect(actual[i], closeTo(expected[i], 1e-9));
    }
    expect(find.byKey(const ValueKey('director-key-value')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('fields commit on submit and key button creates a track', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('director_controls_');
    final d = DirectorDocument.parse(
      File('test/fixtures/director/scene.director.json').readAsStringSync(),
    );
    final id = d.objects.first['id'];
    final s = DirectorSession(d)..select(id);
    await tester.pumpWidget(
      directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
    );
    await tester.pumpAndSettle();
    final x = find.byKey(const ValueKey('director-field:position:0'));
    await tester.enterText(x, '1.5');
    expect(s.hasPendingInput, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.history.document.objects.first['position'][0], 1.5);
    expect(s.hasPendingInput, isFalse);
    await tester.tap(find.byKey(const ValueKey('director-key:position')));
    await tester.pump();
    final track = s.history.document.tracks.singleWhere(
      (t) => t['target_id'] == id && t['property'] == 'position',
    );
    expect(track['keys'].first['frame'], 0);
    for (final property in ['scale', 'color', 'visible']) {
      final key = find.byKey(ValueKey('director-key:$property'));
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pumpAndSettle();
      final t = s.history.document.tracks.singleWhere(
        (t) => t['target_id'] == id && t['property'] == property,
      );
      expect(
        t['keys'].single['value'],
        s.history.document.objects.first[property],
      );
      if (property == 'visible') {
        expect(t['keys'].single['easing'], 'hold');
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
    root.deleteSync(recursive: true);
  });
  testWidgets(
    'uncommitted property survives selection and object creation attempts',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('director_pending_');
      final d = DirectorDocument.parse(
        File('test/fixtures/director/scene.director.json').readAsStringSync(),
      );
      final session = DirectorSession(d)..select(d.objects.first['id']);
      await tester.pumpWidget(
        directorTestApp(Inspector(session: session, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('director-field:name'));
      await tester.enterText(name, 'Keep this draft');
      session.select(d.objects[1]['id']);
      await tester.pump();
      expect(session.selected, d.objects.first['id']);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(
        () => session.history.addObject('prop.cube.v1', 'Box'),
        throwsA(isA<DocumentError>()),
      );
      expect(session.history.document.objects.length, 3);
      await expectLater(session.save(), throwsA(isA<DocumentError>()));
      expect(File('${root.path}/current.json').existsSync(), isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(session.history.document.objects.first['name'], 'Keep this draft');
      expect(session.hasPendingInput, false);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      root.deleteSync(recursive: true);
    },
  );
  testWidgets('right click deletes an object but not the last camera', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('director_menu_');
    final d = DirectorDocument.parse(
      File('test/fixtures/director/scene.director.json').readAsStringSync(),
    );
    final s = DirectorSession(d);
    final keep = d.activeCameras.first['id'];
    for (final c in d.activeCameras.skip(1)) {
      s.history.remove(c['id']);
    }
    await tester.pumpWidget(
      directorTestApp(
        Material(
          child: ListenableBuilder(
            listenable: s.history,
            builder: (_, _) => DirectorObjectsPanel(session: s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> rightClick(String id) async {
      await tester.tap(
        find.byKey(ValueKey('director-object:$id')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    final actor = d.objects.first['id'];
    await rightClick(actor);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(s.history.document.objects.where((o) => o['id'] == actor), isEmpty);
    await rightClick(keep);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(s.history.document.camera(keep), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
    root.deleteSync(recursive: true);
  });
}
