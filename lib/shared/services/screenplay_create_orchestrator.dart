// 职责: 预先校验场次创建输入，原子写入场次、正文、角色与创建变更，提交后同步统计。
// 关联文件:
//   lib/shared/services/screenplay_service.dart
//   lib/shared/services/ai/tools_screenplay.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/screenplay_element.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md

import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/screenplay_element.dart';
import 'screenplay_service.dart';

final _log = AppLogger.forModule('ScreenplayCreateOrchestrator');

class ScreenplayCreateOrchestrator {
  Future<String> createScene({
    required NovelContentDatabase database,
    required ScreenplayService service,
    required String screenplayId,
    required String episodeId,
    required String stage,
    required String timeLabel,
    required String synopsis,
    required Future<void> Function(String sceneId) stageCreateChange,
    String title = '',
    List<String>? emotion,
    List<Map<String, dynamic>>? events,
    String? beatId,
    String? locationId,
    String? interiorExterior,
    String? beforeSceneId,
    String? afterSceneId,
    List<String>? cast,
    List<ScreenplayElement>? elements,
  }) async {
    await service.validateSceneCreate(
      screenplayId: screenplayId,
      episodeId: episodeId,
      beatId: beatId,
      locationId: locationId,
      interiorExterior: interiorExterior,
      stage: stage,
      characterIds: cast,
      elements: elements,
    );
    final String id;
    try {
      id = await database.transaction(() async {
        final id = await service.createScene(
          screenplayId: screenplayId,
          episodeId: episodeId,
          beatId: beatId,
          interiorExterior: interiorExterior,
          locationId: locationId,
          timeLabel: timeLabel,
          synopsis: synopsis,
          title: title,
          emotion: emotion,
          events: events,
          stage: stage,
        );
        if (beforeSceneId != null) {
          await service.moveSceneBefore(id, beforeSceneId);
        }
        if (afterSceneId != null) {
          await service.moveSceneAfter(id, afterSceneId);
        }
        if (cast != null) {
          await service.replaceCast(sceneId: id, characterIds: cast);
        }
        if (elements != null) {
          await service.writeElementsInTransaction(
            sceneId: id,
            elements: elements,
          );
        }
        await stageCreateChange(id);
        return id;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=screenplay_scenes,screenplay_scene_elements,'
        'screenplay_scene_characters,working_changes operation=INSERT episode=$episodeId',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (elements != null) {
      await service.syncNovelWordCount();
    }
    return id;
  }
}
