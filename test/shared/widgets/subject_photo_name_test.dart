// 职责: 验证桌面与 Android 照片重命名、中文输入和失败重试。
// 关联文件:
//   lib/shared/widgets/subject_photo_name.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/subject_photo.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/subject_photo_name.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets('$platform renames and permits clearing the name', (
      tester,
    ) async {
      String? saved;
      await tester.pumpWidget(
        _wrap(
          platform,
          SubjectPhotoName(
            photo: const SubjectPhoto(assetId: 'images/a.png', name: '冬装'),
            onRename: (name) async {
              saved = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('冬装'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' 正面 ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, '正面');
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('冬装'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, '');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed save keeps input and CJK composition never submits', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.windows,
        SubjectPhotoName(
          photo: const SubjectPhoto(assetId: 'images/a.png'),
          onRename: (name) async {
            attempts++;
            if (attempts == 1) {
              throw StateError('write failed');
            }
            expect(name, '冬装');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '冬装',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(attempts, 0);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '冬装',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '冬装',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(TextField), findsNothing);
  });
}

Widget _wrap(TargetPlatform platform, Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  child: Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: RevericThemeData.reveric.toThemeData().copyWith(
        platform: platform,
      ),
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  ),
);
