// 职责: 验证作品打开与维护提交交错时的读取边界和引用保护。
// 关联文件:
//   lib/shared/services/novel_maintenance_coordinator.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/novel_maintenance_coordinator.dart';

void main() {
  test('retained pages protect until the last page leaves', () async {
    final coordinator = NovelMaintenanceCoordinator();
    final first = coordinator.open('novel');
    final second = coordinator.open('novel');
    await first.ready;
    first.release();
    expect(coordinator.tryAcquireCleanup('novel'), isNull);
    second.release();
    second.release();
    final permit = coordinator.tryAcquireCleanup('novel');
    expect(permit, isNotNull);
    permit!.release();
  });

  test('opening during a commit waits and wins over the next tree', () async {
    final coordinator = NovelMaintenanceCoordinator();
    final permit = coordinator.tryAcquireCleanup('novel')!;
    final opening = coordinator.open('novel');
    var canRead = false;
    opening.ready.then((_) => canRead = true);
    await Future<void>.delayed(Duration.zero);
    expect(canRead, isFalse);
    expect(coordinator.tryAcquireCleanup('other'), isNotNull);
    permit.release();
    expect(coordinator.tryAcquireCleanup('novel'), isNull);
    await opening.ready;
    expect(canRead, isTrue);
    opening.release();
    expect(coordinator.tryAcquireCleanup('novel'), isNotNull);
  });
}
