// 职责: 验证官方技能读取本地打包目录，不依赖账号和市场网络连接。
// 关联文件:
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/services/bundled_official_skills.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/agent_skill_catalog_service.dart';

void main() {
  AgentSkillCatalogService service() {
    return AgentSkillCatalogService(assetBundle: _FileAssetBundle());
  }

  test('getOfficial returns bundled detail by name', () async {
    final result = await service().getOfficial(listingId: '章节规划');
    expect(result.listingId, '章节规划');
    expect(result.whenToUse, isNotEmpty);
    expect(result.prompt, contains('小周期推进'));
  });
  test('getOfficial rejects an unknown bundled skill name', () async {
    await expectLater(
      service().getOfficial(listingId: 'no-such-skill'),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.name, 'name', 'listingId')
            .having((e) => e.invalidValue, 'invalidValue', 'no-such-skill'),
      ),
    );
  });
}

class _FileAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
