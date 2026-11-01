// 职责: 验证剪贴板普通文字不会被误识别为文本文件附件。
// 关联文件:
//   lib/shared/widgets/ai/chat/attachment_input.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/ai/chat/attachment_input.dart';
import 'package:super_clipboard/super_clipboard.dart' as clip;

class _PlainTextReader implements clip.DataReader {
  @override
  bool canProvide(clip.DataFormat format) =>
      format == clip.Formats.plainText || format == clip.Formats.plainTextFile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Ordinary text must not be requested as a file');
}

void main() {
  test('shared text/plain format remains text when pasting', () async {
    expect(
      await readChatAttachmentData(_PlainTextReader(), allowTextFile: false),
      isNull,
    );
  });
}
