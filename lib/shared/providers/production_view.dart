// 职责: 上报制作视图和当前子页面，供工作区外壳显示面包屑、浮窗及 AI 定位当前调度。
// 关联文件:
//   lib/desktop/features/production/region.dart
//   lib/desktop/features/editing/region.dart
//   lib/shared/widgets/screenplay/director_workspace.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'production_view.g.dart';

/// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
///
/// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。
@riverpod
class ProductionSegmentsView extends _$ProductionSegmentsView {
  @override
  bool build(String novelId) => true;

  void set(bool segments) {
    // 制片页卸载时延后写入，外壳可能已经先释放了这个 provider。
    if (!ref.mounted || state == segments) {
      return;
    }
    state = segments;
  }
}

typedef ProductionSubpageContext = ({String label, String? stagingId});

/// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
///
/// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。
@riverpod
class ProductionSubpage extends _$ProductionSubpage {
  @override
  ProductionSubpageContext? build(String databasePath) => null;

  void set(ProductionSubpageContext? page) {
    // 子页面卸载时延后写入，外壳可能已经先释放了这个 provider。
    if (!ref.mounted || state == page) {
      return;
    }
    state = page;
  }

  void clear(ProductionSubpageContext page) {
    if (ref.mounted && state == page) {
      set(null);
    }
  }
}
