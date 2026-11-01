// 职责: 验证原生大纲窗口的布局持久化及同 engine 文本同步不会破坏 IME 组词。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_outline_window.dart
//   lib/desktop/widgets/detached_window.dart

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/detached_window.dart';
import 'package:reveric/desktop/widgets/workspace/chapter_outline_window.dart';

void main() {
  test('persists window position while accepting legacy size-only data', () {
    const minimumSize = Size(440, 360);
    final encoded = encodeDetachedWindowPlacement(
      size: const Size(720, 640),
      position: const Offset(-1280, 96),
    );

    final placement = decodeDetachedWindowPlacement(
      encoded,
      minimumSize: minimumSize,
    );
    expect(placement?.size, const Size(720, 640));
    expect(placement?.position, const Offset(-1280, 96));

    final legacyPlacement = decodeDetachedWindowPlacement(
      '{"width":640,"height":640}',
      minimumSize: minimumSize,
    );
    expect(legacyPlacement?.size, const Size(640, 640));
    expect(legacyPlacement?.position, isNull);

    expect(
      decodeDetachedWindowPlacement(
        '{"width":300,"height":640}',
        minimumSize: minimumSize,
      ),
      isNull,
    );
  });

  test('synchronizes outline text directly while waiting for IME commit', () {
    fakeAsync((async) {
      final titleController = TextEditingController(text: '第七章');
      final outlineController = TextEditingController(text: '初始大纲');
      final session = ChapterOutlineWindowSession(
        titleController: titleController,
        outlineController: outlineController,
      );

      expect(session.detachedOutlineController.text, '初始大纲');

      outlineController.text = '主窗口更新';
      expect(session.detachedOutlineController.text, '主窗口更新');

      session.detachedOutlineController.value = const TextEditingValue(
        text: '子窗口组词',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 3, end: 5),
      );
      async.elapse(const Duration(seconds: 1));
      expect(outlineController.text, '主窗口更新');

      session.detachedOutlineController.value = const TextEditingValue(
        text: '子窗口上屏',
        selection: TextSelection.collapsed(offset: 5),
      );
      async.elapse(const Duration(milliseconds: 299));
      expect(outlineController.text, '主窗口更新');
      async.elapse(const Duration(milliseconds: 1));
      expect(outlineController.text, '子窗口上屏');

      session.dispose();
      async.flushMicrotasks();
      titleController.dispose();
      outlineController.dispose();
    });
  });

  test('flushes pending detached outline sync on dispose', () {
    fakeAsync((async) {
      final titleController = TextEditingController(text: '第七章');
      final outlineController = TextEditingController(text: '初始大纲');
      final session = ChapterOutlineWindowSession(
        titleController: titleController,
        outlineController: outlineController,
      );

      session.detachedOutlineController.text = '未同步的大纲';
      async.elapse(const Duration(milliseconds: 100));
      expect(outlineController.text, '初始大纲');

      // ignore: discarded_futures
      session.dispose();
      expect(outlineController.text, '未同步的大纲');

      async.flushMicrotasks();
      titleController.dispose();
      outlineController.dispose();
    });
  });

  test('flushDetachedOutlineSync writes pending text immediately', () {
    fakeAsync((async) {
      final titleController = TextEditingController(text: '第七章');
      final outlineController = TextEditingController(text: '初始大纲');
      final session = ChapterOutlineWindowSession(
        titleController: titleController,
        outlineController: outlineController,
      );

      session.detachedOutlineController.text = '待保存大纲';
      async.elapse(const Duration(milliseconds: 50));
      expect(outlineController.text, '初始大纲');

      session.flushDetachedOutlineSync();
      expect(outlineController.text, '待保存大纲');
      expect(session.isWindowOpen, isFalse);

      // ignore: discarded_futures
      session.dispose();
      async.flushMicrotasks();
      titleController.dispose();
      outlineController.dispose();
    });
  });
}
