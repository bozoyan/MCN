// 职责: 移动端作品编辑页导入契约测试 — 防止 iOS 文件选择器缺少 UTI 导致导入入口直接失败。
// 关联文件:
//   lib/mobile/pages/novel_editor_page.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/pages/novel_editor_page.dart';

void main() {
  test('text document import declares iOS uniform type identifiers', () {
    expect(mobileTextDocumentImportTypeGroup.extensions, contains('txt'));
    expect(mobileTextDocumentImportTypeGroup.extensions, contains('md'));
    expect(
      mobileTextDocumentImportTypeGroup.uniformTypeIdentifiers,
      contains('public.text'),
    );
    expect(
      mobileTextDocumentImportTypeGroup.uniformTypeIdentifiers,
      contains('net.daringfireball.markdown'),
    );
  });
}
