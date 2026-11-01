// 职责: 封面设计师面板的生图高级参数区块,按当前模型协议编辑请求级扩展参数。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart
//   lib/shared/widgets/cover_studio/sections.dart
//   lib/shared/widgets/production/image_request_extras_panel.dart
//   lib/shared/models/image/channels.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/image/channels.dart';
import '../../../shared/models/image/extras.dart';
import '../../../shared/providers/ai_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/chips.dart';
import '../../../shared/widgets/production/image_request_extras_panel.dart';

/// 当前封面模型支持请求级参数(魔搭/MOSS)时显示;其余协议隐藏整块。
class CoverImageExtrasSection extends ConsumerWidget {
  const CoverImageExtrasSection({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ImageRequestExtras? value;
  final ValueChanged<ImageRequestExtras?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(coverStudioImageModelSelectionProvider);
    final protocol = selection?.config.typeConfig.imageProtocol;
    final supported =
        protocol == ImageProtocol.modelscope_image ||
        protocol == ImageProtocol.moss_image;
    if (!supported || selection == null || protocol == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverSectionHead(
          icon: RevericIcons.tune,
          label: context.t(LocaleKeys.productionImageExtras),
        ),
        const SizedBox(height: RevericSpacing.sm),
        ImageRequestExtrasPanel(
          protocol: protocol,
          value: value,
          recommendedSteps: modelScopeRecommendedSteps(selection.model),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
