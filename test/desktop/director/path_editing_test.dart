// 职责: 通过角色运动轨迹分区与实际视口指针事件验证五工具、控制柄、取消和撤销。
// 关联文件:
//   lib/shared/widgets/director/paths/panel.dart
//   lib/shared/widgets/director/paths/viewport.dart
//   lib/shared/services/director/path_edit.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as v;
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/camera.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/widgets/director/paths/panel.dart';
import 'package:reveric/shared/widgets/director/paths/viewport.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());
  DirectorSession session() {
    final s = DirectorSession(DirectorDocument.blank('Scene'));
    s.history.addObject('actor.male.v1', 'Actor');
    s.select(s.history.document.objects.single['id']);
    return s;
  }

  Widget harness(DirectorSession s, DirectorCamera camera) => directorTestApp(
    Row(
      children: [
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) =>
                  DirectorPathSection(session: s, actorId: s.selected!),
            ),
          ),
        ),
        Expanded(
          child: PathViewport(session: s, camera: camera),
        ),
      ],
    ),
  );
  Future<void> click(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  DirectorCamera camera() =>
      DirectorCamera(position: v.Vector3(0, 8, 8), target: v.Vector3.zero());
  Offset screen(
    WidgetTester tester,
    DirectorCamera camera,
    List<double> point,
  ) {
    final viewport = find.byKey(const ValueKey('director-path-viewport'));
    return tester.getTopLeft(viewport) +
        camera.worldToScreen(v.Vector3.array(point), tester.getSize(viewport))!;
  }

  testWidgets(
    'line circle rectangle create edit cancel delete and bake through the panel',
    (tester) async {
      final s = session();
      await tester.pumpWidget(harness(s, camera()));
      await tester.pumpAndSettle();
      for (final kind in ['line', 'circle', 'rectangle']) {
        final count = s.history.undoCount;
        await click(tester, 'director-path-create:$kind');
        expect(s.history.document.paths, isEmpty);
        await click(tester, 'director-path-cancel');
        expect(s.history.undoCount, count);
        await click(tester, 'director-path-create:$kind');
        await click(tester, 'director-path-finish');
        expect(s.error, isNull);
        expect(s.history.document.paths.single['kind'], kind);
        final field = find.byKey(
          ValueKey(
            kind == 'line'
                ? 'director-field:path-end:0:0'
                : kind == 'circle'
                ? 'director-path-radius'
                : 'director-path-width',
          ),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, '3');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(s.error, isNull);
        expect(s.history.undoCount, count + 2);
        final saved = s.history.document.businessContent;
        await click(tester, 'director-path-delete');
        expect(s.history.document.paths, isEmpty);
        s.history.undo();
        await tester.pumpAndSettle();
        expect(s.history.document.businessContent, saved);
        s.pathEditor.select(s.history.document.paths.single['id']);
        await tester.pumpAndSettle();
        await click(tester, 'director-path-bake');
        expect(s.error, isNull);
        expect(s.history.document.paths, isEmpty);
        expect(s.history.document.tracks, isNotEmpty);
        // Each subsequent tool starts from a fresh scene, with no hidden controls.
        s.history.replace(DirectorDocument.blank('Scene'));
        s.history.addObject('actor.male.v1', 'Actor');
        s.select(s.history.document.objects.single['id']);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'pencil viewport drawing simplifies, commits once, and point drag cancels',
    (tester) async {
      final s = session(), c = camera();
      await tester.pumpWidget(harness(s, c));
      await tester.pumpAndSettle();
      await click(tester, 'director-path-create:pencil');
      final count = s.history.undoCount;
      final gesture = await tester.startGesture(screen(tester, c, [-2, 0, 0]));
      for (final p in [
        [-1.5, 0.0, 0.0],
        [-1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, 2.0],
      ]) {
        await gesture.moveTo(screen(tester, c, p));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.history.undoCount, count);
      await click(tester, 'director-path-finish');
      expect(s.error, isNull);
      expect(s.history.undoCount, count + 1);
      final points =
          s.history.document.paths.single['geometry']['points'] as List;
      expect(points, hasLength(3));
      final before = s.history.document.businessContent;
      final drag = await tester.startGesture(
        screen(tester, c, (points[1] as List).cast<double>()),
      );
      await drag.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(
        s.pathEditor.visible!['geometry'],
        isNot(s.history.document.paths.single['geometry']),
      );
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(s.history.document.businessContent, before);
      final drag2 = await tester.startGesture(
        screen(tester, c, (points[1] as List).cast<double>()),
      );
      await drag2.moveBy(const Offset(25, 5));
      await drag2.up();
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.history.undoCount, count + 2);
      s.history.undo();
      expect(s.history.document.businessContent, before);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
  testWidgets(
    'pen click-drag creates handles, edits a handle, closes and cancels Escape',
    (tester) async {
      final s = session(), c = camera();
      await tester.pumpWidget(harness(s, c));
      await tester.pumpAndSettle();
      await click(tester, 'director-path-create:pen');
      final count = s.history.undoCount;
      for (final anchor in [
        [-2.0, 0.0, 0.0],
        [0.0, 0.0, 2.0],
        [2.0, 0.0, 0.0],
      ]) {
        final gesture = await tester.startGesture(screen(tester, c, anchor));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await click(tester, 'director-path-finish');
      expect(s.error, isNull);
      expect(s.history.undoCount, count + 1);
      final node = s.history.document.paths.single['geometry']['nodes'][0];
      expect(node['in_handle'], isNotNull);
      expect(node['out_handle'], isNotNull);
      expect(node['smooth'], isTrue);
      final before = s.history.document.businessContent;
      final handle = (node['out_handle'] as List).cast<double>();
      final drag = await tester.startGesture(screen(tester, c, handle));
      await drag.moveBy(const Offset(10, 20));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await drag.up();
      await tester.pumpAndSettle();
      expect(s.history.document.businessContent, before);
      expect(s.history.undoCount, count + 1);
      final drag2 = await tester.startGesture(screen(tester, c, handle));
      await drag2.moveBy(const Offset(15, 15));
      await drag2.up();
      await tester.pumpAndSettle();
      expect(s.error, isNull);
      expect(s.history.undoCount, count + 2);
      s.pathEditor.update((p) => p['geometry']['closed'] = true);
      await tester.pumpAndSettle();
      expect(s.history.document.paths.single['geometry']['closed'], isTrue);
      await click(tester, 'director-path-bake');
      expect(s.error, isNull);
      expect(s.history.document.paths, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}
