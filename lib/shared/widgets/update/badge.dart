// 职责: 在移动端设置入口上显示新版本圆点且保持原有尺寸。
// 关联文件:
//   lib/shared/providers/update_providers.dart
//   lib/mobile/widgets/tab_bar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/update_providers.dart';
import '../../theme/theme.dart';

class UpdateBadge extends ConsumerWidget {
  const UpdateBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableUpdateProvider) != null;
    return Semantics(
      label: available
          ? context.t(LocaleKeys.settingsAboutUpdateAvailable)
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (available)
            Positioned(
              top: -RevericSpacing.xxs,
              right: -RevericSpacing.xxs,
              child: Container(
                width: RevericSpacing.sm,
                height: RevericSpacing.sm,
                decoration: BoxDecoration(
                  color: RevericTheme.colorsOf(context).accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
