// 职责: 串行保存全景截图并登记资产与派生节点，保留已完成的部分结果。
// 关联文件:
//   lib/shared/providers/production_panorama.dart
//   lib/shared/widgets/production/panorama/capture.dart
//   lib/shared/services/production/canvas_service.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/file-access.md
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../database/novel_content_database.dart';
import '../../logger/app_logger.dart';
import '../../models/asset_purpose.dart';
import '../../models/production/panorama.dart';
import '../../models/video/request.dart';
import '../../widgets/production/panorama/capture.dart';
import '../../widgets/production/panorama/texture.dart';
import 'canvas_service.dart';
import 'ffmpeg_runner.dart';
import 'node_source.dart';
import '../../models/production/view_presets.dart';
import '../../models/production/media.dart';
import '../../database/app_database.dart' show AssetRow;
import '../storyboard/service.dart';

final _log = AppLogger.forModule('Panorama');

typedef PanoramaCaptureRequest = ({PanoramaView view, String name});
typedef PanoramaRender =
    Future<Uint8List> Function(ui.Image image, PanoramaView view, ui.Size size);

enum PanoramaCaptureStage { render, write, register, placement }

class PanoramaCaptureFailure {
  const PanoramaCaptureFailure(this.stage, this.error);
  final PanoramaCaptureStage stage;
  final Object error;
}

class PanoramaCaptureResult {
  PanoramaCaptureResult(
    this.nodes,
    this.failures, {
    this.byView = const {},
    this.viewFailures = const {},
    this.registeredAssets = const {},
  });
  final List<CanvasNode> nodes;
  final Map<String, PanoramaCaptureFailure> failures;
  final Map<int, CanvasNode> byView;
  final Map<int, PanoramaCaptureFailure> viewFailures;
  final Map<int, AssetRow> registeredAssets;
}

bool isProductionPanoramaSource(CanvasNode node) =>
    {canvasNodeTypeImage, canvasNodeTypeMedia}.contains(node.type) &&
    (PanoramaView.fromStyle(node.style) != null ||
        (node.type == canvasNodeTypeImage &&
            ImageGenerationPreset.fromStyle(node.style).method ==
                ImageGenerationMethod.panorama));

class PanoramaService {
  PanoramaService(this.canvas, {this.render = PanoramaCapture.render});
  final ProductionCanvasService canvas;
  final PanoramaRender render;
  bool _capturing = false;
  Future<PanoramaCaptureResult> capture(
    String nodeId,
    List<PanoramaCaptureRequest> requests, {
    ProductionNodeSource? inputSource,
    MediaCancellation? cancellation,
    ProductionNodePlacement? placement,
  }) async {
    if (_capturing || requests.isEmpty || requests.length > 4) {
      throw StateError('Invalid or active capture');
    }
    requests = List.unmodifiable(requests);
    for (final request in requests) {
      request.view.validate();
    }
    final token = cancellation ?? MediaCancellation();
    void checkCancelled() {
      if (token.cancelled) {
        throw const MediaException(MediaFailure.cancelled);
      }
    }

    _capturing = true;
    try {
      checkCancelled();
      if (!isProductionPanoramaSource(await canvas.requireNode(nodeId))) {
        throw const StoryboardException('invalid_reference');
      }
      final source = inputSource?.node ?? await canvas.requireNode(nodeId);
      final asset =
          inputSource?.asset ??
          await canvas.inputAsset(
            ProductionInput.node(nodeId, VideoInputRole.reference_image),
          );
      final size = panoramaCaptureSize(
        (await canvas.shots.requireSettings()).ratio,
      );
      final nodes = await canvas.db.canvasDao.getNodesByCanvas(source.canvasId);
      final origin =
          placement?.at ?? panoramaGroupOrigin(source, nodes, requests.length);
      final texture = await PanoramaTextures.acquire(
        inputSource?.path ?? canvas.library.resolve(asset),
      );
      try {
        final temporary = await Directory.systemTemp.createTemp(
          'reveric_panorama_capture_',
        );
        try {
          final completed = <CanvasNode>[];
          final failures = <String, PanoramaCaptureFailure>{};
          final byView = <int, CanvasNode>{};
          final viewFailures = <int, PanoramaCaptureFailure>{};
          final registered = <int, AssetRow>{};
          for (final (index, request) in requests.indexed) {
            var stage = PanoramaCaptureStage.render;
            try {
              checkCancelled();
              final bytes = await render(texture.image, request.view, size);
              checkCancelled();
              stage = PanoramaCaptureStage.write;
              final file = await File(
                '${temporary.path}/$index.png',
              ).writeAsBytes(bytes, flush: true);
              checkCancelled();
              stage = PanoramaCaptureStage.register;
              final saved = await canvas.library.importFile(
                file,
                name: '${request.name}.png',
                novelId: canvas.novelId,
                purpose: AssetPurpose.production_output,
                cancellation: token,
                source: 'panorama_capture',
              );
              registered[index] = saved;
              stage = PanoramaCaptureStage.placement;
              final node = await canvas.addDerivedOutput(
                nodeId,
                saved.id,
                title: request.name,
                placement: (
                  at: (
                    x: origin.x + (index % 2) * 340,
                    y: origin.y + (index ~/ 2) * 340,
                  ),
                  moves: placement?.moves ?? {},
                ),
              );
              completed.add(node);
              byView[index] = node;
            } catch (error, stack) {
              final failure = PanoramaCaptureFailure(stage, error);
              failures[request.name] = failure;
              viewFailures[index] = failure;
              _log.error(
                'capture failed index=$index node=$nodeId',
                error: error,
                stackTrace: stack,
              );
            }
          }
          return PanoramaCaptureResult(
            completed,
            failures,
            byView: Map.unmodifiable(byView),
            viewFailures: Map.unmodifiable(viewFailures),
            registeredAssets: Map.unmodifiable({
              for (final entry in registered.entries)
                if (!byView.containsKey(entry.key)) entry.key: entry.value,
            }),
          );
        } finally {
          await temporary.delete(recursive: true);
        }
      } finally {
        texture.dispose();
      }
    } finally {
      _capturing = false;
    }
  }
}

/// 整组先找空位，空槽也为失败的方向保留，保证四向始终是同一 2×2 布局。
({double x, double y}) panoramaGroupOrigin(
  CanvasNode source,
  List<CanvasNode> nodes,
  int count,
) {
  final x = source.x + math.max(source.width ?? 300, 300) + 120;
  var y = source.y;
  final width = count == 1 ? 300.0 : 640.0;
  final height = count <= 2 ? 300.0 : 640.0;
  while (nodes.any(
    (n) => ui.Rect.fromLTWH(
      n.x,
      n.y,
      math.max(n.width ?? 300, 300),
      math.max(n.height ?? 300, 300),
    ).inflate(24).overlaps(ui.Rect.fromLTWH(x, y, width, height)),
  )) {
    y += height + 40;
  }
  return (x: x, y: y);
}
