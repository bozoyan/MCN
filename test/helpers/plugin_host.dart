// 职责: 为不测试插件的 Agent 用例显式提供空插件注册表。
// 关联文件:
//   lib/shared/services/plugins/host.dart
//   lib/shared/services/plugins/registry.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/plugins/host.dart';
import 'package:reveric/shared/services/plugins/registry.dart';

PluginHostService emptyPluginHost() => _EmptyPluginHost();

class _EmptyPluginHost extends Fake implements PluginHostService {
  @override
  final registry = PluginRegistry(hostToolNames: {});
}
