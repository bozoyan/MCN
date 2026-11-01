// 职责: 验证角色目录的默认选项、异步初始人物、搜索、添加与桌面移动布局。
// 关联文件:
//   lib/shared/widgets/director/workspace.dart
//   lib/shared/widgets/director/panels/actors.dart
//   test/desktop/director/harness.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/actor_catalog.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/director/workspace.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDirectorTest();
    if (Platform.environment['DIRECTOR_SCREENSHOT_DIR'] != null) {
      for (final family in ['Ahem', 'Roboto']) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf')))
            .load();
      }
    }
  });
  setUp(() => rootBundle.clear());

  Future<DirectorSession> mount(
    WidgetTester tester, {
    DirectorActorCatalog? catalog,
    Size size = const Size(1440, 900),
    GlobalKey? boundary,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final session = DirectorSession(DirectorDocument.blank('Scene'))
      ..setPanel('actors');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
    await tester.pumpWidget(
      directorTestApp(
        RepaintBoundary(
          key: boundary,
          child: DirectorWorkspace(
            session: session,
            actorCatalog: catalog,
            viewportBuilder: (_, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (size.width < 900) {
      await tester.tap(find.text('Objects').first);
      await tester.pumpAndSettle();
    }
    return session;
  }

  testWidgets(
    'repeated selection keeps one actor and selects the existing instance',
    (tester) async {
      final session = await mount(
        tester,
        catalog: const DirectorActorCatalog(
          initialActors: [DirectorActor(id: 'han', name: '韩可心')],
        ),
      );
      final option = find.byKey(const ValueKey('director-actor-option:han'));
      await tester.tap(option);
      await tester.pumpAndSettle();
      final firstId = session.history.document.objects.single['id'];
      session.select(null);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(session.history.document.objects, hasLength(1));
      expect(session.selected, firstId);
    },
  );

  testWidgets(
    'catalog identity survives renaming, document reload, deletion and undo',
    (tester) async {
      const actor = DirectorActor(id: 'original', name: 'Same name');
      const other = DirectorActor(id: 'different', name: 'Same name');
      final session = await mount(
        tester,
        catalog: const DirectorActorCatalog(initialActors: [actor, other]),
      );
      final firstId = session.history.addActor(actor);
      session.history.execute(
        (j) => j['objects'][0]['name'] = 'Renamed in scene',
      );
      final encoded = session.history.document.encode();
      session.replace(DirectorDocument.parse(encoded), saved: true);
      expect(session.history.addActor(actor), firstId);
      expect(
        session.history.document.objects.single['name'],
        'Renamed in scene',
      );
      expect(session.history.dirty, isFalse);
      session.history.remove(firstId);
      expect(session.history.document.objects, isEmpty);
      session.history.undo();
      expect(session.history.document.objects.single['id'], firstId);
      session.history.redo();
      expect(session.history.document.objects, isEmpty);
      final addedId = session.history.addActor(actor);
      expect(addedId, isNot(firstId));
      expect(session.history.document.objects.single['catalog_id'], actor.id);
      session.history.execute((j) => j['objects'][0]['name'] = other.name);
      final secondId = session.history.addActor(other);
      expect(secondId, isNot(firstId));
      expect(session.history.document.objects, hasLength(2));
      expect(
        () => session.history.document.mutate(
          (j) => j['objects'][1]['catalog_id'] = actor.id,
        ),
        throwsA(isA<DocumentError>()),
      );
      // Re-instantiating an imported document preserves source identities as well.
      session.replace(session.history.document.instantiate(), saved: true);
      session.history.addActor(actor);
      expect(session.history.document.objects, hasLength(2));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'default catalog adds named male and female snapshots with undo',
    (tester) async {
      final session = await mount(tester);
      await tester.tap(
        find.byKey(const ValueKey('director-actor-option:female')),
      );
      await tester.pumpAndSettle();
      expect(session.history.document.objects.single['name'], 'Female actor');
      expect(
        session.history.document.objects.single['geometry_key'],
        'actor.female.v1',
      );
      expect(session.selected, session.history.document.objects.single['id']);
      expect(find.text('Body'), findsNothing);
      session.history.undo();
      expect(session.history.document.objects, isEmpty);
      session.history.redo();
      expect(session.history.document.objects.single['name'], 'Female actor');
    },
  );

  for (final size in [const Size(1440, 900), const Size(375, 812)]) {
    testWidgets(
      'initial cast searches and remains selectable while loader completes at $size',
      (tester) async {
        final request = Completer<List<DirectorActor>>();
        final boundary = GlobalKey();
        final session = await mount(
          tester,
          size: size,
          boundary: boundary,
          catalog: DirectorActorCatalog(
            initialActors: const [
              DirectorActor(
                id: 'lin',
                name: '林音',
                body: DirectorActorBody.female,
              ),
            ],
            load: () => request.future,
          ),
        );
        expect(find.text('林音'), findsOneWidget);
        expect(find.text('Male actor'), findsNothing);
        final catalogRow = find.byKey(
          const ValueKey('director-actor-option:lin'),
        );
        await tester.tap(catalogRow);
        await tester.pumpAndSettle();
        expect(session.history.document.objects.single['name'], '林音');
        request.complete(const [
          DirectorActor(
            id: 'river',
            name: 'River',
            body: DirectorActorBody.male,
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('River'), findsOneWidget);
        expect(find.text('In this scene'), findsOneWidget);
        expect(find.text('Other characters'), findsOneWidget);
        bool placed(String id) => find
            .descendant(
              of: find.byKey(ValueKey('director-actor-option:$id')),
              matching: find.byWidgetPredicate(
                (w) => w is RevericIcon && w.assetPath == RevericIcons.check,
              ),
            )
            .evaluate()
            .isNotEmpty;
        expect(placed('lin'), isTrue);
        expect(placed('river'), isFalse);
        final search = find.descendant(
          of: find.byKey(const ValueKey('director-actor-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'river');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(catalogRow, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 200));
        expect(catalogRow, findsNothing);
        await tester.enterText(search, '');
        await tester.pump();
        expect(catalogRow, findsOneWidget);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['DIRECTOR_SCREENSHOT_DIR'];
        if (output != null) {
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File(
              '$output/actor-catalog-${size.width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
  testWidgets(
    'unspecified body adds the default mannequin without a gender prompt',
    (tester) async {
      final session = await mount(
        tester,
        catalog: const DirectorActorCatalog(
          initialActors: [DirectorActor(id: 'unknown', name: 'Alex')],
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('director-actor-option:unknown')),
      );
      await tester.pumpAndSettle();
      expect(session.history.document.objects.single['name'], 'Alex');
      expect(
        session.history.document.objects.single['geometry_key'],
        'actor.male.v1',
      );
      expect(find.text('Male'), findsNothing);
      expect(find.text('Female'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('explicit empty catalog does not introduce default actors', (
    tester,
  ) async {
    await mount(tester, catalog: const DirectorActorCatalog(initialActors: []));
    expect(find.text('No actors available'), findsOneWidget);
    expect(find.text('Male actor'), findsNothing);
  });
  testWidgets('loader failure shows retry and never substitutes defaults', (
    tester,
  ) async {
    var attempts = 0;
    await mount(
      tester,
      catalog: DirectorActorCatalog(
        load: () async {
          if (attempts++ == 0) {
            throw StateError('source unavailable');
          }
          return [];
        },
      ),
    );
    expect(find.text('Unable to load actors'), findsOneWidget);
    expect(find.text('Female actor'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No actors available'), findsOneWidget);
    expect(find.text('Unable to load actors'), findsNothing);
  });
}
