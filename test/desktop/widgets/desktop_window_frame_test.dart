// 职责: 桌面窗口框架测试 — 验证标题栏拖拽层不会抢占已排除的业务按钮区域。
// 关联文件:
//   lib/desktop/widgets/desktop_window_frame.dart
// 遵循的 Rules:
//   .agents/rules/desktop-window-frame.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/desktop/widgets/desktop_window_frame.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  const windowManagerChannel = MethodChannel('window_manager');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
  });

  testWidgets(
    'double tap inside an excluded title bar region reaches the app',
    (tester) async {
      final toolbarKey = GlobalKey();
      final windowCalls = <String>[];
      var saveTapCount = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
            windowCalls.add(call.method);
            if (call.method == 'isMaximized') {
              return false;
            }
            return null;
          });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundImagePathProvider.overrideWithValue(''),
            appBackgroundFitProvider.overrideWithValue(AppBackgroundFit.cover),
            appBackgroundThemeProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: DesktopWindowFrame(
                  titleBarGestureExclusionKeys: [toolbarKey],
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        height: DesktopWindowFrame.titleBarHeight,
                        child: KeyedSubtree(
                          key: toolbarKey,
                          child: Center(
                            child: FilledButton(
                              onPressed: () {
                                saveTapCount++;
                              },
                              child: const Text('Save'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(saveTapCount, greaterThan(0));
      expect(windowCalls, isNot(contains('maximize')));
      expect(windowCalls, isNot(contains('unmaximize')));
    },
  );
}
