// 职责: 验证导演台的分区操作、双视角隔离及中英文窄屏布局。
// 关联文件:
//   lib/shared/widgets/director/workspace.dart
//   lib/shared/widgets/director/stage.dart
//   test/desktop/director/harness.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/aspect_ratio.dart';
import 'package:reveric/shared/components/reveric_segmented_control.dart';
import 'package:reveric/shared/widgets/director/stage.dart';
import 'package:reveric/shared/widgets/director/timeline.dart';
import 'package:reveric/shared/services/director/session.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/director/grid.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/widgets/director/overlay.dart';
import 'package:reveric/shared/widgets/director/viewport.dart';
import 'package:reveric/shared/widgets/director/workspace.dart';
import 'harness.dart';
import 'package:reveric/shared/widgets/director/header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDirectorTest();
    if (Platform.environment['DIRECTOR_SCREENSHOT_DIR'] != null) {
      for (final family in ['Ahem', 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
        await loader.load();
      }
    }
  });
  setUp(() => rootBundle.clear());

  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    for (final size in [
      const Size(1440, 900),
      const Size(1024, 768),
      const Size(375, 812),
    ]) {
      testWidgets('director regions remain usable at $locale $size', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final document = DirectorDocument.parse(
          File('test/fixtures/director/scene.director.json').readAsStringSync(),
        );
        final session = DirectorSession(document);
        final boundary = GlobalKey();
        ViewState? mainView, previewView;
        await tester.pumpWidget(
          directorTestApp(
            RepaintBoundary(
              key: boundary,
              child: Material(
                color: RevericThemeData.reveric.colors.canvas,
                child: DirectorWorkspace(
                  session: session,
                  header: (viewMode) => DirectorHeader(
                    session: session,
                    onBack: () {},
                    center: viewMode,
                  ),
                  viewportBuilder: (session, view) {
                    // The GPU scene is excluded; this renders real workspace chrome and the real editor grid.
                    if (mainView == null || identical(mainView, view)) {
                      mainView = view;
                    } else {
                      previewView = view;
                    }
                    final colors = RevericThemeData.reveric.colors;
                    return LayoutBuilder(
                      builder: (context, c) => Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: DirectorGridPainter(
                              view.camera(),
                              colors.border,
                            ),
                          ),
                          if (!view.output)
                            ClipRect(
                              child: CustomPaint(
                                painter: StageOverlayPainter(
                                  StageOverlay(
                                    document: session.history.document,
                                    sample: sampleDocument(
                                      session.history.document,
                                      session.frame.value,
                                    ),
                                    camera: view.camera(),
                                    size: c.biggest,
                                    selected: session.selected,
                                    frame: session.frame.value,
                                  ),
                                  colors,
                                  RevericThemeData.reveric.typography.uiTiny,
                                  24,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(mainView!.output, isFalse);
        expect(tester.takeException(), isNull);
        final zh = locale.languageCode == 'zh';
        if (size.width >= 900) {
          expect(
            find.byKey(const ValueKey('director-camera-preview')),
            findsOneWidget,
          );
          expect(previewView!.output, isTrue);
          final mode = find.byKey(const ValueKey('director-view-mode'));
          await tester.tap(mode);
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .descendant(
                  of: mode,
                  matching: find.text(document.activeCameras.first['name']),
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(mainView!.output, isTrue);
          expect(session.viewCameraId, document.activeCameras.first['id']);
          expect(
            find.byKey(const ValueKey('director-camera-preview')),
            findsNothing,
          );
          await tester.tap(mode);
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .descendant(
                  of: mode,
                  matching: find.text(zh ? '导演视角' : 'Director view'),
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(mainView!.output, isFalse);
          expect(previewView!.output, isTrue);
        } else {
          await tester.tap(find.text(zh ? '对象' : 'Objects').first);
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(
            ValueKey('director-object:${document.objects.first['id']}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(session.selected, document.objects.first['id']);
        expect(
          find.byKey(const ValueKey('director-tab:actions')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('director-tab:props')));
        await tester.pumpAndSettle();
        final objectCount = session.history.document.objects.length;
        final cube = find.byKey(const ValueKey('director-prop:prop.cube.v1'));
        await tester.ensureVisible(cube);
        await tester.tap(cube);
        await tester.pumpAndSettle();
        expect(session.history.document.objects, hasLength(objectCount + 1));
        expect(
          session.history.document.objects.last['geometry_key'],
          'prop.cube.v1',
        );
        session.setPanel('actions');
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            ValueKey('director-object:${document.objects.first['id']}'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('director-action:stand')),
          findsNothing,
        );
        expect(
          find.text(zh ? '从动作库添加' : 'Add from library', skipOffstage: false),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('director-tab:cameras')));
        await tester.pumpAndSettle();
        final preset = find.byKey(
          const ValueKey('director-camera-preset:front_medium'),
        );
        for (final index in [1, 2]) {
          await tester.ensureVisible(preset);
          await tester.tap(preset);
          await tester.pumpAndSettle();
          expect(
            session.history.document.activeCameras.last['name'],
            zh ? '正面中景_$index' : 'Front medium $index',
          );
        }
        expect(tester.takeException(), isNull);

        expect(find.byKey(const ValueKey('director-tab:aspect')), findsNothing);
        final aspectButton = find.byKey(
          const ValueKey('director-aspect-button'),
        );
        Future<void> pickAspect(DirectorAspectRatio aspect) async {
          await tester.tap(aspectButton);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('director-aspect:${aspect.label}')),
          );
          await tester.pumpAndSettle();
        }

        for (final aspect in DirectorAspectRatio.values.skip(1)) {
          await pickAspect(aspect);
          expect(session.history.document.aspectRatio, aspect);
          // 选完收起弹层，顶栏按钮显示当前比例。
          expect(
            find.byKey(ValueKey('director-aspect:${aspect.label}')),
            findsNothing,
          );
          // 窄顶栏只留图标，比例写在提示里。
          expect(
            size.width < 720
                ? find.byTooltip('${zh ? '画幅' : 'Aspect'} · ${aspect.label}')
                : find.descendant(
                    of: aspectButton,
                    matching: find.text(aspect.label),
                  ),
            findsOneWidget,
          );
        }
        await pickAspect(DirectorAspectRatio.adaptive);
        final viewportSize = tester.getSize(
          find.byType(DirectorStage, skipOffstage: false),
        );
        expect((
          session.history.document.width,
          session.history.document.height,
        ), adaptiveOutputSize(viewportSize.width, viewportSize.height));
        final undoCount = session.history.undoCount;
        tester.view.physicalSize = Size(size.width, size.height + 80);
        await tester.pumpAndSettle();
        final resized = tester.getSize(
          find.byType(DirectorStage, skipOffstage: false),
        );
        expect((
          session.history.document.width,
          session.history.document.height,
        ), adaptiveOutputSize(resized.width, resized.height));
        expect(session.history.undoCount, undoCount);
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        if (size.width < 900) {
          await tester.tap(
            find.descendant(
              of: find.byType(RevericSegmentedControl<int>),
              matching: find.text(zh ? '导演视角' : 'Director view'),
            ),
          );
          await tester.pumpAndSettle();
        }
        final beforeUndo = session.history.document.businessContent;
        await tester.tap(find.byKey(const ValueKey('director-undo')));
        await tester.pumpAndSettle();
        expect(session.history.canRedo, true);
        await tester.tap(find.byKey(const ValueKey('director-redo')));
        await tester.pumpAndSettle();
        expect(session.history.document.businessContent, beforeUndo);

        final outputDir = Platform.environment['DIRECTOR_SCREENSHOT_DIR'];
        if (outputDir != null) {
          if (size.width < 900) {
            await tester.tap(
              find.descendant(
                of: find.byType(RevericSegmentedControl<int>),
                matching: find.text(zh ? '导演视角' : 'Director view'),
              ),
            );
            await tester.pumpAndSettle();
          }
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(outputDir).create(recursive: true);
            await File(
              '$outputDir/${locale.toLanguageTag()}-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final sampledBeforeRemoval = sampleDocument(
          session.history.document,
          session.frame.value,
        );
        session.history.execute((json) {
          for (final camera in json['cameras']) {
            if (camera['orientation_mode'] == 'look_at') {
              camera['camera_target'] = {
                'type': 'point',
                'position':
                    sampledBeforeRemoval.cameras[camera['id']]!['target'],
              };
            }
          }
        });
        for (final object in session.history.document.objects) {
          session.history.remove(object['id']);
        }
        await tester.pumpAndSettle();
        expect(session.history.document.objects, isEmpty);
        expect(find.byType(DirectorTimeline), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('director-undo')));
        await tester.pumpAndSettle();
        expect(session.history.document.objects, isNotEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('playback previews the cut sequence in the main viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final document = DirectorDocument.parse(
      File('test/fixtures/director/scene.director.json').readAsStringSync(),
    );
    final session = DirectorSession(document);
    addTearDown(session.dispose);
    ViewState? mainView;
    await tester.pumpWidget(
      directorTestApp(
        Material(
          child: DirectorWorkspace(
            session: session,
            viewportBuilder: (session, view) {
              mainView ??= view;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final camera = document.activeCameras.last['id'] as String;
    session.select(camera);
    await tester.pump();
    expect(session.cameraMode, 'fixed');
    expect(mainView!.output, isFalse);

    await tester.tap(find.byKey(const ValueKey('director-play')));
    await tester.pump();
    expect(session.playing, isTrue);
    expect(mainView!.output, isTrue);
    expect(session.cameraMode, 'sequence');
    expect(find.byKey(const ValueKey('director-camera-preview')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('director-play')));
    await tester.pump();
    expect(session.playing, isFalse);
    expect(mainView!.output, isFalse);
    expect(session.viewCameraId, camera);
    expect(session.cameraMode, 'fixed');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
