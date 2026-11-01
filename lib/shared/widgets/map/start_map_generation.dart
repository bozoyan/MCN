// 职责: 为还没有 Map 记录的地点落库并出图 — 待生成地图点「开始制作」时的唯一入口。
// 关联文件:
//   lib/shared/providers/map_studio_controller.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/widgets/map/location_types.dart
//   lib/desktop/features/map/map_studio_page.dart
//   lib/mobile/features/map/studio_page.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../database/novel_content_database.dart';
import '../../providers/map_studio_controller.dart';
import '../../providers/maps_providers.dart';
import '../../services/generate_map_orchestrator.dart';
import 'location_types.dart';

/// 进入待生成状态本身不会写库；只有作者明确点击生成时，才创建 [owner]
/// 唯一对应的 Map 记录，再按 [request] 出图。
Future<void> startMapGenerationForLocation(
  WidgetRef ref, {
  required String databasePath,
  required String novelId,
  required Location owner,
  required MapGenerationRequest request,
}) async {
  final mapId = await ref
      .read(mapsServiceProvider(databasePath))
      .getOrCreateMapForLocation(
        locationId: owner.id,
        name: owner.name,
        type: mapTypeForOwner(owner),
      );

  // 新 Map 出现在 stream 并切换到正式工作台前，主动监听 controller，
  // 保证 autoDispose provider 不会在首次 await 时取消刚启动的操作。
  final provider = mapStudioControllerProvider(databasePath, mapId);
  final subscription = ref.listenManual(provider, (previous, next) {});
  try {
    await ref
        .read(provider.notifier)
        .generate(request, novelId: novelId, sourceMapName: owner.name);
  } finally {
    subscription.close();
  }
}
