// 职责: 校验生成任务的制作来源，并幂等采用最新图片或视频结果。
// 关联文件:
//   lib/shared/services/ai/video/task_service.dart
//   lib/shared/providers/video_tasks.dart
//   lib/shared/services/production/canvas_service.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
import 'package:reveric/shared/models/generation/task.dart';
import 'package:drift/drift.dart';
import '../../database/app_database.dart' as app;
import '../../database/novel_content_database.dart';
import '../../logger/app_logger.dart';
import '../storyboard/service.dart';
import 'canvas_service.dart';

final _log = AppLogger.forModule('Production');

class ProductionResultService {
  ProductionResultService(this.database, this.resolve, {this.release});
  final Future<void> Function(ProductionCanvasService service)? release;
  final _applied = <String>{};
  final app.AppDatabase database;
  final Future<ProductionCanvasService?> Function(String novelId) resolve;
  static bool handles(String type) => type == 'production_clip';

  Future<app.GenerationTask?> latest(
    String novelId,
    String type,
    String id,
  ) async {
    final row = await database
        .customSelect(
          'SELECT id FROM generation_tasks WHERE novel_id = ? AND source_type = ? AND source_id = ? AND deleted_at = 0 ORDER BY rowid DESC LIMIT 1',
          variables: [Variable(novelId), Variable(type), Variable(id)],
          readsFrom: {database.generationTasks},
        )
        .getSingleOrNull();
    return row == null
        ? null
        : database.generationTaskDao.getById(row.read<String>('id'));
  }

  Future<void> beforeCreate(String novelId, String type, String id) async {
    if (!handles(type)) {
      return;
    }
    final service = await resolve(novelId);
    if (service == null) {
      throw const StoryboardException('source_missing');
    }
    try {
      await _source(service, type, id);
      final task = await latest(novelId, type, id);
      if (task != null &&
          task.status == GenerationTaskStatus.completed &&
          task.resultAssetId != null) {
        await apply(task, service);
      }
    } finally {
      await release?.call(service);
    }
  }

  Future<void> _source(
    ProductionCanvasService service,
    String type,
    String id,
  ) async {
    final clip = await service.shots.getShot(id);
    if (clip == null) {
      throw const StoryboardException('source_missing');
    }
    await service.shots.requireEpisode(clip.episodeId);
  }

  /// 生成结果入库时的资产名：取来源片段的标题，没有标题时为 null。
  Future<String?> sourceName(app.GenerationTask task) async {
    if (!handles(task.sourceType)) {
      return null;
    }
    final service = await resolve(task.novelId);
    if (service == null) {
      return null;
    }
    try {
      final title = (await service.shots.getShot(task.sourceId))?.title.trim();
      return title == null || title.isEmpty ? null : title;
    } finally {
      await release?.call(service);
    }
  }

  Future<void> beforeSubmit(app.GenerationTask task) async {
    if (!handles(task.sourceType)) {
      return;
    }
    final service = await resolve(task.novelId);
    if (service == null) {
      throw const StoryboardException('source_missing');
    }
    try {
      await service.write(task.sourceId, () async {
        await _source(service, task.sourceType, task.sourceId);
        final clip = (await service.shots.getShot(task.sourceId))!;
        if (clip.kind != task.kind.name) {
          throw const StoryboardException('invalid_config');
        }
        await service.shots.setErrorDismissed(task.sourceId, false);
        if ((await latest(task.novelId, task.sourceType, task.sourceId))?.id !=
            task.id) {
          throw const StoryboardException('source_missing');
        }
      });
    } finally {
      await release?.call(service);
    }
  }

  /// Uses the same source transaction as automatic adoption, so a completed
  /// adoption and a cancellation request have one observable order.
  Future<({bool accepted, bool resultApplied})> requestCancellation(
    String taskId,
  ) async {
    final task = await database.generationTaskDao.getById(taskId);
    if (task == null) {
      throw const StoryboardException('source_missing');
    }
    final service = await resolve(task.novelId);
    if (service == null) {
      throw const StoryboardException('source_missing');
    }
    try {
      return await service.write(task.sourceId, () async {
        final latestTask = (await database.generationTaskDao.getById(taskId))!;
        final clip = await service.shots.getShot(task.sourceId);
        final applied = clip?.lastAppliedGenerationTaskId == taskId;
        if (latestTask.status.isTerminal) {
          return (accepted: false, resultApplied: applied);
        }
        if (!await database.generationTaskDao.requestCancellation(taskId)) {
          return (accepted: false, resultApplied: applied);
        }
        await database.generationTaskDao.transition(
          taskId,
          {GenerationTaskStatus.prepared},
          const app.GenerationTasksCompanion(
            status: Value(GenerationTaskStatus.cancelled),
          ),
        );
        return (accepted: true, resultApplied: applied);
      });
    } finally {
      await release?.call(service);
    }
  }

  Future<void> apply(
    app.GenerationTask task,
    ProductionCanvasService service,
  ) => service.write(task.sourceId, () async {
    final current = await database.generationTaskDao.getById(task.id);
    if (current?.cancelRequestedAt != null) {
      return;
    }
    if (task.resultAssetId == null ||
        task.status != GenerationTaskStatus.completed) {
      return;
    }
    if ((await latest(task.novelId, task.sourceType, task.sourceId))?.id !=
        task.id) {
      return;
    }
    // A deleted source never gets recreated by a late result.
    {
      final shot = await service.shots.getShot(task.sourceId);
      if (shot == null || shot.lastAppliedGenerationTaskId == task.id) {
        return;
      }
      await service.shots.requireEpisode(shot.episodeId);
      if (shot.kind != task.kind.name) {
        throw const StoryboardException('invalid_config');
      }
      final asset = await service.requireAsset(
        task.resultAssetId!,
        type: task.kind.name,
      );
      await service.appendSubjectPhoto(shot, asset.id);
      await (service.db.update(
        service.db.productionClips,
      )..where((t) => t.id.equals(shot.id))).write(
        ProductionClipsCompanion(
          adoptedAssetId: Value(asset.id),
          lastAppliedGenerationTaskId: Value(task.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  });

  Future<void>? _recovering;
  Future<void> recover() => _recovering ??= _recover().whenComplete(() {
    _recovering = null;
  });

  Future<void> _recover() async {
    final rows = await database
        .customSelect(
          '''
      SELECT t.id FROM generation_tasks t WHERE t.deleted_at = 0
      AND t.source_type IN ('production_clip')
      AND t.rowid = (SELECT MAX(n.rowid) FROM generation_tasks n WHERE n.novel_id=t.novel_id
        AND n.source_type=t.source_type AND n.source_id=t.source_id AND n.deleted_at=0)
      AND ((t.status='completed' AND t.result_asset_id IS NOT NULL) OR (t.status='prepared' AND t.error_code='source_state_pending'))
    ''',
          readsFrom: {database.generationTasks},
        )
        .get();
    _applied.retainAll(rows.map((row) => row.read<String>('id')));
    for (final row in rows) {
      final taskId = row.read<String>('id');
      if (_applied.contains(taskId)) {
        continue;
      }
      final task = await database.generationTaskDao.getById(taskId);
      if (task == null) {
        continue;
      }
      try {
        final service = await resolve(task.novelId);
        if (service == null) {
          continue;
        }
        if (task.status == GenerationTaskStatus.completed) {
          try {
            await apply(task, service);
            _applied.add(task.id);
          } finally {
            await release?.call(service);
          }
        } else {
          await release?.call(service);
          await beforeSubmit(task);
          await database.generationTaskDao.transition(
            task.id,
            {GenerationTaskStatus.prepared},
            const app.GenerationTasksCompanion(
              errorCode: Value('awaiting_submission_confirmation'),
            ),
          );
        }
      } catch (error, stack) {
        _log.error(
          'result/state awaiting application task=${task.id}',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }
}
