// 职责: 在全屏对话框中复用节点视角并提供关闭、重置与构图线操作。
// 关联文件:
//   lib/shared/widgets/production/panorama/viewer.dart
//   lib/shared/widgets/production/panorama/controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';
import '../../../components/reveric_button.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';
import 'controller.dart';
import 'viewer.dart';

Future<void> showPanoramaFullscreen(
  BuildContext context,
  String path,
  PanoramaController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    child: Stack(
      children: [
        Positioned.fill(
          child: PanoramaViewer(
            path: path,
            controller: controller,
            fullscreen: true,
          ),
        ),
        Positioned(
          left: RevericSpacing.x2l,
          top: RevericSpacing.x6l,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RevericButton.secondary(
                label: context.t(LocaleKeys.commonClose),
                icon: RevericIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: RevericSpacing.sm),
              RevericButton.secondary(
                label: context.t(LocaleKeys.productionViewPanoramaReset),
                onPressed: controller.reset,
              ),
              const SizedBox(height: RevericSpacing.sm),
              RevericButton.secondary(
                label: context.t(LocaleKeys.productionViewPanoramaGrid),
                onPressed: controller.toggleGrid,
              ),
            ],
          ),
        ),
      ],
    ),
  ),
).whenComplete(controller.flush);
