// 职责: macOS 自动升级重启脚本生成 — 构建退出后重新打开 app 的 shell 脚本
// 关联文件:
//   lib/shared/services/update/update_service.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

String buildMacOSRestartScript({
  required int processId,
  required String appPath,
  required String scriptPath,
}) {
  final app = shellSingleQuotedString(appPath);
  final script = shellSingleQuotedString(scriptPath);
  return '''
#!/bin/sh
set -u

process_id=$processId
app_path=$app
script_path=$script

while kill -0 "\$process_id" 2>/dev/null; do
  sleep 0.2
done

/usr/bin/open -n "\$app_path"
rm -f "\$script_path"
''';
}

String shellSingleQuotedString(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
