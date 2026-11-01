// 职责: 更新源抽象 — UpdateSource 接口定义
// 关联文件:
//   lib/shared/services/update/models.dart
//   lib/shared/services/update/sources/custom_api_source.dart
//   lib/shared/services/update/sources/github_releases_source.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'models.dart';

/// 更新源抽象 — 可替换为 GitHub Releases / 自建 API / 其他
abstract class UpdateSource {
  Future<UpdateCheckResult> checkForUpdate(String currentVersion);
}
