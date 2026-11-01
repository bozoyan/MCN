// 职责: 验证姿态自动帧、完整键、时间轴显隐与可取消单次手势提交。
// 关联文件:
//   lib/shared/widgets/director/inspector/pose.dart
//   lib/shared/widgets/director/timeline_bar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/widgets/director/inspector.dart';
import 'package:reveric/shared/widgets/director/timeline.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());
  Future<void> openPose(WidgetTester tester) async {
    await tester.tap(find.text('Pose').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'out of world pose preview is rejected without losing the last valid preview',
    (tester) async {
      final s = DirectorSession(DirectorDocument.blank('Pose'));
      s.history.addObject('actor.male.v1', 'Actor');
      s.select(s.history.document.objects.single['id']);
      final before = s.history.document.businessContent;
      final undo = s.history.undoCount;
      await tester.pumpWidget(
        directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      await openPose(tester);
      final slider = find.byKey(
        const ValueKey('director-pose-slider:root_offset_y'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final start = tester.getCenter(slider);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(20, 0));
      await tester.pump();
      final validPreview = s.history.preview;
      expect(validPreview, isNotNull);
      await gesture.moveTo(Offset(tester.getRect(slider).right, start.dy));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(s.error, contains('world_position'));
      expect(s.history.preview, same(validPreview));
      expect(s.history.document.businessContent, before);
      expect(s.history.undoCount, undo);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(s.history.preview, isNull);
      expect(s.history.document.businessContent, before);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'copy paste reset preserve full pose height and reopen hold keys',
    (tester) async {
      final s = DirectorSession(DirectorDocument.blank('Pose'));
      s.history.addObject('actor.male.v1', 'Actor');
      final id = s.history.document.objects.single['id'];
      s.select(id);
      s.history.autoKey = true;
      s.seek(24);
      final pose = {
        ...s.history.document.objects.single['pose'] as Json,
        'root_offset_y': 0.3,
        'head_yaw': 42.0,
      };
      s.history.editProperty(id, 'pose', pose, 24);
      s.history.setKeyEasing(id, 'pose', 24, 'hold');
      await tester.pumpWidget(
        directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      await openPose(tester);
      Future<void> tap(String label) async {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(s.error, isNull);
      }

      await tap('Copy');
      s.seek(48);
      await tester.pumpAndSettle();
      await tap('Paste');
      expect(s.history.document.tracks.single['keys'].last['value'], pose);
      await tap('Reset to default');
      final reset = s.history.document.tracks.single['keys'].last['value'];
      expect(reset['root_offset_y'], 0);
      expect(reset['head_yaw'], 0);
      expect(reset.length, 26);
      expect(
        sampleDocument(s.history.document, 47).objects.single['pose'],
        pose,
      );
      expect(
        sampleDocument(s.history.document, 48).objects.single['pose'],
        reset,
      );
      final reopened = DirectorDocument.fromJson(s.history.document.toJson());
      expect(sampleDocument(reopened, 47).objects.single['pose'], pose);
      expect(sampleDocument(reopened, 48).objects.single['pose'], reset);
      s.history.undo();
      expect(s.history.document.tracks.single['keys'].last['value'], pose);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'auto key records the complete pose and hiding timeline preserves animation',
    (tester) async {
      final s = DirectorSession(DirectorDocument.blank('Scene'));
      s.history.addObject('actor.male.v1', 'Actor');
      s.select(s.history.document.objects.single['id']);
      s.seek(24);
      await tester.pumpWidget(
        directorTestApp(
          ListenableBuilder(
            listenable: s,
            builder: (context, _) => Column(
              children: [
                DirectorTimeline(session: s),
                Expanded(
                  child: Inspector(session: s, onAlignToView: (_) {}),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openPose(tester);
      await tester.tap(find.byKey(const ValueKey('director-auto-key')));
      await tester.pumpAndSettle();
      final height = find.byKey(
        const ValueKey('director-pose-value:root_offset_y'),
      );
      await tester.ensureVisible(height);
      await tester.enterText(height, '-0.4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.history.document.objects.single['pose']['root_offset_y'], 0);
      final key = s.history.document.tracks.single['keys'].single;
      expect(key['frame'], 24);
      expect(key['value'].length, 26);
      expect(key['value']['root_offset_y'], -0.4);
      s.seek(36);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('director-auto-key')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(height).enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('director-show-timeline')));
      await tester.pumpAndSettle();
      expect(s.frame.value, 36);
      expect(s.history.document.tracks, hasLength(1));
      expect(
        sampleDocument(
          s.history.document,
          36,
        ).objects.single['pose']['root_offset_y'],
        -0.4,
      );
      expect(tester.widget<TextField>(height).enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'pose slider previews live, cancels, and commits one undo per gesture',
    (tester) async {
      final s = DirectorSession(DirectorDocument.blank('Scene'));
      s.history.addObject('actor.male.v1', 'Actor');
      s.select(s.history.document.objects.single['id']);
      await tester.pumpWidget(
        directorTestApp(Inspector(session: s, onAlignToView: (_) {})),
      );
      await tester.pumpAndSettle();
      await openPose(tester);
      final slider = find.byKey(
        const ValueKey('director-pose-slider:head_yaw'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final count = s.history.undoCount,
          before = s.history.document.businessContent;
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(s.history.preview, isNotNull);
      expect(s.history.document.businessContent, before);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(s.history.preview, isNull);
      expect(s.history.undoCount, count);
      await tester.drag(slider, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.history.undoCount, count + 1);
      expect(s.history.document.objects.single['pose']['head_yaw'], isNot(0));
      expect(s.history.document.objects.single['pose']['root_offset_y'], 0);
      s.history.undo();
      expect(s.history.document.businessContent, before);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}
