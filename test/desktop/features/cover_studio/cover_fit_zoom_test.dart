// 职责: 测试封面舞台「适应画布」缩放 — 按宽高取较小值并对齐步进。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/providers/cover_studio_providers.dart';

void main() {
  group('coverFitZoom', () {
    test('以较紧的一边为准，并向下对齐到 20% 步进', () {
      // 可用宽 ≈ 900-56-66-12=766 → 766/400*100 ≈ 191.5 → 受高限制
      // 可用高 ≈ 800-32-100=668；2:3 时 100% 高 = 400/(2/3)=600 → 668/600*100 ≈ 111
      // → 向下取步进得 100；取 120 会放不下，说明行与工具带会被顶出舞台。
      final zoom = coverFitZoom(
        stageWidth: 900,
        stageHeight: 800,
        aspectRatio: 2 / 3,
      );

      expect(zoom, 100);
    });

    test('舞台过小时回落 100，不崩', () {
      expect(
        coverFitZoom(stageWidth: 20, stageHeight: 20, aspectRatio: 2 / 3),
        100,
      );
    });
  });
}
