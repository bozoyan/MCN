// 职责: 原子保存人工剧本文档并接管脏场次 AI 提议，提交后单独同步作品统计。
// 关联文件:
//   lib/shared/models/screenplay_document.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md

import 'dart:convert';
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/screenplay_document.dart';
import 'screenplay_service.dart';
import 'working_overlay.dart';

final _log = AppLogger.forModule('ScreenplayEditOrchestrator');

class ScreenplayDocumentSaveResult {
  const ScreenplayDocumentSaveResult(
    this.document, {
    this.statisticsPending = false,
    this.sceneIds = const {},
    this.elementIds = const {},
  });
  final ScreenplayDocument document;
  final bool statisticsPending;
  final Map<String, String> sceneIds;
  final Map<String, String> elementIds;
}

class ScreenplayEditOrchestrator {
  Future<ScreenplayDocumentSaveResult> save({
    required NovelContentDatabase database,
    required ScreenplayService service,
    required WorkingOverlayService overlay,
    required ScreenplayDocument baseline,
    required ScreenplayDocument target,
  }) async {
    late ScreenplayDocument saved;
    var sceneIds = <String, String>{};
    var elementIds = <String, String>{};
    try {
      saved = await database.transaction(() async {
        final dirty = await service.validateDocumentBaseline(baseline, target);
        if (dirty.isNotEmpty) {
          await overlay.takeOverScreenplayScenes(
            dirty.difference(target.newSceneIds),
          );
          final applied = await service.applyDocument(baseline, target, dirty);
          target = applied.document;
          sceneIds = applied.sceneIds;
          elementIds = applied.elementIds;
          final changes = <String>[];
          for (final id in dirty) {
            final before = baseline.scenes[id];
            final after = target.scenes[id];
            if (before == null || after == null) {
              continue;
            }
            final oldValues = <String, String>{
              'title': before.title,
              'emotion': jsonEncode(before.emotion),
              'events': jsonEncode(before.events),
              'interior_exterior': jsonEncode(
                baseline.sceneElements(id).first.interiorExterior,
              ),
            };
            final newValues = <String, String>{
              'title': after.title,
              'emotion': jsonEncode(after.emotion),
              'events': jsonEncode(after.events),
              'interior_exterior': jsonEncode(
                target.sceneElements(id).first.interiorExterior,
              ),
            };
            for (final field in oldValues.keys) {
              if (oldValues[field] == newValues[field]) {
                continue;
              }
              final change = await overlay.stageTextChange(
                resourcePath: 'scenes/$id/$field',
                resourceType: workingChangeResourceTypeScreenplayScenes,
                resourceId: id,
                field: field,
                oldText: oldValues[field]!,
                newText: newValues[field]!,
                source: workingChangeSourceManual,
              );
              changes.add(change.id);
            }
          }
          await overlay.commitManualSave(
            manualChangeIds: changes,
            resourceScopes: dirty.map((id) => 'scenes/${sceneIds[id] ?? id}'),
            manualMessage: 'history.commit_message.manual_scene_save',
          );
        }
        return service.readDocument(
          target.episodeId,
          sceneIds: target.fullEpisode ? null : target.scenes.keys.toSet(),
          previousSceneId: target.previousSceneId,
          nextSceneId: target.nextSceneId,
          evidenceIds: {...baseline.evidence.keys, ...target.evidence.keys},
        );
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=screenplay_scenes,working_changes operation=MANUAL_SAVE id=${target.episodeId}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    var pending = false;
    try {
      await service.syncNovelWordCount();
    } catch (error, stackTrace) {
      pending = true;
      _log.error(
        'Screenplay saved; work statistics pending',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return ScreenplayDocumentSaveResult(
      saved,
      statisticsPending: pending,
      sceneIds: sceneIds,
      elementIds: elementIds,
    );
  }
}
