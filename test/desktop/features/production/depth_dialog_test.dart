// 职责: 验证深度下载确认、就绪直启、完成自动关闭与后台任务查看不会重复执行。
// 关联文件:
//   lib/desktop/features/production/depth_dialog.dart
//   lib/shared/services/depth/task_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'dart:async';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/desktop/features/production/depth_dialog.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_dialog.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/depth.dart';
import 'package:reveric/shared/services/depth/model.dart';
import 'package:reveric/shared/services/depth/model_service.dart';
import 'package:reveric/shared/services/depth/task_controller.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/theme/theme.dart';

class _Models extends DepthModelService {
  _Models(this.installed)
    : super(Directory.systemTemp, const DepthModelManifest());
  bool installed;
  @override
  Future<bool> isReady(MediaCancellation token) async => installed;
}

class _Tasks implements DepthTaskController {
  _Tasks({required bool installed, this.finishImmediately = false})
    : models = _Models(installed);
  final bool finishImmediately;
  @override
  final _Models models;
  @override
  final state = ValueNotifier<DepthTask?>(null);
  int starts = 0, cancellations = 0;
  Completer<void>? _done;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> start(String novelId, String nodeId) async {
    starts++;
    final done = _done = Completer<void>();
    state.value = DepthTask(
      id: 'task-$starts',
      novelId: novelId,
      nodeId: nodeId,
      stage: DepthStage.inference,
      progress: 0.25,
    );
    if (finishImmediately) {
      finish();
    }
    await done.future;
  }

  void finish({bool fail = false, bool libraryOnly = false}) {
    final current = state.value!;
    models.installed = true;
    state.value = DepthTask(
      id: current.id,
      novelId: current.novelId,
      nodeId: current.nodeId,
      stage: fail ? DepthStage.failed : DepthStage.complete,
      failure: fail ? DepthFailure.native_failed : null,
      assetId: fail ? null : 'asset',
      outputNodeId: fail || libraryOnly ? null : 'output',
    );
    _done?.complete();
    _done = null;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_Tasks tasks) => ProviderScope(
  overrides: [depthTaskProvider.overrideWithValue(tasks)],
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
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showDepthDialog(
                      context,
                      novelId: 'work',
                      nodeId: 'node',
                    ),
                    child: const Text('Capture'),
                  ),
                  TextButton(
                    onPressed: () => showDepthDialog(context),
                    child: const Text('Task status'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder button(String label) => find.widgetWithText(RevericButton, label);

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets('shows connection, download percentage and verification stages', (
    tester,
  ) async {
    final tasks = _Tasks(installed: false);
    tasks.state.value = const DepthTask(
      id: 'task',
      novelId: 'work',
      nodeId: 'node',
      stage: DepthStage.connecting,
    );
    await tester.pumpWidget(_app(tasks));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task status'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Connecting to model source'), findsOneWidget);
    tasks.state.value = const DepthTask(
      id: 'task',
      novelId: 'work',
      nodeId: 'node',
      stage: DepthStage.downloading,
      progress: 0.42,
    );
    await tester.pump();
    expect(find.text('Downloading model'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    tasks.state.value = const DepthTask(
      id: 'task',
      novelId: 'work',
      nodeId: 'node',
      stage: DepthStage.verifying,
    );
    await tester.pump();
    expect(find.text('Verifying model'), findsOneWidget);
    expect(find.text('42%'), findsNothing);
    await tester.tap(button('Close'));
    await tester.pumpAndSettle();
    expect(tasks.cancellations, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tasks.state.dispose();
  });
  testWidgets('completion before the next frame still closes automatically', (
    tester,
  ) async {
    final tasks = _Tasks(installed: true, finishImmediately: true);
    await tester.pumpWidget(_app(tasks));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    expect(find.byType(RevericDialog), findsNothing);
    expect(tasks.starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tasks.state.dispose();
  });
  for (final installed in [false, true]) {
    testWidgets(
      'installed=$installed starts once and closes after completion',
      (tester) async {
        final tasks = _Tasks(installed: installed);
        await tester.pumpWidget(_app(tasks));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Capture'));
        await tester.pumpAndSettle();
        if (!installed) {
          expect(tasks.starts, 0);
          expect(button('Start'), findsOneWidget);
          await tester.tap(button('Start'));
          await tester.pumpAndSettle();
        }
        expect(tasks.starts, 1);
        expect(button('Start'), findsNothing);
        tasks.finish();
        await tester.pumpAndSettle();
        expect(find.byType(RevericDialog), findsNothing);
        expect(tasks.starts, 1);
        await tester.tap(find.text('Task status'));
        await tester.pumpAndSettle();
        expect(button('Start'), findsNothing);
        expect(button('Retry'), findsNothing);
        expect(tasks.starts, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        tasks.state.dispose();
      },
    );
  }
  testWidgets('failure stays open for retry and closing does not cancel work', (
    tester,
  ) async {
    final tasks = _Tasks(installed: true);
    await tester.pumpWidget(_app(tasks));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    tasks.finish(fail: true);
    await tester.pumpAndSettle();
    expect(find.byType(RevericDialog), findsOneWidget);
    await tester.tap(button('Retry'));
    await tester.pumpAndSettle();
    expect(tasks.starts, 2);
    await tester.tap(button('Close'));
    await tester.pumpAndSettle();
    expect(tasks.cancellations, 0);
    tasks.finish();
    await tester.pumpAndSettle();
    expect(find.text('Capture'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tasks.state.dispose();
  });
  testWidgets(
    'completion only closes its own route and reports library-only result',
    (tester) async {
      final tasks = _Tasks(installed: true);
      await tester.pumpWidget(_app(tasks));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(RevericDialog)),
          builder: (_) => const AlertDialog(content: Text('Another dialog')),
        ),
      );
      await tester.pumpAndSettle();
      tasks.finish(libraryOnly: true);
      await tester.pumpAndSettle();
      expect(find.text('Another dialog'), findsOneWidget);
      expect(find.byType(RevericDialog), findsNothing);
      expect(tasks.starts, 1);
      Navigator.of(tester.element(find.text('Another dialog'))).pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('saved in the asset library'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tasks.state.dispose();
    },
  );
}
