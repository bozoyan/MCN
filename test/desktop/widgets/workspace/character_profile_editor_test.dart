// 职责: 测试角色资料编辑器把七个分组平铺成连续滚动、锚点跳转生效、紧凑高度下不溢出，且重复行为标签被去重拦截。
// 关联文件:
//   lib/desktop/widgets/workspace/character_profile_editor.dart
//   lib/shared/widgets/character/character_profile_section.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:reveric/desktop/widgets/workspace/character_profile_editor.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/character/character_profile_section.dart';
import 'package:reveric/third/form/flutter_hook_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'seven sections share one scroll, anchors jump, and duplicate behavior tags are rejected',
    (tester) async {
      final tagChanges = <List<CharacterBehaviorTag>>[];
      await tester.pumpWidget(
        _wrapEditor(_editor(onTagsChanged: tagChanges.add)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollbar), findsOneWidget);

      // Hero 与吸顶锚点栏在页面顶部；七个分组标题在锚点栏里各出现一次。
      expect(find.byType(CharacterProfileAnchorBar), findsOneWidget);
      for (final section in characterProfileSections) {
        expect(
          find.descendant(
            of: find.byType(CharacterProfileAnchorBar),
            matching: find.text(section.titleKey.tr()),
          ),
          findsOneWidget,
          reason: '锚点栏缺少分组 ${section.id}',
        );
      }

      // 第一个分组的内容一开始就可见，不再需要先切 tab。
      expect(find.text('别名与称号'), findsOneWidget);

      // 点末尾锚点应把关系网络分组滚进视口，中途不产生溢出。
      // 页面滚动体：最外层 CustomScrollView 自己的 Scrollable
      // （长文编辑器内部也是 CustomScrollView，不能用 byType 直接取）。
      final pageScroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(pageScroll.position.pixels, 0);
      await tester.tap(
        find.descendant(
          of: find.byType(CharacterProfileAnchorBar),
          matching: find.text('关系网络'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final relationsOffset = pageScroll.position.pixels;
      expect(relationsOffset, greaterThan(0));
      expect(find.text('只读概览 · 编辑请前往关系图', skipOffstage: false), findsOneWidget);

      // 行为标签与当前状态原本分散在两个 tab 里，现在同属一条滚动、同时在树上。
      expect(find.text('行为标签', skipOffstage: false), findsOneWidget);
      expect(
        find.text('该段落由 AI 随剧情自动维护，手动修改会在下次同步时被覆盖。', skipOffstage: false),
        findsNothing,
      );
      // 回到首个锚点同样生效：滚回 Hero 之下、身份档案分组吸顶的位置。
      await tester.tap(
        find.descendant(
          of: find.byType(CharacterProfileAnchorBar),
          matching: find.text('身份档案'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(pageScroll.position.pixels, lessThan(relationsOffset));
      expect(find.text('别名与称号'), findsOneWidget);

      // 行为标签去重：滚到「内在心理」分组，让标签编辑器进入视口。
      await tester.tap(
        find.descendant(
          of: find.byType(CharacterProfileAnchorBar),
          matching: find.text('内在心理'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('character-behavior-tag-field')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 已存在「先观察 / 进入陌生环境时」，输入相同组合应被拒绝且不新增行。
      // 通过情境输入框的 done 动作提交，避免视口边缘的按钮命中问题。
      await tester.enterText(
        find.byKey(const Key('character-behavior-tag-field')),
        '先观察',
      );
      await tester.enterText(
        find.byKey(const Key('character-behavior-context-field')),
        '进入陌生环境时',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('相同的行为标签与触发情境已存在'), findsOneWidget);
      expect(tagChanges, isEmpty, reason: '重复组合不应触发 onChanged 新增行');

      // 不重复的组合可以正常添加，错误提示随之消失。
      await tester.enterText(
        find.byKey(const Key('character-behavior-tag-field')),
        '主动站出来',
      );
      await tester.enterText(
        find.byKey(const Key('character-behavior-context-field')),
        '同伴被指责时',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('相同的行为标签与触发情境已存在'), findsNothing);
      expect(tagChanges, hasLength(1));
      expect(tagChanges.single, hasLength(2));
      expect(tagChanges.single.last.tag, '主动站出来');

      // 新增第二行后，编辑第一行成重复组合，失焦时必须使用最新列表校验。
      final firstTagField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == '先观察',
      );
      final firstContextField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == '进入陌生环境时',
      );
      expect(firstTagField, findsOneWidget);
      expect(firstContextField, findsOneWidget);
      await tester.enterText(firstTagField, '主动站出来');
      await tester.enterText(firstContextField, '同伴被指责时');
      final addTagField = find.byKey(const Key('character-behavior-tag-field'));
      await tester.ensureVisible(addTagField);
      await tester.tap(addTagField);
      await tester.pump();

      expect(find.text('相同的行为标签与触发情境已存在'), findsOneWidget);
      expect(tagChanges, hasLength(1));
      expect(tagChanges.single, hasLength(2));
    },
  );
}

Widget _editor({ValueChanged<List<CharacterBehaviorTag>>? onTagsChanged}) {
  return HookBuilder(
    builder: (context) {
      final form = useForm<CharacterProfileEditFields>(
        initialValues: {
          CharacterProfileEditFields.name: '林默',
          CharacterProfileEditFields.role: 'supporting',
          CharacterProfileEditFields.gender: 'unknown',
        },
        listen: false,
      );
      final behaviorTags = useState<List<CharacterBehaviorTag>>(const [
        CharacterBehaviorTag(tag: '先观察', context: '进入陌生环境时'),
      ]);
      final managementTags = useState<List<String>>(const ['云岚宗']);
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
                text: '林默',
              ),
              CharacterProfileEditFields.role: useTextEditingController(
                text: 'supporting',
              ),
              CharacterProfileEditFields.gender: useTextEditingController(
                text: 'unknown',
              ),
              CharacterProfileEditFields.identity: useTextEditingController(),
              CharacterProfileEditFields.age: useTextEditingController(
                text: '未知',
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
            aliases: const ['小林'],
            tags: managementTags.value,
            behaviorTags: behaviorTags.value,
            onAliasesChanged: (_) {},
            onTagsChanged: (next) => managementTags.value = next,
            onBehaviorTagsChanged: (next) {
              behaviorTags.value = next;
              onTagsChanged?.call(next);
            },
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
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 700, height: 360, child: child),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
