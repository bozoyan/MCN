// 职责: 验证创建作品与概览封面入口防重入、失败恢复及卸载后的回调安全。
// 关联文件:
//   lib/mobile/pages/novel_create_page.dart
//   lib/mobile/widgets/overview_panel.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reveric/mobile/pages/novel_create_page.dart';
import 'package:reveric/mobile/widgets/overview_panel.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/agent_rule_providers.dart';
import 'package:reveric/shared/providers/cover_studio_providers.dart';
import 'package:reveric/shared/providers/dictionary_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/novel_fixture.dart';

const _databasePath = 'cover-picker-test';
const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
const _createCoverKey = ValueKey('mobile-novel-cover-picker');
const _overviewCoverKey = ValueKey('mobile-overview-cover');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Completer<String?>> requests;
  late NovelContentDatabase database;
  late NovelContentService service;
  final novel = buildTestNovel(databasePath: _databasePath);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    rootBundle.clear();
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = NovelContentService(database);
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, (call) {
          expect(call.method, 'pickImage');
          final request = Completer<String?>();
          requests.add(request);
          return request.future;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester, bool overview) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelCategoriesProvider.overrideWith((ref) => const <String>[]),
          novelTagsProvider.overrideWith((ref) => const <String>[]),
          novelsProvider.overrideWith((ref) => Stream.value(const <Novel>[])),
          novelProvider(novel.id).overrideWith((ref) => Stream.value(novel)),
          novelContentServiceProvider(_databasePath).overrideWithValue(service),
          agentRulesStreamProvider(
            _databasePath,
          ).overrideWith((ref) => Stream.value([])),
          canOpenCoverStudioProvider.overrideWithValue(false),
        ],
        child: EasyLocalization(
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
              theme: RevericThemeData.reveric.toThemeData(),
              builder: (_, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: child!,
              ),
              home: overview
                  ? Scaffold(
                      body: MobileOverviewPanel(
                        novel: novel,
                        databasePath: _databasePath,
                        onOpenSection: (_) {},
                        onContinueWriting: (_) {},
                        onOpenChat: () {},
                        onOpenChatWithPrompt: (_) {},
                        onEditNovel: () {},
                        onOpenAgentRules: () {},
                        onOpenCoverStudio: (_) {},
                        onUploadCover: () async {
                          await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                          );
                        },
                      ),
                    )
                  : const MobileNovelCreatePage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, bool overview) async {
    await tester.tap(
      find.byKey(overview ? _overviewCoverKey : _createCoverKey),
    );
    if (overview) {
      await tester.pumpAndSettle();
      await tester.tap(find.text(LocaleKeys.editorUploadCover.tr()));
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final overview in [false, true]) {
    testWidgets(
      'cover picker prevents overlap and retries (overview: $overview)',
      (tester) async {
        await pumpPage(tester, overview);
        final cover = find.byKey(
          overview ? _overviewCoverKey : _createCoverKey,
        );
        final retainedTap = tester.widget<InkWell>(cover).onTap!;
        await openPicker(tester, overview);
        retainedTap();
        await tester.pumpAndSettle();
        final pendingCalls = requests.length;
        final reopenedMenu =
            overview &&
            find.text(LocaleKeys.editorUploadCover.tr()).evaluate().isNotEmpty;
        if (reopenedMenu) {
          Navigator.of(
            tester.element(find.text(LocaleKeys.editorUploadCover.tr())),
          ).pop();
          await tester.pumpAndSettle();
        }
        for (final request in requests) {
          request.complete(null);
        }
        await tester.pumpAndSettle();
        expect(pendingCalls, 1);
        expect(reopenedMenu, isFalse);

        await openPicker(tester, overview);
        requests.last.completeError(PlatformException(code: 'already_active'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        await openPicker(tester, overview);
        expect(requests, hasLength(3));
        requests.last.complete(null);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('cover picker finishes after disposal (overview: $overview)', (
      tester,
    ) async {
      await pumpPage(tester, overview);
      await openPicker(tester, overview);
      await tester.pumpWidget(const SizedBox.shrink());
      requests.single.complete('unused-cover.png');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
