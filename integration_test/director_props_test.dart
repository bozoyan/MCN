// 职责: 用真实 GPU 验证内置道具缓存、失败重试、实例隔离、尺寸与 PNG 渲染。
// 关联文件:
//   lib/shared/services/director/prop_models.dart
//   lib/shared/services/director/scene_builder.dart
//   lib/shared/services/director/renderer.dart
//   lib/shared/models/director/presets.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/prop_catalog.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/prop_models.dart';
import 'package:reveric/shared/services/director/renderer.dart';
import 'package:reveric/shared/services/director/scene_builder.dart';
import 'package:vector_math/vector_math.dart' as v;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'builtin GLB props load at meter scale and render',
    (tester) async {
      await tester.runAsync(() async {
        const requested = String.fromEnvironment('DIRECTOR_ACCEPTANCE_DIR');
        final root = requested.isEmpty
            ? await Directory.systemTemp.createTemp('reveric_props_')
            : await Directory(requested).create(recursive: true);
        await Scene.initializeStaticResources();
        final renderer = DirectorRenderer();
        final originalPrint = debugPrint;
        var decodes = 0;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message?.startsWith('Unpacking glTF (nodes: 1,') == true) {
            decodes++;
          }
          originalPrint(message, wrapWidth: wrapWidth);
        };
        try {
          final failing = CommandHistory(DirectorDocument.blank('Retry'));
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          var failedReads = 0;
          failing.addObject('prop.wall.v1', 'Wall');
          messenger.setMockMessageHandler('flutter/assets', (_) async {
            failedReads++;
            return null;
          });
          try {
            await expectLater(
              Future.wait([
                for (var i = 0; i < 3; i++) PropModels.load(failing.document),
              ]),
              throwsA(isA<FlutterError>()),
            );
            expect(failedReads, 1);
          } finally {
            messenger.setMockMessageHandler('flutter/assets', null);
            failing.dispose();
          }
          for (final prop in propPresets) {
            final history = CommandHistory(DirectorDocument.blank(prop.name));
            try {
              final key = 'prop.${prop.name}.v1';
              history.addObject(key, prop.name);
              final size = prop.size;
              final extent = size.reduce(math.max);
              history.execute((json) {
                json['output'] = {
                  'width': 640,
                  'height': 360,
                  'aspect_mode': 'auto',
                  'background': '#BFC5CC',
                };
                json['cameras'][0]['position'] = [
                  extent * 1.8,
                  extent * 1.5,
                  extent * 2.4,
                ];
                json['cameras'][0]['camera_target'] = {
                  'type': 'point',
                  'position': [
                    0,
                    prop.defaultPosition[1] + prop.minimum[1] + size[1] / 2,
                    0,
                  ],
                };
              });
              final document = DirectorDocument.parse(
                history.document.encode(),
              );
              // 主视口、预览、导出同时请求；失败过的 wall 也必须能重新加载。
              final concurrent = await Future.wait([
                for (var i = 0; i < 3; i++) PropModels.load(document),
              ]);
              final models = concurrent.first;
              for (final loaded in concurrent.skip(1)) {
                expect(loaded[key], same(models[key]));
              }
              expect((await PropModels.load(document))[key], same(models[key]));
              final bounds = models[key]!.combinedLocalBounds!;
              for (var axis = 0; axis < 3; axis++) {
                expect(
                  bounds.max[axis] - bounds.min[axis],
                  closeTo(size[axis], 1e-5),
                );
              }
              for (var axis = 0; axis < 3; axis++) {
                expect(bounds.min[axis], closeTo(prop.minimum[axis], 1e-5));
              }
              final scene = SceneBuilder(document, props: models);
              final edited = document.mutate((json) {
                json['objects'][0]['position'] = [2, 1, 0];
                json['objects'][0]['color'] = '#FF0000';
              });
              final other = SceneBuilder(edited, props: concurrent.last);
              try {
                scene.apply(document, 0, document.defaultCameraId);
                other.apply(edited, 0, edited.defaultCameraId);
                final first = scene.roots.values.single;
                final second = other.roots.values.single;
                second.highlightColor = v.Vector4(0, 1, 0, 1);
                expect(first.position.x, 0);
                expect(second.position.x, 2);
                expect(first.highlightColor, isNull);
                expect(models[key]!.highlightColor, isNull);
                final originalPrimitive =
                    first.meshNodes.first.mesh!.primitives.first;
                final editedPrimitive =
                    second.meshNodes.first.mesh!.primitives.first;
                expect(
                  originalPrimitive.geometry,
                  same(editedPrimitive.geometry),
                );
                expect(
                  (originalPrimitive.material as PhysicallyBasedMaterial)
                      .baseColorFactor,
                  v.Vector4(1, 1, 1, 1),
                );
                expect(
                  originalPrimitive.material.doubleSided,
                  models[key]!
                      .meshNodes
                      .first
                      .mesh!
                      .primitives
                      .first
                      .material
                      .doubleSided,
                );
                if (prop.name == 'plane') {
                  expect(originalPrimitive.material.doubleSided, isTrue);
                }
                expect(
                  (editedPrimitive.material as PhysicallyBasedMaterial)
                      .baseColorFactor,
                  v.Vector4(1, 0, 0, 1),
                );
                expect(
                  scene.roots.values.single.children.single,
                  isNot(same(models[key])),
                );
                expect(scene.owners.length, greaterThan(1));
              } finally {
                scene.dispose();
                other.dispose();
              }
              final bytes = await renderer.capture(
                document,
                0,
                document.defaultCameraId,
              );
              final codec = await ui.instantiateImageCodec(bytes);
              final frame = await codec.getNextFrame();
              expect((frame.image.width, frame.image.height), (640, 360));
              frame.image.dispose();
              codec.dispose();
              await File('${root.path}/${prop.name}.png').writeAsBytes(bytes);
            } finally {
              history.dispose();
            }
          }
          const input = String.fromEnvironment('DIRECTOR_DOCUMENT_FILE');
          if (input.isNotEmpty) {
            final document = DirectorDocument.parse(
              await File(input).readAsString(),
            );
            final bytes = await renderer.capture(
              document,
              0,
              document.cameras.last['id'],
            );
            await File('${root.path}/staging-overview.png').writeAsBytes(bytes);
          }
          expect(decodes, propPresets.length);
          debugPrint('DIRECTOR_PROP_DECODES=$decodes');
          debugPrint('DIRECTOR_PROP_ARTIFACTS=${root.path}');
        } finally {
          debugPrint = originalPrint;
          renderer.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
