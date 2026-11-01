// 职责: 验证应用语言对应的编辑器与阅读默认字体选择。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/settings_providers.dart';

void main() {
  group('AppSettings.defaultFontFamilyForLanguage', () {
    test('uses the bundled Chinese font for Chinese', () {
      expect(AppSettings.defaultFontFamilyForLanguage('zh_CN'), 'LXGWWenKai');
    });

    test('uses Literata as the default for English', () {
      expect(
        AppSettings.defaultFontFamilyForLanguage('en'),
        AppSettings.defaultEditorFontFamily,
      );
    });

    test('keeps entity recognition enabled and styles disabled by default', () {
      final settings = AppSettings(
        theme: AppTheme.reveric,
        themeMode: AppThemeMode.light,
        language: 'zh_CN',
        aiSettings: AiSettings.defaults(),
      );

      expect(settings.editorEntityRecognitionEnabled, isTrue);
      expect(settings.editorEntityItalic, isFalse);
      expect(settings.editorEntityHighlight, isFalse);
      expect(settings.editorEntityUnderline, isFalse);
      expect(settings.editorEntityBold, isFalse);
      expect(settings.editorEntityTextColorHex, isEmpty);
      expect(
        settings
            .copyWith(editorEntityRecognitionEnabled: false)
            .editorEntityRecognitionEnabled,
        isFalse,
      );
    });
  });
}
