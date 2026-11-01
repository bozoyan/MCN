// 职责: 导出导演台的静帧或视频：渲染调度、登记资产，并按需放到画布导演台节点右侧。
// 关联文件:
//   lib/shared/services/director/export_task.dart
//   lib/shared/services/production/director_output_orchestrator.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/director/file_output.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import '../../database/app_database.dart';
import '../../database/novel_content_database.dart';
import '../../models/director/document.dart';
import '../director/export_task.dart';
import '../director/file_output.dart';
import '../director/renderer.dart';
import '../storyboard/service.dart';
import 'canvas_service.dart';
import 'director_output_orchestrator.dart';

class StagingExportOrchestrator {
  /// [still] 为 true 时导出第 0 帧静帧，否则导出整段预演；机位按切镜序列选择。
  Future<CanvasNode> run({
    required ProductionCanvasService canvas,
    required String directorNodeId,
    required bool still,
    FrameRenderer? renderer,
  }) async {
    final node = await canvas.requireNode(directorNodeId);
    final staging = node.stagingId == null
        ? null
        : await canvas.db.screenplayDao.getStaging(node.stagingId!);
    if (staging?.document == null) {
      throw const StoryboardException('invalid_config');
    }
    final document = DirectorDocument.fromJson(staging!.document!);
    final task = ExportTaskOrchestrator();
    try {
      final asset = await render(
        canvas: canvas,
        stagingId: staging.id,
        document: document,
        task: task,
        frame: still ? 0 : null,
        savedRevisionId: '${staging.version}',
        renderer: renderer,
      );
      return await canvas.addStagingOutput(directorNodeId, asset.id);
    } finally {
      task.dispose();
    }
  }

  /// 渲染 [document] 并登记为资产，不放到画布。[frame] 非空时导出这一帧静帧，
  /// 否则导出整段；[cameraId] 为空时按切镜序列选机位。进度和取消走 [task]。
  Future<AssetRow> render({
    required ProductionCanvasService canvas,
    required String stagingId,
    required DirectorDocument document,
    required ExportTaskOrchestrator task,
    int? frame,
    String? cameraId,
    String? savedRevisionId,
    FrameRenderer? renderer,
  }) async {
    if (document.activeCameras.isEmpty) {
      throw const StoryboardException('invalid_config');
    }
    AssetRow? asset;
    Object? registerError;
    StackTrace? registerStack;
    await task.run(
      workspace: await DirectorFileOutput.workspace(
        stagingId,
        novelId: canvas.novelId,
      ),
      document: document,
      renderer: renderer ?? DirectorRenderer(),
      cameraMode: cameraId == null ? 'sequence' : 'fixed',
      cameraId: cameraId,
      singleFrame: frame,
      savedRevisionId: savedRevisionId,
      onRendered: (frames, manifest) async {
        try {
          asset = await DirectorOutputOrchestrator().run(
            library: canvas.library,
            novelId: canvas.novelId,
            documentTitle: document.title,
            cameraName: document.camera(cameraId)?['name'],
            frames: frames,
            manifest: manifest,
            task: task,
          );
        } catch (error, stack) {
          // 导出任务会把所有失败归成 capture_failed；留住真实原因交给调用方。
          registerError = error;
          registerStack = stack;
          rethrow;
        }
      },
    );
    if (registerError != null) {
      Error.throwWithStackTrace(registerError!, registerStack!);
    }
    if (task.state != OutputState.completed || asset == null) {
      throw StateError(task.errorCode ?? 'director_export_failed');
    }
    return asset!;
  }
}
