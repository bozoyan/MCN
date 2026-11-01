// 职责: 侧边栏人物分组的黄金图（加载真实字体），人工目检折叠态分组索引与展开后的缩进层级。
// 关联文件:
//   lib/desktop/widgets/sidebar/character_groups.dart
//   lib/desktop/widgets/sidebar/sections.dart

import 'dart:io';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/database/app_database.dart'
    show AppDatabase, notDeletedSentinel;
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  testWidgets('golden: 分组折叠索引与展开后的组内缩进', (tester) async {
    tester.view.physicalSize = const Size(460, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    final database = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(_wrapSidebar(_characters(), database));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LeftSidebar),
      matchesGoldenFile('goldens/character_groups_collapsed.png'),
    );

    await tester.tap(find.text('云岚宗'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LeftSidebar),
      matchesGoldenFile('goldens/character_groups_expanded.png'),
    );
  });
}

List<CharacterProfile> _characters() {
  return [
    _character(id: 'a', name: '陈屿', tags: const ['云岚宗', '内门弟子']),
    _character(id: 'b', name: '苏瑶', tags: const ['云岚宗']),
    _character(id: 'c', name: '张伟', tags: const ['云岚宗', '内门弟子']),
    _character(id: 'd', name: '纳兰嫣', tags: const ['纳兰家']),
    _character(id: 'e', name: '陈峰'),
    _character(id: 'f', name: '李想'),
    _character(id: 'g', name: '王芳'),
  ];
}

CharacterProfile _character({
  required String id,
  required String name,
  List<String> tags = const [],
}) {
  final now = DateTime.utc(2026, 1, 1);
  return CharacterProfile(
    id: id,
    name: name,
    role: 'supporting',
    gender: 'unknown',
    aliases: const [],
    tags: tags,
    biography: '',
    appearance: '',
    description: '',
    currentState: '',
    identity: '',
    age: '',
    motivation: '',
    arc: '',
    personality: '',
    behaviorTags: const [],
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrapSidebar(List<CharacterProfile> characters, AppDatabase database) {
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
            appDatabaseProvider.overrideWithValue(database),
            appSettingsNotifierProvider.overrideWith(
              _TestAppSettingsNotifier.new,
            ),
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
                body: LeftSidebar(
                  novelTitle: '重生之我用 AI 写小说',
                  currentNovelId: 'novel-1',
                  databasePath: null,
                  selection: const WorkspaceSelection(
                    section: NovelWorkspaceSection.characters,
                  ),
                  chapters: const [],
                  worldbuildingEntries: const [],
                  outlineEntries: const [],
                  materialEntries: const [],
                  characterProfiles: characters,
                  skillEntries: const [],
                  items: const [],
                  factionEntries: const [],
                  creatureEntries: const [],
                  foreshadowings: const [],
                  maps: const [],
                  locations: const [],
                  onSelect: (_) {},
                  onEditDetails: () {},
                  onCreateChapter: () async {},
                  onCollapse: () {},
                  onExpand: () {},
                  onSwitchNovel: (_) {},
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'zh-CN',
      aiSettings: AiSettings.defaults(),
    );
  }
}
