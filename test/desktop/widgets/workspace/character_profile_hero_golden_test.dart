// 职责: 人物资料编辑器 hero 与身份档案分组的黄金图（加载真实字体），人工目检摘要单行、名称居中与标签编辑器。
// 关联文件:
//   lib/desktop/widgets/workspace/character_profile_editor.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/character_profile_editor.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/form/flutter_hook_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
  });

  testWidgets('golden: hero summary stays on one line with real fonts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1040, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapEditor(_editor()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(CharacterProfileEditor),
      matchesGoldenFile('goldens/character_profile_hero.png'),
    );
  });
}

Widget _editor() {
  return HookBuilder(
    builder: (context) {
      final form = useForm<CharacterProfileEditFields>(
        initialValues: {
          CharacterProfileEditFields.name: '陈屿',
          CharacterProfileEditFields.role: 'protagonist',
          CharacterProfileEditFields.gender: 'male',
        },
        listen: false,
      );
      final aliases = useState<List<String>>(const ['小屿', '云岚宗大长老']);
      final managementTags = useState<List<String>>(const ['云岚宗', '内门弟子']);
      return CharacterProfileEditor(
        session: CharacterProfileEditorSession(
          target: const CharacterProfileEditorTarget(
            selectedItemId: null,
            isCreating: true,
            characterProfiles: [],
          ),
          fields: CharacterProfileFormSession(
            form: form,
            controllers: {
              CharacterProfileEditFields.name: useTextEditingController(
                text: '陈屿',
              ),
              CharacterProfileEditFields.role: useTextEditingController(
                text: 'protagonist',
              ),
              CharacterProfileEditFields.gender: useTextEditingController(
                text: 'male',
              ),
              CharacterProfileEditFields.identity: useTextEditingController(
                text: '程序员',
              ),
              CharacterProfileEditFields.age: useTextEditingController(
                text: '21岁（2015年秋季，大三）',
              ),
              CharacterProfileEditFields.motivation: useTextEditingController(),
              CharacterProfileEditFields.arc: useTextEditingController(),
              CharacterProfileEditFields.biography: useTextEditingController(),
              CharacterProfileEditFields.appearance: useTextEditingController(),
              CharacterProfileEditFields.description:
                  useTextEditingController(),
              CharacterProfileEditFields.personality:
                  useTextEditingController(),
              CharacterProfileEditFields.currentState:
                  useTextEditingController(),
            },
            focusNodes: {
              CharacterProfileEditFields.name: useFocusNode(),
              CharacterProfileEditFields.identity: useFocusNode(),
              CharacterProfileEditFields.age: useFocusNode(),
              CharacterProfileEditFields.motivation: useFocusNode(),
              CharacterProfileEditFields.arc: useFocusNode(),
              CharacterProfileEditFields.biography: useFocusNode(),
              CharacterProfileEditFields.appearance: useFocusNode(),
              CharacterProfileEditFields.description: useFocusNode(),
              CharacterProfileEditFields.personality: useFocusNode(),
              CharacterProfileEditFields.currentState: useFocusNode(),
            },
            aliases: aliases.value,
            tags: managementTags.value,
            behaviorTags: const [],
            onAliasesChanged: (next) => aliases.value = next,
            onTagsChanged: (next) => managementTags.value = next,
            onBehaviorTagsChanged: (_) {},
          ),
          media: CharacterProfileMediaSession(
            avatarAssetId: null,
            photos: const [],
            avatarPicking: false,
            photoAdding: false,
            isImageGenerationConfigured: false,
            onPickAvatar: () async {},
            onAddPhoto: () async {},
            onRemovePhoto: (_) async {},
            onRenamePhoto: (_, _) async {},
            onRemoveAvatar: () async {},
            onGenerateAvatar: (_, _) async {},
            onGeneratePhoto: (_, _) async {},
          ),
          onCreateCharacter: () {},
        ),
      );
    },
  );
}

Widget _wrapEditor(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            editorFontFamilyProvider.overrideWithValue('Georgia'),
            editorFontSizeProvider.overrideWithValue(16),
            editorLetterSpacingProvider.overrideWithValue(0),
            editorLineHeightProvider.overrideWithValue(1.8),
            editorFontColorProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(
              fontFamily: 'LXGWWenKai',
            ),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 1040, height: 900, child: child),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
