// 职责: 验证设备 ID 在升级后继续复用既有持久化值。
// 关联文件:
//   lib/shared/services/device_id_service.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/device_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reuses a persisted device ID without a source marker', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'legacy-device-id'});

    final deviceId = await DeviceIdService().getOrCreate();

    expect(deviceId, 'legacy-device-id');
  });

  test('regenerates and persists a new device ID for debug use', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'old-device-id'});
    final service = DeviceIdService();

    final deviceId = await service.regenerate();
    final persistedDeviceId = await service.getOrCreate();

    expect(deviceId, isNot('old-device-id'));
    expect(persistedDeviceId, deviceId);
  });
}
