// 职责: 验证移动端统一作品入口按内容类型分派到剧本编辑器。
// 关联文件:
//   lib/mobile/pages/workspace_editor_page.dart
//   lib/shared/models/content_kind.dart
//   lib/shared/providers/novel_providers.dart
//
// 桌面端这一侧没有对应用例：`WorkspaceEditorPage` 已经不按类型分叉，剧本和小说
// 都走 `NovelEditorPage`，分叉下沉到了 rail 导航表（见
// test/desktop/widgets/sidebar/rail_groups_test.dart）。把 `NovelEditorPage`
// 的页面集成行为由对应编辑器测试覆盖。

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/features/screenplay/editor_page.dart';
import 'package:reveric/mobile/pages/workspace_editor_page.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('mobile routes screenplay works to the screenplay editor', (
    tester,
  ) async {
    final screenplay = _screenplay();
    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            novelProvider(
              screenplay.id,
            ).overrideWith((ref) => Stream.value(screenplay)),
          ],
          child: MobileWorkspaceEditorPage(novel: screenplay),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileScreenplayEditorPage), findsOneWidget);
    expect(
      tester
          .widget<MobileScreenplayEditorPage>(
            find.byType(MobileScreenplayEditorPage),
          )
          .novel
          .id,
      screenplay.id,
    );
  });
}

Novel _screenplay() {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_test',
    title: 'Screenplay Test',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindScreenplay,
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
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => RevericTheme(
        data: RevericThemeData.reveric,
        child: MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: child,
        ),
      ),
    ),
  );
}
