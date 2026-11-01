// 职责: 保存画布场次引用的当前摘要及有效季、集身份，不复制正文。
// 关联文件:
//   lib/shared/models/screenplay.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';
import 'screenplay.dart';

class CanvasSceneReference {
  const CanvasSceneReference({
    required this.scene,
    required this.episode,
    required this.season,
  });

  final ScreenplaySceneSummary scene;
  final ScreenplayEpisodeRow episode;
  final ScreenplaySeasonRow season;
}
