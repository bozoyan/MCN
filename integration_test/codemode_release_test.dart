// 职责: 用 Release 应用 target 汇集原生边界、资源回收与真实数据工具验收。
// 关联文件:
//   integration_test/codemode_native_test.dart
//   integration_test/codemode_resources_test.dart
//   integration_test/codemode_data_test.dart
import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test.dart';

import 'codemode_native_test.dart' as native;
import 'codemode_resources_test.dart' as resources;
import 'codemode_data_test.dart' as data;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('CODEMODE_STANDALONE_PROBE')) {
    unawaited(
      binding.allTestsPassed.future.then((passed) {
        stdout.writeln('CODEMODE_RELEASE_PROBE_PASSED=$passed');
        exit(passed ? 0 : 1);
      }),
    );
  }
  resources.main();
  data.main();
  native.main(initializeLibrary: false);
}
