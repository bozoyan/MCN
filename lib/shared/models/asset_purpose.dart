// 职责: 集中定义资产入库的业务场景取值（assets.purpose），入库方必须显式选择其一。
// 关联文件:
//   lib/shared/services/production/import_orchestrator.dart
//   lib/shared/services/production/library_service.dart
//   lib/shared/services/image_library_service.dart
// 遵循的 Rules:
//   .agents/rules/enum-naming.md

enum AssetPurpose {
  // 已发布版本写入过的取值，保持原字符串。
  reference('reference'),
  cover('cover'),
  avatar('avatar'),
  photo('photo'),
  map('map'),

  // 新取值按业务域加命名空间。
  ai_chat_generated('ai_chat.generated'),
  library_general('library.general'),
  director_scene_recognition('director.scene_recognition'),
  director_output('director.output'),
  production_upload('production.upload'),
  production_generated('production.generated'),
  production_video_tool('production.video_tool'),
  production_output('production.output'),
  editing_upload('editing.upload');

  const AssetPurpose(this.value);

  /// 写入 assets.purpose 的字符串。
  final String value;
}
