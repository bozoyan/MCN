// 职责: 编排通用二次确认弹窗的语义、异步提交和取消行为。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../components/reveric_button.dart';
import '../components/reveric_dialog.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

enum ConfirmDialogVariant { normal, warning, error }

/// 弹出确认对话框。返回 `true` 表示用户点击确认。
///
/// 仅适用于标题 + 正文 + 取消/确认 的最简场景；带表单、勾选、自定义
/// 交互的对话框使用 [RevericDialog]，自行处理其业务状态和返回值。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  ConfirmDialogVariant variant = ConfirmDialogVariant.normal,
  Future<void> Function()? onConfirm,
  Future<String?>? blockedReason,
  bool barrierDismissible = true,
}) async {
  return await showRevericDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) {
          return ConfirmDialog(
            title: title,
            message: message,
            confirmLabel:
                confirmLabel ?? dialogContext.t(LocaleKeys.commonConfirm),
            cancelLabel:
                cancelLabel ?? dialogContext.t(LocaleKeys.commonCancel),
            variant: variant,
            onConfirm: onConfirm,
            blockedReason: blockedReason,
          );
        },
      ) ??
      false;
}

class ConfirmDialog extends HookWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.variant = ConfirmDialogVariant.normal,
    this.onConfirm,
    this.blockedReason,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final ConfirmDialogVariant variant;
  final Future<void> Function()? onConfirm;

  /// 打开时执行的前置检查：完成前确认按钮不可点；结果非空时展示原因并保持禁用。
  /// 检查失败同样禁用确认，不放行。
  final Future<String?>? blockedReason;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final submitting = useState(false);
    final blockedSnapshot = useFuture(blockedReason);
    final String? blockedMessage;
    final bool blockedPending;
    if (blockedReason == null) {
      blockedMessage = null;
      blockedPending = false;
    } else if (blockedSnapshot.hasError) {
      blockedMessage = context.t(LocaleKeys.commonLoadFailed);
      blockedPending = false;
    } else {
      blockedMessage = blockedSnapshot.data;
      blockedPending = blockedSnapshot.connectionState != ConnectionState.done;
    }
    final confirmEnabled = !blockedPending && blockedMessage == null;
    final iconColor = switch (variant) {
      ConfirmDialogVariant.normal => colors.accent,
      ConfirmDialogVariant.warning => colors.warningText,
      ConfirmDialogVariant.error => colors.deletionBorder,
    };
    final iconBackground = switch (variant) {
      ConfirmDialogVariant.normal => colors.selected,
      ConfirmDialogVariant.warning => colors.warningBg,
      ConfirmDialogVariant.error => colors.deletionBg,
    };

    Future<void> confirm() async {
      if (submitting.value) {
        return;
      }
      submitting.value = true;
      try {
        await onConfirm?.call();
        if (context.mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (_) {
        if (context.mounted) {
          submitting.value = false;
        }
        rethrow;
      }
    }

    return PopScope(
      canPop: !submitting.value,
      child: RevericDialog(
        title: title,
        leading: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(RevericSizes.iconButtonPadding),
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: RevericIcon(
              switch (variant) {
                ConfirmDialogVariant.normal => RevericIcons.info_outline,
                ConfirmDialogVariant.warning => RevericIcons.warning,
                ConfirmDialogVariant.error => RevericIcons.delete_outline,
              },
              size: RevericSizes.iconButtonIconSize,
              color: iconColor,
            ),
          ),
        ),
        content: message == null && blockedMessage == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null)
                    Text(
                      message!,
                      style: typo.ui.copyWith(
                        color: colors.textSecondary,
                        height: typo.bodySmall.height,
                      ),
                    ),
                  if (message != null && blockedMessage != null)
                    const SizedBox(height: RevericSpacing.md),
                  if (blockedMessage != null)
                    Text(
                      blockedMessage,
                      style: typo.ui.copyWith(
                        color: colors.warningText,
                        height: typo.bodySmall.height,
                      ),
                    ),
                ],
              ),
        actions: [
          RevericButton.secondary(
            label: cancelLabel,
            onPressed: submitting.value
                ? null
                : () => Navigator.of(context).pop(false),
          ),
          if (variant == ConfirmDialogVariant.error)
            RevericButton.danger(
              label: confirmLabel,
              loading: submitting.value,
              onPressed: confirmEnabled ? confirm : null,
            )
          else
            RevericButton.primary(
              label: confirmLabel,
              loading: submitting.value,
              onPressed: confirmEnabled ? confirm : null,
            ),
        ],
      ),
    );
  }
}
