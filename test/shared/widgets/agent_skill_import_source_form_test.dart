// 职责: 验证桌面 / 移动导入入口、窄屏键盘布局、输入校验与关闭后的异步安全。
// 关联文件:
//   lib/shared/widgets/agent_skill_import_source_form.dart
//   lib/shared/services/agent_skill_transfer.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:reveric/shared/providers/agent_skill_catalog_providers.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/widgets/sheet.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_dialog.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/services/agent_skill_import_parser.dart';
import 'package:reveric/shared/services/agent_skill_transfer.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/agent_skill_import_source_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _candidate = AgentSkillImportCandidate(
  filePath: 'SKILL.md',
  parsed: AgentSkillImportParseResult(
    name: 'test',
    description: 'desc',
    body: 'body',
  ),
  nameConflict: false,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  testWidgets(
    'remote scans acquire a fresh configured client and close it on failure',
    (tester) async {
      final adapters = <_ImportAdapter>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skillHttpClientFactoryProvider.overrideWithValue(() async {
              final adapter = _ImportAdapter();
              adapters.add(adapter);
              return Dio()..httpClientAdapter = adapter;
            }),
          ],
          child: _wrap(
            AgentSkillImportSourceForm(
              initialUrl: 'https://github.com/example/skill',
              existingNames: const {},
              pickFiles: () async => null,
              onDiscovered: (_) => fail('Expected rate limiting'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapters, isEmpty);
      for (var attempt = 1; attempt <= 2; attempt++) {
        await tester.tap(
          find.widgetWithText(
            RevericButton,
            tr(LocaleKeys.agentSkillImportScan),
          ),
        );
        await tester.pumpAndSettle();
        expect(adapters, hasLength(attempt));
        expect(adapters.last.path, '/repos/example/skill/zipball');
        expect(adapters.last.closed, isTrue);
        expect(
          find.text(tr(LocaleKeys.agentSkillImportRateLimited)),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'closing while proxy settings load closes the late client without downloading',
    (tester) async {
      final pending = Completer<Dio>();
      final adapter = _ImportAdapter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skillHttpClientFactoryProvider.overrideWithValue(
              () => pending.future,
            ),
          ],
          child: _wrap(
            AgentSkillImportSourceForm(
              initialUrl: 'https://github.com/example/skill',
              existingNames: const {},
              pickFiles: () async => null,
              onDiscovered: (_) => fail('Import was closed'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(RevericButton, tr(LocaleKeys.agentSkillImportScan)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(Dio()..httpClientAdapter = adapter);
      await tester.pumpAndSettle();
      expect(adapter.closed, isTrue);
      expect(adapter.path, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform supports URL validation and local selection',
      (tester) async {
        final mobile = platform == TargetPlatform.android;
        tester.view.physicalSize = mobile
            ? const Size(360, 640)
            : const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<AgentSkillImportCandidate>? selected;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  Widget content(BuildContext context) =>
                      AgentSkillImportSourceForm(
                        existingNames: const {},
                        initialUrl: 'https://github.com/example/skill',
                        pickDirectory: () async => [_candidate],
                        pickFiles: () async => [_candidate],
                        onDiscovered: (items) {
                          selected = items;
                          Navigator.of(context).pop();
                        },
                      );
                  if (mobile) {
                    showMobileSheet<void>(
                      context: context,
                      builder: (context) => MobileSheetScaffold(
                        header: MobileSheetHeader.closable(
                          title: 'Import',
                          onClose: () => Navigator.of(context).pop(),
                        ),
                        child: content(context),
                      ),
                    );
                  } else {
                    showRevericDialog<void>(
                      context: context,
                      builder: (context) => RevericDialog.panel(
                        title: const Text('Import'),
                        content: content(context),
                      ),
                    );
                  }
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'https://github.com/example/skill',
        );
        expect(selected, isNull);
        await tester.enterText(
          find.byType(TextField),
          'https://example.com/not-supported',
        );
        if (mobile) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
        }
        final scan = find.widgetWithText(
          RevericButton,
          tr(LocaleKeys.agentSkillImportScan),
        );
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await tester.pumpAndSettle();
        expect(
          find.text(tr(LocaleKeys.agentSkillImportInvalidUrl)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (mobile) {
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        final files = find.widgetWithText(
          RevericButton,
          tr(LocaleKeys.agentSkillImportSelectFile),
        );
        await tester.ensureVisible(files);
        await tester.tap(files);
        await tester.pumpAndSettle();
        expect(selected, [_candidate]);
        expect(find.byType(AgentSkillImportSourceForm), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('dismissal ignores results during the closing animation', (
    tester,
  ) async {
    final pending = Completer<List<AgentSkillImportCandidate>?>();
    var delivered = false;
    late BuildContext dialogContext;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () => showRevericDialog<void>(
              context: context,
              builder: (context) {
                dialogContext = context;
                return RevericDialog.panel(
                  title: const Text('Import'),
                  content: AgentSkillImportSourceForm(
                    existingNames: const {},
                    pickFiles: () => pending.future,
                    onDiscovered: (_) {
                      delivered = true;
                      Navigator.of(context).pop();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        RevericButton,
        tr(LocaleKeys.agentSkillImportSelectFile),
      ),
    );
    await tester.pump();
    Navigator.of(dialogContext).pop();
    expect(dialogContext.mounted, isTrue);
    pending.complete([_candidate]);
    await tester.pumpAndSettle();
    expect(delivered, isFalse);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled picker allows retry; closing ignores a late result', (
    tester,
  ) async {
    var calls = 0;
    var delivered = false;
    final pending = Completer<List<AgentSkillImportCandidate>?>();
    await tester.pumpWidget(
      _wrap(
        AgentSkillImportSourceForm(
          existingNames: const {},
          pickFiles: () async {
            calls++;
            return calls == 1 ? null : pending.future;
          },
          onDiscovered: (_) => delivered = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final files = find.widgetWithText(
      RevericButton,
      tr(LocaleKeys.agentSkillImportSelectFile),
    );
    await tester.tap(files);
    await tester.pumpAndSettle();
    expect(find.text(tr(LocaleKeys.agentSkillImportFailed)), findsNothing);
    await tester.tap(files);
    await tester.pump();
    await tester.tap(files);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete([_candidate]);
    await tester.pumpAndSettle();
    expect(delivered, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child) => ProviderScope(
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
        builder: (_, child) =>
            RevericTheme(data: RevericThemeData.reveric, child: child!),
        home: Scaffold(body: child),
      ),
    ),
  ),
);

class _ImportAdapter implements HttpClientAdapter {
  bool closed = false;
  String? path;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    path = options.uri.path;
    return ResponseBody.fromString('rate limited', 429);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}
