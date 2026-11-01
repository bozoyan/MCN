// 职责: 验证桌面端 Cmd/Ctrl+S 都能触发当前保存回调且不会并发重入。
// 关联文件:
//   lib/desktop/widgets/desktop_save_shortcut.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/desktop/widgets/desktop_save_shortcut.dart';

void main() {
  testWidgets('handles Control+S and Meta+S', (tester) async {
    var saveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSaveShortcut(
            onSave: () async {
              saveCount++;
            },
            child: const TextField(autofocus: true),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS, platform: 'windows');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(saveCount, 2);
  });

  testWidgets('does not start a second save while the first is pending', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    var saveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSaveShortcut(
            onSave: () {
              saveCount++;
              return saveCompleter.future;
            },
            child: const TextField(autofocus: true),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(saveCount, 1);

    saveCompleter.complete();
    await tester.pump();
  });
}
