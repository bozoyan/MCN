// 职责: 验证桌面人物编辑区域独立拥有草稿、人物切换、自动保存、失焦落盘与 CJK 组合输入边界。
// 关联文件:
//   lib/desktop/widgets/workspace/character_profile_editor_region.dart
//   lib/desktop/widgets/workspace/character_profile_editor.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/workspace/character_profile_editor.dart';
import 'package:reveric/desktop/widgets/workspace/character_profile_editor_region.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/character/character_profile_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _databasePath = 'desktop_character_editor_region_test';
const _pastAutoSaveDebounce = Duration(milliseconds: 900);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late NovelContentDatabase contentDatabase;
  late AppDatabase appDatabase;
  late NovelContentService contentService;
  late WorkingOverlayService overlayService;
  late String characterAId;
  late String characterBId;

  setUp(() async {
    rootBundle.clear();
    contentDatabase = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDatabase = AppDatabase.forTest(NativeDatabase.memory());
    contentService = NovelContentService(contentDatabase);
    overlayService = WorkingOverlayService(
      contentDatabase,
      contentService,
      novelActionsService: NovelActionsService(appDatabase),
    );
    characterAId = await contentService.createCharacterProfile(name: '人物甲');
    characterBId = await contentService.createCharacterProfile(name: '人物乙');
  });

  tearDown(() async {
    await contentDatabase.close();
    await appDatabase.close();
  });

  testWidgets('empty selection transition and character drafts stay isolated', (
    tester,
  ) async {
    final selection = ValueNotifier<WorkspaceSelection>(
      const WorkspaceSelection(section: NovelWorkspaceSection.characters),
    );
    final controller = CharacterProfileEditorRegionController();

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            novelContentDatabaseProvider(
              _databasePath,
            ).overrideWithValue(contentDatabase),
            novelContentServiceProvider(
              _databasePath,
            ).overrideWithValue(contentService),
            workingOverlayServiceProvider(
              _databasePath,
            ).overrideWithValue(overlayService),
            isImageGenerationConfiguredProvider.overrideWithValue(false),
            editorFontFamilyProvider.overrideWithValue('Georgia'),
            editorFontSizeProvider.overrideWithValue(16),
            editorLetterSpacingProvider.overrideWithValue(0),
            editorLineHeightProvider.overrideWithValue(1.8),
          ],
          child: ValueListenableBuilder<WorkspaceSelection>(
            valueListenable: selection,
            builder: (context, currentSelection, _) {
              return CharacterProfileEditorRegion(
                databasePath: _databasePath,
                selection: currentSelection,
                novel: _novel(_databasePath),
                controller: controller,
                nameAssistantAiService: null,
                host: CharacterProfileEditorRegionHost(
                  onCreateCharacter: () {},
                  onSavingChanged: (_) {},
                  onGenerateAvatar: (_, _) async {},
                  onGeneratePhoto: (_, _) async {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有选中人物'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect((await contentService.getCharacterProfiles()).length, 2);
    expect(
      await controller.flushBeforeTransition(
        selectedItemId: selection.value.itemId,
      ),
      isTrue,
    );

    selection.value = const WorkspaceSelection.creating(
      section: NovelWorkspaceSection.characters,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CharacterProfileAnchorBar), findsOneWidget);
    expect(find.text('身份档案'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('character-name-field')),
      '人物丙',
    );
    final session = tester
        .widget<CharacterProfileEditor>(find.byType(CharacterProfileEditor))
        .session;
    session.identityController.text = '巡夜人';
    session.ageController.text = '二十七';
    session.motivationController.text = '查明旧案';
    session.arcController.text = '由回避到承担';
    session.summaryController.text = '出身边城，曾在北境服役。';
    session.appearanceController.text = '身形修长，黑发束冠。';
    session.descriptionController.text = '左眉有浅疤，说话很轻。';
    session.personalityController.text = '谨慎，自尊心强，但会保护弱者。';
    session.currentStateController.text = '右臂受伤，正在松江府休养。';
    session.onAliasesChanged(const ['阿丙']);
    session.onBehaviorTagsChanged(const [
      CharacterBehaviorTag(tag: '先观察', context: '进入陌生环境时'),
    ]);
    await tester.pump();
    expect(controller.hasDraftContent, isTrue);
    expect((await contentService.getCharacterProfiles()).length, 2);

    final createdId = await controller.save();
    await tester.pumpAndSettle();
    expect(createdId, isNotNull);
    expect((await contentService.getCharacterProfiles()).length, 3);
    final created = (await contentService.getCharacterProfileById(createdId!))!;
    expect(created.name, '人物丙');
    expect(created.identity, '巡夜人');
    expect(created.age, '二十七');
    expect(created.aliases, ['阿丙']);
    expect(created.motivation, '查明旧案');
    expect(created.arc, '由回避到承担');
    expect(created.biography, '出身边城，曾在北境服役。');
    expect(created.appearance, '身形修长，黑发束冠。');
    expect(created.description, '左眉有浅疤，说话很轻。');
    expect(created.personality, '谨慎，自尊心强，但会保护弱者。');
    expect(created.behaviorTags, [
      const CharacterBehaviorTag(tag: '先观察', context: '进入陌生环境时'),
    ]);
    expect(created.currentState, '右臂受伤，正在松江府休养。');

    selection.value = WorkspaceSelection(
      section: NovelWorkspaceSection.characters,
      itemId: characterAId,
    );
    await tester.pumpAndSettle();
    final nameField = find.byKey(const Key('character-name-field'));
    expect(tester.widget<TextField>(nameField).controller!.text, '人物甲');

    final relations = contentService.entityRelationsService;
    final activeId = await relations.createRelation(
      sourceType: 'character',
      sourceId: characterAId,
      targetType: 'character',
      targetId: characterBId,
      relationType: 'friend',
      proof: 'current',
    );
    await relations.createRelation(
      sourceType: 'character',
      sourceId: characterAId,
      targetType: 'character',
      targetId: characterBId,
      relationType: 'lover',
      status: 'ended',
      proof: 'past',
    );
    await tester.pumpAndSettle();
    int? relationCount() => tester
        .widget<CharacterProfileAnchorBar>(
          find.byType(CharacterProfileAnchorBar),
        )
        .counts[CharacterProfileSectionId.relations];
    expect(relationCount(), 1);
    await relations.recordChange(
      id: activeId,
      status: 'ended',
      proof: 'ended',
      reason: 'ended',
    );
    await tester.pumpAndSettle();
    expect(relationCount() ?? 0, 0);
    expect(
      await relations.getRelationsForEntity(
        entityType: 'character',
        entityId: characterAId,
      ),
      hasLength(2),
    );

    await tester.tap(nameField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '人',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump(_pastAutoSaveDebounce);
    expect(
      (await contentService.getCharacterProfileById(characterAId))!.name,
      '人物甲',
    );
    expect(await controller.save(), isNull);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '人物甲改',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump(_pastAutoSaveDebounce);
    await tester.pumpAndSettle();
    expect(
      (await contentService.getCharacterProfileById(characterAId))!.name,
      '人物甲改',
    );

    selection.value = WorkspaceSelection(
      section: NovelWorkspaceSection.characters,
      itemId: characterBId,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, '人物乙');
    await tester.enterText(nameField, '人物乙改');
    await tester.pump(_pastAutoSaveDebounce);
    await tester.pumpAndSettle();

    expect(
      (await contentService.getCharacterProfileById(characterAId))!.name,
      '人物甲改',
    );
    expect(
      (await contentService.getCharacterProfileById(characterBId))!.name,
      '人物乙改',
    );

    // 保存过一次后 form 控制器会随 updatedAt 重建；此时把焦点切到另一个字段，
    // 失焦落盘必须用当前 form 校验——否则会校验失败、内容存不下去，
    // 并把焦点抢回名称字段。
    final sessionB = tester
        .widget<CharacterProfileEditor>(find.byType(CharacterProfileEditor))
        .session;
    sessionB.nameFocusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(sessionB.nameFocusNode.hasFocus, isTrue);

    sessionB.motivationController.text = '守住渡口';
    sessionB.motivationFocusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(sessionB.motivationFocusNode.hasFocus, isTrue);
    expect(sessionB.nameFocusNode.hasFocus, isFalse);
    expect(
      (await contentService.getCharacterProfileById(characterBId))!.motivation,
      '守住渡口',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));

    // 编辑区被主区替换（智能体规则页等）后没有可落盘草稿，切换前的 flush 必须放行，
    // 否则切 section / 打开规则 / 返回全部被静默拦死。
    expect(
      await controller.flushBeforeTransition(selectedItemId: characterBId),
      isTrue,
    );

    selection.dispose();
  });
}

Novel _novel(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'novel_test',
    title: '测试作品',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindNovel,
    contentDatabasePath: databasePath,
    wordCount: 0,
    draft: false,
    category: '',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
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
        );
      },
    ),
  );
}
