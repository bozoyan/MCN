// 职责: 展示打光派生的光源方位、亮度、质感与色温字段。
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

class ProductionLightPanel extends StatelessWidget {
  const ProductionLightPanel({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ViewChoice<LightDirection>(
        field: ViewField.direction,
        label: context.t(LocaleKeys.productionViewDirection),
        options: {
          for (final value in LightDirection.values)
            value: context.t(
              '${LocaleKeys.productionViewOptions}.direction.${value.index}',
            ),
        },
      ),
      ViewChoice<LightBrightness>(
        field: ViewField.brightness,
        label: context.t(LocaleKeys.productionViewBrightness),
        options: {
          for (final value in LightBrightness.values)
            value: context.t(
              '${LocaleKeys.productionViewOptions}.brightness.${value.index}',
            ),
        },
      ),
      ViewChoice<LightTexture>(
        field: ViewField.texture,
        label: context.t(LocaleKeys.productionViewTexture),
        options: {
          for (final value in LightTexture.values)
            value: context.t(
              '${LocaleKeys.productionViewOptions}.texture.${value.index}',
            ),
        },
      ),
      ViewChoice<LightTemperature>(
        field: ViewField.temperature,
        label: context.t(LocaleKeys.productionViewTemperature),
        options: {
          for (final value in LightTemperature.values)
            value: context.t(
              '${LocaleKeys.productionViewOptions}.temperature.${value.index}',
            ),
        },
      ),
    ],
  );
}
