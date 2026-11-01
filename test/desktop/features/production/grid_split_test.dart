// 职责: 验证宫格选格、计数、自定义规格和退出时清理本地会话。
// 关联文件:
//   lib/desktop/features/production/grid/session.dart
//   lib/desktop/features/production/grid/split_overlay.dart
//   lib/desktop/features/production/grid/spec_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/grid/session.dart';
import 'package:reveric/desktop/features/production/grid/split_bar.dart';
import 'package:reveric/desktop/features/production/grid/split_overlay.dart';
import 'package:reveric/desktop/features/production/grid/spec_picker.dart';
import '../../director/harness.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(initializeDirectorTest);
  testWidgets(
    'grid choices smaller than member count are disabled',
    (tester) async {
      GridSpec? chosen;
      await tester.pumpWidget(
        directorTestApp(
          Center(
            child: ProductionGridSpecPicker(
              label: 'Grid',
              minimum: 5,
              onSelected: (value) => chosen = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 (2×2)'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      await tester.tap(find.text('9 (3×3)'));
      await tester.pumpAndSettle();
      expect(chosen, (rows: 3, cols: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'unsupported HD multiplier stays visible but cannot be chosen',
    (tester) async {
      var chosen = 2;
      await tester.pumpWidget(
        directorTestApp(
          Center(
            child: ProductionUpscaleMultiplier(
              value: 2,
              supported: const {2},
              onChanged: (value) => chosen = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2×'));
      await tester.pumpAndSettle();
      expect(find.text('4×'), findsOneWidget);
      expect(
        find.text('The selected model does not support this resolution'),
        findsOneWidget,
      );
      await tester.tap(find.text('4×'));
      await tester.pumpAndSettle();
      expect(chosen, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'selection count, custom dimensions, Esc and deselect reset the session',
    (tester) async {
      final selection = ValueNotifier<String?>('source');
      addTearDown(selection.dispose);
      late GridSplitSession session;
      await tester.pumpWidget(
        directorTestApp(
          ValueListenableBuilder(
            valueListenable: selection,
            builder: (_, id, _) => ProductionGridWorkspace(
              nodeId: id,
              child: Builder(
                builder: (context) {
                  session = ProductionGridSession.maybeOf(context)!;
                  return Column(
                    children: [
                      ProductionGridSpecPicker(
                        label: 'Split',
                        onSelected: session.start,
                      ),
                      Text('selected=${session.selected.length}'),
                      const SizedBox(
                        width: 300,
                        height: 200,
                        child: ProductionGridOverlay(
                          nodeId: 'source',
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom ›'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-spec/1/1')));
      await tester.pumpAndSettle();
      expect(session.active, isFalse);
      await tester.tap(find.byKey(const ValueKey('grid-spec/2/3')));
      await tester.pumpAndSettle();
      expect(session.spec, (rows: 2, cols: 3));
      await tester.tap(find.byKey(const ValueKey('grid-cell/1/2')));
      await tester.pumpAndSettle();
      expect(find.text('selected=1'), findsOneWidget);
      expect(find.text('2-3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grid-cell/1/2')));
      await tester.pumpAndSettle();
      expect(find.text('selected=0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(session.active, isFalse);
      session.start((rows: 2, cols: 2));
      session.toggle(1);
      await tester.pumpAndSettle();
      selection.value = null;
      await tester.pumpAndSettle();
      expect(session.active, isFalse);
      expect(session.selected, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
