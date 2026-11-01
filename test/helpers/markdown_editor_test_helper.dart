// 职责: widget 测试里向 RevericMarkdownEditor 写入正文内容。
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';

/// 把 [text] 写进 [RevericMarkdownEditor]。
///
/// 这个编辑器渲染的是 block 列表 + 自定义 `TextInputClient`，整棵子树里没有
/// `TextField`，`tester.enterText(find.byType(TextField).last, ...)` 只会打到页面上
/// 别的输入框（例如 Agent Rule 面板的名称框），内容一个字都没进去，断言却要等到
/// 保存后读内容时才炸。
///
/// 这里直接写编辑器持有的 controller：调用方（编辑面板）的 dirty 上报与保存链路本来
/// 就挂在这个 controller 的 listener 上，写它等价于用户输入。编辑器自身的按键、选区
/// 和 IME 行为由 test/shared/widgets/md/markdown_block_editor_test.dart 覆盖。
Future<void> enterMarkdownEditorText(
  WidgetTester tester,
  String text, {
  Finder? editor,
}) async {
  final controller = tester
      .widget<RevericMarkdownEditor>(
        editor ?? find.byType(RevericMarkdownEditor),
      )
      .controller;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tester.pumpAndSettle();
}
