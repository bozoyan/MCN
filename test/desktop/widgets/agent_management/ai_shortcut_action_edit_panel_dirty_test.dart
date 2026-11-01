// 职责: 验证 AI 快捷方式编辑面板向父级注册 save，并在文本变更后上报 dirty。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/agent_management/ai_shortcut_action_edit_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_shortcut_action.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiShortcutActionDefinition _action({
  required String name,
  required String prompt,
}) {
  return AiShortcutActionDefinition(
    id: 'shortcut-1',
    name: name,
    prompt: prompt,
    locations: const [AiShortcutActionLocation.chapter],
    sortOrder: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('reports dirty and registers save for unsaved-back dialog', (
    tester,
  ) async {
    final changes = <bool>[];
    Future<bool> Function()? registeredSave;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: RevericThemeData.reveric.toThemeData(),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: AiShortcutActionEditPanel(
                      action: _action(name: 'Draft', prompt: 'Do the thing'),
                      onSaved: () {},
                      onBack: () {},
                      onHasChangesChanged: changes.add,
                      onRegisterSave: (save) => registeredSave = save,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(registeredSave, isNotNull);

    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Draft updated');
    await tester.pumpAndSettle();

    expect(
      changes.where((c) => c).isNotEmpty,
      isTrue,
      reason:
          'typing must report dirty so Home can show unsaved dialog: $changes',
    );
  });
}
