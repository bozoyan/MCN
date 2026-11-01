// 职责: 本机设置模型 — 描述 settings.local.json 中只对当前设备有效、不进入应用备份的设置。
// 关联文件:
//   lib/shared/services/file_workspace_orchestrator.dart

class LocalSettings {
  const LocalSettings({this.fileWorkspaceDirectory});

  factory LocalSettings.fromJson(Map<String, dynamic> json) => LocalSettings(
    fileWorkspaceDirectory: json['file_workspace_directory'] as String?,
  );

  /// file_workspaces 文件夹的绝对路径；null 表示应用目录下的默认位置。
  final String? fileWorkspaceDirectory;

  Map<String, dynamic> toJson() => {
    'file_workspace_directory': fileWorkspaceDirectory,
  };
}
