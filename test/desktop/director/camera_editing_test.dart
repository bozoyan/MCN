// 职责: 验证相机完整目标、关键帧限制、自由旋转与真实光学参数编辑。
// 关联文件:
//   lib/shared/widgets/director/inspector/camera.dart
//   lib/shared/services/director/commands.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/widgets/director/inspector.dart';
import 'harness.dart';
import 'package:reveric/shared/widgets/director/frame_content.dart';
import 'package:reveric/shared/widgets/director/viewport.dart';
import 'package:reveric/shared/widgets/director/timeline.dart';
import 'package:reveric/shared/widgets/director/camera_preview.dart';

void main() {
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());
  testWidgets(
    'two invalid restored cameras can be repaired separately while new errors remain atomic',
    (tester) async {
      final source = DirectorDocument.blank('Two invalid cameras').mutate((j) {
        j['cameras'][0]['position'] = [0, 1.6, 0];
        j['cameras'].add(
          DirectorDocument.newCamera('B', [0, 1.6, 0], [0, 1, 0], 35),
        );
      });
      final s = DirectorSession(DirectorDocument.blank('Host'));
      s.restore(source);
      s.seek(12);
      final a = s.history.document.cameras.first['id'],
          b = s.history.document.cameras.last['id'];
      s.select(a);
      await tester.pumpWidget(
        directorTestApp(
          Column(
            children: [
              SizedBox(
                height: 140,
                child: DirectorFrameContent(
                  session: s,
                  builder: (_) =>
                      const SizedBox(key: ValueKey('repaired-frame')),
                ),
              ),
              Expanded(
                child: Inspector(session: s, onAlignToView: (_) {}),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('director-field:camera_position:2'),
      );
      Future<void> edit(String value) async {
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await edit('2');
      expect(s.error, isNull);
      expect(s.history.document.camera(a)!['position'][2], 2);
      expect(
        find.byKey(const ValueKey('director-frame-diagnostic')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('director-inspector-diagnostic')),
            )
            .data,
        contains(b),
      );
      final before = s.history.document, undo = s.history.undoCount;
      await edit('0');
      expect(s.error, contains('parallel_reference_up'));
      expect(s.history.document, same(before));
      expect(s.history.undoCount, undo);
      await edit('2');
      s.select(b);
      await tester.pumpAndSettle();
      await edit('2');
      expect(s.error, isNull);
      expect(find.byKey(const ValueKey('repaired-frame')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('director-inspector-diagnostic')),
        findsNothing,
      );
      expect(sampleDocument(s.history.document, 12).cameras.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'external animation can seek an invalid frame and repair its key without losing controls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = DirectorDocument.blank('Camera');
      final id = base.cameras.single['id'];
      final external = base.mutate(
        (j) => j['tracks'] = [
          {
            'id': '40000000-0000-4000-8000-000000000009',
            'target_id': id,
            'property': 'position',
            'keys': [
              {
                'frame': 0,
                'value': [0, 1.6, 5],
                'easing': 'linear',
              },
              {
                'frame': 24,
                'value': [0, 1, 0],
                'easing': 'hold',
              },
            ],
          },
        ],
      );
      final s = DirectorSession(base);
      s.restore(external);
      s.select(id);
      // An invalid future frame must not block a valid current-frame edit.
      s.history.setValue(id, 'focal_length_mm', 40, 0);
      expect(s.history.document.cameras.single['focal_length_mm'], 40);
      await tester.pumpWidget(
        directorTestApp(
          Column(
            children: [
              SizedBox(
                height: 160,
                child: DirectorFrameContent(
                  session: s,
                  builder: (_) =>
                      const SizedBox(key: ValueKey('valid-frame-content')),
                ),
              ),
              Expanded(
                child: Inspector(session: s, onAlignToView: (_) {}),
              ),
              DirectorTimeline(session: s),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('valid-frame-content')), findsOneWidget);
      s.seek(24);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('director-frame-diagnostic')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('director-inspector-diagnostic')),
        findsOneWidget,
      );
      final field = find.byKey(
        const ValueKey('director-field:camera_position:2'),
      );
      expect(tester.widget<TextField>(field).enabled, isTrue);
      expect(tester.widget<TextField>(field).controller!.text, '0.00');
      s.seek(0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('director-frame-diagnostic')),
        findsNothing,
      );
      s.seek(24);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.enterText(field, '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(s.error, isNull);
      expect(
        find.byKey(const ValueKey('director-inspector-diagnostic')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('valid-frame-content')), findsOneWidget);
      expect(sampleDocument(s.history.document, 24).cameras[id]!['position'], [
        0,
        1,
        2,
      ]);
      s.history.undo();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('director-frame-diagnostic')),
        findsOneWidget,
      );
      s.history.redo();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('valid-frame-content')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'native viewport rejects an invalid imported frame before constructing its scene',
    (tester) async {
      final external = DirectorDocument.blank(
        'Camera',
      ).mutate((j) => j['cameras'][0]['position'] = [0, 1.6, 0]);
      final s = DirectorSession(DirectorDocument.blank('Target'));
      s.restore(external);
      final view = ViewState();
      await tester.pumpWidget(
        directorTestApp(DirectorViewport(session: s, view: view)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('director-frame-diagnostic')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      view.dispose();
      s.dispose();
    },
  );

  testWidgets(
    'invalid camera input retains committed state and can be corrected',
    (tester) async {
      final s = DirectorSession(DirectorDocument.blank('Camera'));
      s.select(s.history.document.activeCameras.first['id']);
      final before = s.history.document.businessContent;
      await tester.pumpWidget(
        directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('director-field:camera_position:2'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(s.error, contains('parallel_reference_up'));
      expect(s.history.document.businessContent, before);
      expect(s.history.undoCount, 0);
      await tester.enterText(field, '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.history.document.cameras.single['position'][2], 2);
      expect(s.history.undoCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'global cut row, default and fixed observation share the same frame',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final d = DirectorDocument.parse(
        File('test/fixtures/director/scene.director.json').readAsStringSync(),
      );
      final s = DirectorSession(d);
      final first = d.cameras.first['id'], second = d.cameras[1]['id'];
      await tester.pumpWidget(
        directorTestApp(
          Column(
            children: [
              SizedBox(
                width: 320,
                child: DirectorCameraPreview(
                  session: s,
                  viewportBuilder: (_, _) => const SizedBox(),
                ),
              ),
              Expanded(
                child: Inspector(session: s, onAlignToView: (_) {}),
              ),
              DirectorTimeline(session: s),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pristine = s.history.document.businessContent;
      s.viewCamera(second);
      s.seek(48);
      await tester.pumpAndSettle();
      expect(s.history.document.businessContent, pristine);
      final add = find.byKey(const ValueKey('director-add-cut'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      final cut = s.history.document.cuts.single;
      expect(cut['frame'], 48);
      expect(cut['camera_id'], second);
      s.viewCamera(null);
      s.seek(47);
      expect(s.viewCameraId, first);
      s.seek(48);
      expect(s.viewCameraId, second);
      s.viewCamera(first);
      expect(s.viewCameraId, first);
      await tester.pumpAndSettle();
      final marker = find.byKey(ValueKey('director-cut-marker:${cut['id']}'));
      await tester.ensureVisible(marker);
      await tester.tap(marker);
      await tester.pumpAndSettle();
      expect(s.cameraMode, 'sequence');
      expect(s.viewCameraId, second);
      expect(find.byKey(const ValueKey('director-cut-lane')), findsOneWidget);
      final frame = find.byKey(ValueKey('director-cut-frame:${cut['id']}'));
      await tester.ensureVisible(frame);
      await tester.enterText(frame, '72');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(s.history.document.cuts.single['frame'], 72);
      final defaultField = find.byKey(
        const ValueKey('director-default-camera'),
      );
      tester.widget<RevericSelect<String>>(defaultField).onChanged(second);
      await tester.pumpAndSettle();
      s.seek(0);
      expect(s.viewCameraId, second);
      final more = find.byKey(ValueKey('director-cut-more:${cut['id']}'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(s.history.document.cuts, isEmpty);
      s.history.undo();
      expect(s.history.document.cuts.single['frame'], 72);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'target reference, offset, hold key and hidden timeline stay coherent',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final d = DirectorDocument.parse(
        File('test/fixtures/director/scene.director.json').readAsStringSync(),
      );
      final id = d.activeCameras.first['id'];
      final s = DirectorSession(d)..select(id);
      await tester.pumpWidget(
        directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      Future<void> choose(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        tester.widget<RevericSelect<String>>(field).onChanged(value);
        await tester.pumpAndSettle();
        expect(s.error, isNull);
      }

      Future<void> edit(String key, String value) async {
        final field = find.byKey(ValueKey('director-field:$key'));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(s.error, isNull);
      }

      await choose('director-target-type', 'object');
      expect(
        s.history.document.camera(id)!['camera_target']['object_id'],
        d.objects.first['id'],
      );
      await choose('director-target-type', 'bone');
      await choose('director-target-bone', 'head');
      await edit('camera_target:1', '0.2');
      s.seek(24);
      await tester.pumpAndSettle();
      final key = find.byKey(
        const ValueKey('director-key:camera:camera_target'),
      );
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pumpAndSettle();
      final track = s.history.document.tracks.singleWhere(
        (t) => t['target_id'] == id && t['property'] == 'camera_target',
      );
      expect(track['keys'].single['value'], {
        'type': 'bone',
        'actor_id': d.objects.first['id'],
        'bone': 'head',
        'offset': [0, 0.2, 0],
      });
      await choose('director-easing:camera_target', 'hold');
      s.seek(30);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('director-field:camera_target:1')),
            )
            .enabled,
        false,
      );
      s.history.autoKey = true;
      s.refresh();
      await tester.pumpAndSettle();
      await edit('camera_target:1', '0.4');
      expect(
        s.history.document.tracks
            .singleWhere(
              (t) => t['target_id'] == id && t['property'] == 'camera_target',
            )['keys']
            .length,
        2,
      );
      s.history.timelineVisible = false;
      s.refresh();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('director-key:camera:camera_target')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('director-field:camera_target:1')),
            )
            .enabled,
        false,
      );
      await edit('sensor_height_mm', '30');
      await edit('focus_distance_m', '2.5');
      await edit('aperture_fstop', '1.4');
      expect(
        sampleDocument(s.history.document, 30).cameras[id]!['focus_distance_m'],
        2.5,
      );
      expect(
        sampleDocument(s.history.document, 30).cameras[id]!['aperture_fstop'],
        1.4,
      );
      // 时长、切镜和灯光属于整个导演台：机位属性里没有，取消选中后在导演台属性里编辑。
      expect(
        find.byKey(const ValueKey('director-field:duration')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('director-field:lighting.ambient_intensity')),
        findsNothing,
      );
      s.select(null);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('director-field:duration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('director-default-camera')),
        findsOneWidget,
      );
      await edit('lighting.ambient_intensity', '1.2');
      expect(
        sampleDocument(s.history.document, 30).lighting['ambient_intensity'],
        1.2,
      );
      s.history.timelineVisible = true;
      s.refresh();
      await tester.pumpAndSettle();
      final lightKey = find.byKey(
        const ValueKey('director-key:camera:lighting.key_intensity'),
      );
      await tester.ensureVisible(lightKey);
      await tester.tap(lightKey);
      await tester.pumpAndSettle();
      await edit('lighting.key_intensity', '2.5');
      expect(
        s.history.document.tracks
            .singleWhere(
              (t) => t['property'] == 'lighting.key_intensity',
            )['keys']
            .single['value'],
        2.5,
      );

      expect(
        sampleDocument(s.history.document, 30).cameras[id]!['sensor_height_mm'],
        30,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets('free mode retains framing and degree edits commit one undo', (
    tester,
  ) async {
    final d = DirectorDocument.blank('Camera');
    final id = d.activeCameras.first['id'];
    final s = DirectorSession(d)..select(id);
    await tester.pumpWidget(
      directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
    );
    await tester.pumpAndSettle();
    final before = sampleDocument(d, 0).cameras[id]!['rotation'];
    tester
        .widget<RevericSelect<String>>(
          find.byKey(const ValueKey('director-camera-mode')),
        )
        .onChanged('free');
    await tester.pumpAndSettle();
    expect(s.error, isNull);
    expect(s.history.document.camera(id)!['rotation'], before);
    final count = s.history.undoCount;
    final field = find.byKey(
      const ValueKey('director-field:camera_rotation:2'),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(s.error, isNull);
    expect(s.history.undoCount, count + 1);
    expect(
      quaternionEuler(s.history.document.camera(id)!['rotation'])[2],
      closeTo(20 * 3.141592653589793 / 180, 1e-8),
    );
    s.history.undo();
    expect(s.history.document.camera(id)!['rotation'], before);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
}
