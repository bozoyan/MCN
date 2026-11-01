// 职责: 制片画布生图工具栏的高级参数入口按钮,弹层内编辑请求级扩展参数。
// 关联文件:
//   lib/shared/widgets/production/image_request_extras_panel.dart
//   lib/shared/models/image/extras.dart
//   lib/shared/models/image/channels.dart
//   lib/desktop/features/production/popover.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/image/channels.dart';
import '../../../shared/models/image/extras.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/components/reveric_popover.dart';
import '../../../shared/widgets/production/image_request_extras_panel.dart';
import 'popover.dart';

/// 高级参数入口;当前模型不是魔搭/MOSS 协议时不渲染。
class ProductionImageExtrasButton extends StatelessWidget {
  const ProductionImageExtrasButton({
    super.key,
    required this.protocol,
    required this.value,
    required this.onChanged,
    this.modelId,
  });
  final ImageProtocol? protocol;
  final ImageRequestExtras? value;
  final ValueChanged<ImageRequestExtras?> onChanged;

  /// 当前选中的魔搭模型 Model-Id,用于确定建议采样步数;其他协议可为空。
  final String? modelId;

  bool get _supported =>
      protocol == ImageProtocol.modelscope_image ||
      protocol == ImageProtocol.moss_image;

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return const SizedBox.shrink();
    }
    return RevericPopover(
      up: true,
      trigger: (context, open, toggle) => ProductionToolButton(
        icon: RevericIcons.tune,
        open: open,
        tooltip: context.t(LocaleKeys.productionImageExtras),
        onTap: toggle,
      ),
      panel: (context, close) => ProductionPopoverPanel(
        width: 300,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(RevericSpacing.sm),
            child: ImageRequestExtrasPanel(
              protocol: protocol!,
              value: value,
              recommendedSteps: modelScopeRecommendedSteps(modelId ?? ''),
              onChanged: (v) {
                onChanged(v);
                if (v == null) {
                  close();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
