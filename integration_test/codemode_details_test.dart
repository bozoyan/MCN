// 职责: 在原生 Flutter 窗口复用批量调用详情的标签与按需解析回归测试。
// 关联文件:
//   test/shared/widgets/ai/codemode_tool_test.dart
//   lib/shared/widgets/ai/tools/codemode_detail_dialog.dart
import 'package:integration_test/integration_test.dart';

import '../test/shared/widgets/ai/codemode_tool_test.dart' as details;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  details.main();
}
