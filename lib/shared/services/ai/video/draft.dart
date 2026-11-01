// 职责: 根据视频任务快照判断样片能力、成片期限，以及片段当前采用的样片。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/video/channels.dart
//   lib/shared/services/ai/video/task_service.dart

import '../../../database/app_database.dart';
import '../../../models/video/channels.dart';

/// 样片固定 480p；按样片 ID 生成的成片固定 1080p（供应商要求）。
const videoDraftResolution = '480p';
const videoDraftFinalResolution = '1080p';

extension VideoDraftTask on GenerationTask {
  bool get supportsDraftCompletion =>
      kind == GenerationKind.video &&
      draft &&
      lookupVideoChannelModel(
            providerType,
            modelId,
          )?.protocolOptions.supportsDraft ==
          true;

  DateTime? get draftExpiresAt => submittedAt?.add(const Duration(days: 7));

  bool isDraftExpired(DateTime now) =>
      draftExpiresAt != null && !draftExpiresAt!.isAfter(now);
}

/// 片段当前采用的样片：[run] 是它在生成记录里的序号（从 1 起），
/// [completion] 是由它生成的最近一次成片任务（没有为 null）。
typedef AdoptedVideoDraft = ({
  GenerationTask task,
  int run,
  GenerationTask? completion,
});

/// [tasks] 为同一片段的生成记录，新的在前；采用的不是样片时返回 null。
AdoptedVideoDraft? adoptedVideoDraft(
  List<GenerationTask> tasks,
  String? adoptedAssetId,
) {
  if (adoptedAssetId == null) {
    return null;
  }
  final index = tasks.indexWhere(
    (t) => t.draft && t.resultAssetId == adoptedAssetId,
  );
  if (index < 0) {
    return null;
  }
  final task = tasks[index];
  return (
    task: task,
    run: tasks.length - index,
    completion: tasks.where((t) => t.draftTaskId == task.id).firstOrNull,
  );
}
