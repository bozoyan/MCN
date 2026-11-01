// 职责: 验证时间轴真实指针移动、裁切、冲突拒绝和中断回滚。
// 关联文件:
//   lib/shared/widgets/director/timeline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'dart:io';
import 'dart:math' as math;
import 'package:reveric/shared/models/director/sampling.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/widgets/director/timeline.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());
  Future<(DirectorSession, Directory)> mount(WidgetTester tester) async {
    final root = Directory.systemTemp.createTempSync('director_timeline_');
    final doc = DirectorDocument.parse(
      File('test/fixtures/director/motion.director.json').readAsStringSync(),
    );
    final session = DirectorSession(
      doc.mutate((j) {
        j['camera_moves'] = [
          {
            'id': '60000000-0000-4000-8000-000000000001',
            'camera_id': j['cameras'][1]['id'],
            'kind': 'static',
            'start_frame': 0,
            'end_frame': 96,
          },
          {
            'id': '60000000-0000-4000-8000-000000000002',
            'camera_id': j['cameras'][1]['id'],
            'kind': 'pan_l',
            'start_frame': 96,
            'end_frame': 120,
          },
        ];
      }),
    );
    await tester.pumpWidget(
      directorTestApp(
        Align(
          alignment: Alignment.topCenter,
          child: DirectorTimeline(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 新时间轴按对象分组，机位的运镜轨在机位轨之下，先滚进可视区。
    await tester.ensureVisible(
      find.byKey(ValueKey('segment-lane:${doc.cameras.last['id']}')),
    );
    await tester.pumpAndSettle();
    return (session, root);
  }

  Future<void> cleanup(
    WidgetTester tester,
    DirectorSession session,
    Directory root,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    await tester.pumpAndSettle();
    root.deleteSync(recursive: true);
  }

  testWidgets('timeline displays height and all three rotation angles', (
    tester,
  ) async {
    final (s, root) = await mount(tester);
    final id = s.history.document.objects.first['id'];
    s.history.setValue(id, 'position', [1, 2, 3], 0);
    s.history.setValue(
      id,
      'rotation',
      eulerQuaternion([math.pi / 6, math.pi / 4, math.pi / 3]),
      0,
    );
    await tester.pumpAndSettle();
    expect(find.text('1.0, 2.0, 3.0'), findsOneWidget);
    expect(find.text('30°, 45°, 60°'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await cleanup(tester, s, root);
  });
  testWidgets(
    'resize then move camera segment snaps to whole frames and records each gesture once',
    (tester) async {
      final (s, root) = await mount(tester);
      final actor = s.history.document.cameras.last['id'],
          walk = s.history.document.moves.first['id'],
          wave = s.history.document.moves.last['id'];
      final scale =
          tester.getSize(find.byKey(ValueKey('clip-lane:$actor'))).width / 120;
      final clip = find.byKey(ValueKey('clip:$walk'));
      var rect = tester.getRect(clip);
      var gesture = await tester.startGesture(
        Offset(rect.right - 3, rect.center.dy),
      );
      await gesture.moveBy(Offset(-24 * scale, 0));
      await tester.pump();
      expect(s.history.document.moves.first['end_frame'], 96);
      expect(s.history.visible.moves.first['end_frame'], 72);
      await gesture.up();
      await tester.pump();
      expect(s.history.document.moves.first['end_frame'], 72);
      expect(s.history.undoCount, 1);
      rect = tester.getRect(find.byKey(ValueKey('clip:$wave')));
      gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(Offset(-23.7 * scale, 0));
      await gesture.up();
      await tester.pump();
      expect(s.history.document.moves.last['start_frame'], 72);
      expect(s.history.document.moves.last['end_frame'], 96);
      expect(s.history.undoCount, 2);
      s.history.undo();
      s.history.undo();
      expect(s.history.dirty, false);
      await cleanup(tester, s, root);
    },
  );
  testWidgets(
    'overlap is visible during drag and release leaves original unchanged',
    (tester) async {
      final (s, root) = await mount(tester);
      final before = s.history.document.businessContent,
          actor = s.history.document.cameras.last['id'],
          wave = s.history.document.moves.last['id'];
      final scale =
          tester.getSize(find.byKey(ValueKey('clip-lane:$actor'))).width / 120;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('clip:$wave'))),
      );
      await gesture.moveBy(Offset(-12 * scale, 0));
      await tester.pump();
      expect(find.byKey(ValueKey('clip-invalid:$wave')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(s.history.document.businessContent, before);
      expect(s.history.undoCount, 0);
      await cleanup(tester, s, root);
    },
  );
  testWidgets(
    'escape, pointer cancel, background, and pending fields prevent commit',
    (tester) async {
      final (s, root) = await mount(tester);
      final before = s.history.document.businessContent,
          id = s.history.document.moves.first['id'];
      for (final mode in ['escape', 'cancel', 'background']) {
        final rect = tester.getRect(find.byKey(ValueKey('clip:$id')));
        final gesture = await tester.startGesture(
          Offset(rect.right - 3, rect.center.dy),
        );
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
        if (mode == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else if (mode == 'cancel') {
          await gesture.cancel();
        } else {
          s.background();
        }
        if (mode != 'cancel') {
          await gesture.up();
        }
        await tester.pump();
        expect(s.history.document.businessContent, before);
        expect(s.history.preview, isNull);
      }
      s.hasPendingInput = true;
      final rect = tester.getRect(find.byKey(ValueKey('clip:$id')));
      await tester.dragFrom(
        Offset(rect.right - 3, rect.center.dy),
        const Offset(-30, 0),
      );
      await tester.pump();
      expect(s.history.undoCount, 0);
      expect(s.error, 'apply_pending');
      await cleanup(tester, s, root);
    },
  );
  testWidgets('second pointer cancels rather than replacing the first drag', (
    tester,
  ) async {
    final (s, root) = await mount(tester);
    final before = s.history.document.businessContent,
        id = s.history.document.moves.first['id'];
    final rect = tester.getRect(find.byKey(ValueKey('clip:$id')));
    final first = await tester.startGesture(
      Offset(rect.right - 3, rect.center.dy),
      pointer: 11,
    );
    await first.moveBy(const Offset(-30, 0));
    await tester.pump();
    final second = await tester.startGesture(rect.center, pointer: 12);
    await tester.pump();
    await second.moveBy(const Offset(-45, 0));
    await second.up();
    await first.moveBy(const Offset(-20, 0));
    await first.up();
    await tester.pump();
    expect(s.history.document.businessContent, before);
    expect(s.history.preview, isNull);
    expect(s.history.undoCount, 0);
    await cleanup(tester, s, root);
  });
}
