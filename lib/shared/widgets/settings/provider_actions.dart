// 职责: 提供供应商桌面操作菜单与跨平台删除确认流程。
// 关联文件:
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/widgets/settings/mobile_provider_list.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/localization/ai_provider_localization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../components/reveric_context_menu.dart';
import '../../localization/ai_provider_localization.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/ai_provider.dart';
import '../../theme/theme.dart';
import '../confirm_dialog.dart';

class ProviderActionsMenu extends StatelessWidget {
  const ProviderActionsMenu({
    super.key,
    required this.config,
    required this.onDelete,
  });

  final AiProvider config;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (!config.canDelete ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: RevericSpacing.xs),
      child: Builder(
        builder: (buttonContext) => IconButton(
          tooltip: context.t(LocaleKeys.commonMoreActions),
          padding: const EdgeInsets.all(RevericSpacing.xs),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RevericRadius.small),
            ),
          ),
          icon: RevericIcon(
            RevericIcons.more_horiz,
            size: 18,
            color: colors.textMuted,
          ),
          onPressed: () {
            final box = buttonContext.findRenderObject()! as RenderBox;
            showRevericContextMenu(
              context: context,
              position: box.localToGlobal(Offset(0, box.size.height)),
              entries: [
                RevericMenuItem(
                  icon: RevericIcons.delete,
                  iconColor: colors.warningText,
                  labelColor: colors.warningText,
                  label: context.t(LocaleKeys.commonDelete),
                  onTap: onDelete,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<bool> confirmDeleteProvider(
  BuildContext context, {
  required AiProvider config,
  required Future<void> Function() onDelete,
}) async {
  if (!config.canDelete) {
    return false;
  }
  final confirmed = await showConfirmDialog(
    context,
    title: context.t(LocaleKeys.commonDelete),
    message: context.t(
      LocaleKeys.settingsDeleteProviderConfirm,
      namedArgs: {'name': localizedAiProviderName(context, config)},
    ),
    confirmLabel: context.t(LocaleKeys.commonDelete),
    variant: ConfirmDialogVariant.error,
  );
  if (confirmed != true) {
    return false;
  }
  try {
    await onDelete();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.commonDeleteFailed))),
      );
    }
    return false;
  }
}
