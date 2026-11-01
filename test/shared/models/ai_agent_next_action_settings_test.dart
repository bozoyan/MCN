// 职责: 测试下一步建议开关的编解码与旧记录兼容 — 缺字段时默认开启，无 migration。
// 关联文件:
//   lib/shared/models/app_settings_aggregate_data.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/app_settings_aggregate_data.dart';

void main() {
  group('AiAgentSettingsData.nextActionSuggestions', () {
    test('默认开启', () {
      expect(AiAgentSettingsData.defaults.nextActionSuggestions, isTrue);
    });

    test('旧记录缺该字段 → 解码为 true（无 migration）', () {
      final legacy = jsonEncode({
        'version': 1,
        'identity': '旧身份',
        'soul': '旧人格',
        'avatarPath': '',
      });

      final decoded = AiAgentSettingsData.decode(legacy);

      expect(decoded.identity, '旧身份');
      expect(decoded.nextActionSuggestions, isTrue);
    });

    test('显式关闭后往返保持 false', () {
      final off = AiAgentSettingsData(
        identity: AiAgentSettingsData.defaults.identity,
        soul: AiAgentSettingsData.defaults.soul,
        avatarPath: '',
        nextActionSuggestions: false,
      );

      final restored = AiAgentSettingsData.decode(off.encode());

      expect(restored.nextActionSuggestions, isFalse);
    });

    test('schemaVersion 不变', () {
      expect(AiAgentSettingsData.currentVersion, 1);
      expect(jsonDecode(AiAgentSettingsData.defaults.encode())['version'], 1);
    });
  });
}
