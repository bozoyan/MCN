// 职责: macOS 自动升级重启脚本测试 — 验证退出后重新打开 app 与路径转义
// 关联文件:
//   lib/shared/services/update/macos_restart_script.dart
//   lib/shared/services/update/update_service.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/update/macos_restart_script.dart';

void main() {
  group('buildMacOSRestartScript', () {
    test('waits for the running app before opening the replacement app', () {
      final script = buildMacOSRestartScript(
        processId: 42,
        appPath: '/Applications/Reveric.app',
        scriptPath: '/tmp/reveric_restart.sh',
      );

      expect(script, contains('process_id=42'));
      expect(
        script.indexOf(r'while kill -0 "$process_id"'),
        lessThan(script.indexOf(r'/usr/bin/open -n "$app_path"')),
      );
      expect(
        script.indexOf(r'/usr/bin/open -n "$app_path"'),
        lessThan(script.indexOf(r'rm -f "$script_path"')),
      );
    });

    test('quotes shell single-quoted string literals', () {
      expect(
        shellSingleQuotedString("/Applications/Reveric O'Clock.app"),
        "'/Applications/Reveric O'\"'\"'Clock.app'",
      );
    });
  });
}
