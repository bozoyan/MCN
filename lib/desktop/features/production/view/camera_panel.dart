// 职责: 展示镜头派生的水平、垂直与景别字段。
// 关联文件:
//   lib/desktop/features/production/view/form.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
import 'package:flutter/material.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/production/view_presets.dart';
import 'field.dart';
import 'form.dart';

class ProductionCameraPanel extends StatelessWidget {
  const ProductionCameraPanel({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ViewChoice<int>(
        field: ViewField.yaw,
        label: context.t(LocaleKeys.productionViewYaw),
        options: {
          for (final value in cameraYawFragments.keys) value: '$value°',
        },
      ),
      ViewChoice<int>(
        field: ViewField.pitch,
        label: context.t(LocaleKeys.productionViewPitch),
        options: {
          for (final value in cameraPitchFragments.keys) value: '$value°',
        },
      ),
      ViewChoice<CameraFraming>(
        field: ViewField.framing,
        label: context.t(LocaleKeys.productionViewFraming),
        options: {
          for (final value in CameraFraming.values)
            value: context.t(
              '${LocaleKeys.productionViewOptions}.framing.${value.index}',
            ),
        },
      ),
    ],
  );
}
