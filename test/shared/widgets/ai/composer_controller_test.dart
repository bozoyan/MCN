// 职责: 验证聊天草稿的文件块编辑、快照与提交防重入生命周期。
// 关联文件:
//   lib/shared/widgets/ai/chat/composer_controller.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/chat/composer_controller.dart';
import 'package:reveric/shared/services/ai/chat_attachments.dart';

void main() {
  test('rapid submissions consume a draft only once while preparing', () async {
    final controller = ChatComposerController()..text = 'same draft';
    addTearDown(controller.dispose);
    final preparation = Completer<void>();
    final submissions = <String>[];
    Future<void> send() async {
      submissions.add(controller.text);
      await preparation.future;
      controller.clear();
    }

    final first = controller.submit(send);
    final second = controller.submit(send);
    try {
      expect(submissions, ['same draft']);
      expect(controller.text, 'same draft');
    } finally {
      preparation.complete();
      await Future.wait([first, second]);
    }
    expect(controller.text, isEmpty);
  });

  test(
    'consumed draft permits queuing; older turn cannot unlock new submission',
    () async {
      final controller = ChatComposerController()..text = 'same text';
      addTearDown(controller.dispose);
      final firstTurn = Completer<void>();
      final queuePreparation = Completer<void>();
      var sends = 0;
      final first = controller.submit(() async {
        sends++;
        controller.clear();
        await firstTurn.future;
      });
      // Even identical content is a new draft after the first one was consumed.
      controller.text = 'same text';
      final queued = controller.submit(() async {
        sends++;
        await queuePreparation.future;
        controller.clear();
      });
      expect(sends, 2);
      firstTurn.complete();
      await first;
      await controller.submit(() async => sends++);
      expect(sends, 2);
      queuePreparation.complete();
      await queued;
      controller.text = 'third';
      await controller.submit(() async => sends++);
      expect(sends, 3);
    },
  );

  test(
    'failed or declined submission preserves draft and allows retry',
    () async {
      final controller = ChatComposerController()..text = 'retry';
      addTearDown(controller.dispose);
      await expectLater(
        controller.submit(() async => throw StateError('preparation failed')),
        throwsStateError,
      );
      expect(controller.text, 'retry');
      var sends = 0;
      await controller.submit(() async => sends++);
      await controller.submit(() async => sends++);
      expect(sends, 2);
      expect(controller.text, 'retry');
    },
  );

  test(
    'selection changes keep the guard; edited drafts can queue during preparation',
    () async {
      final controller = ChatComposerController()..text = 'first';
      addTearDown(controller.dispose);
      final preparation = Completer<void>();
      final submissions = <String>[];
      Future<void> send() async {
        submissions.add(controller.text);
        await preparation.future;
      }

      final first = controller.submit(send);
      controller.selection = const TextSelection.collapsed(offset: 1);
      await controller.submit(send);
      expect(submissions, ['first']);
      controller.text = 'next';
      final second = controller.submit(send);
      expect(submissions, ['first', 'next']);
      preparation.complete();
      await Future.wait([first, second]);
      expect(controller.text, 'next');
    },
  );

  XFile file(String name) =>
      NamedChatFile.data(Uint8List.fromList([1]), name: name);
  test(
    'insertion and moving preserve surrounding text and attachment identity',
    () {
      final controller = ChatComposerController();
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: '前后',
        selection: TextSelection.collapsed(offset: 1),
      );
      controller.insertFiles([file('a.png')]);
      expect(controller.readableText(controller.snapshot()), '前Image #1后');
      expect(
        controller.text.length,
        3,
        reason: 'one native editing unit per attachment',
      );
      controller.moveFile(1, 3);
      expect(controller.readableText(controller.snapshot()), '前后Image #1');
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 3,
      );
      controller.insertText('');
      expect(controller.text, '前后');
      expect(controller.snapshot().attachments, isEmpty);
    },
  );

  test('image numbers survive moving/deleting and reset for a new message', () {
    final controller = ChatComposerController();
    addTearDown(controller.dispose);
    controller.insertFiles([
      file('notes.txt'),
      file('one.png'),
      file('two.png'),
    ]);
    expect(
      controller.readableText(controller.snapshot()),
      '[notes.txt]Image #1Image #2',
    );
    controller.moveFile(2, 1);
    expect(
      controller.readableText(controller.snapshot()),
      '[notes.txt]Image #2Image #1',
    );
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 3);
    controller.insertText('');
    controller.insertFiles([file('three.png')]);
    expect(
      controller.readableText(controller.snapshot()),
      '[notes.txt]Image #2Image #3',
    );
    controller.clear();
    controller.insertFiles([file('next.png')]);
    expect(controller.readableText(controller.snapshot()), 'Image #1');
  });

  test('cut/paste moves the same image number while a copy gets a new one', () {
    final controller = ChatComposerController();
    addTearDown(controller.dispose);
    controller.insertFiles([file('one.png'), file('two.png')]);
    final cut = controller.snapshot(controller.text[0]);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.insertText('');
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.insertDraft(cut);
    expect(controller.readableText(controller.snapshot()), 'Image #2Image #1');
    controller.insertDraft(cut);
    expect(
      controller.readableText(controller.snapshot()),
      'Image #2Image #1Image #3',
    );
  });

  test(
    'copied mixed content survives clearing and pastes as independent atoms',
    () {
      final original = ChatComposerController();
      final pasted = ChatComposerController();
      addTearDown(original.dispose);
      addTearDown(pasted.dispose);
      original.insertText('根据');
      original.insertFiles([file('参考.md')]);
      original.insertText('比较');
      original.insertFiles([file('图.png')]);
      final copy = original.snapshot();
      original.clear();
      pasted.insertDraft(copy);
      pasted.insertDraft(copy);
      expect(pasted.snapshot().attachments.length, 4);
      expect(
        pasted.readableText(pasted.snapshot()),
        '根据[参考.md]比较Image #1根据[参考.md]比较Image #2',
      );
    },
  );
}
