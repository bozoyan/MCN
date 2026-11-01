// 职责: 用独立 Flutter GPU 场景捕获固定尺寸 PNG 并释放帧资源。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/scene_builder.dart
import 'dart:typed_data';
import 'prop_models.dart';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';

import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/actor_models.dart';
import 'package:reveric/shared/services/director/scene_builder.dart';

abstract interface class FrameRenderer {
  Future<Uint8List> capture(
    DirectorDocument document,
    int frame,
    String cameraId,
  );
  void dispose();
}

class DirectorRenderer implements FrameRenderer {
  SceneBuilder? _builder;
  String? _identity;
  @override
  Future<Uint8List> capture(
    DirectorDocument document,
    int frame,
    String cameraId,
  ) async {
    await Scene.initializeStaticResources();
    await ActorModels.load();
    if (_identity != document.encode()) {
      _builder?.dispose();
      _builder = SceneBuilder(document, props: await PropModels.load(document));
      _identity = document.encode();
    }
    final builder = _builder!,
        camera = builder.apply(document, frame, cameraId);
    final recorder = ui.PictureRecorder();
    // Each capture owns its Picture and Image. No frame is retained by the app.
    final target = ui.Canvas(recorder);
    target.drawColor(
      ui.Color(
        0xFF000000 | int.parse(document.background.substring(1), radix: 16),
      ),
      ui.BlendMode.src,
    );
    builder.scene.render(
      camera,
      target,
      viewport: ui.Rect.fromLTWH(
        0,
        0,
        document.width.toDouble(),
        document.height.toDouble(),
      ),
      pixelRatio: 1,
    );
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(document.width, document.height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('capture_failed');
      }
      return data.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _builder?.dispose();
    _builder = null;
    _identity = null;
  }
}
